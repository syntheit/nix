"""fajita-textgrab-atspi — the AT-SPI backend for the GNOME Shell Mobile
long-press text-grab feature ("long-press -> read text -> Copy").

Contract
--------
Given a --pid and a window-local (x, y) point plus a --granularity, this
program emits EXACTLY ONE JSON line to stdout:

    {"text": "...", "boxes": [{"x": .., "y": .., "w": .., "h": ..}, ...]}

with all coordinates in WINDOW-LOCAL pixels, OR:

    {}

if nothing is found / the leaf has no Text interface / the text is empty.

The WINDOW coordinates come from the shell's window frame rect (the shell
passes us the point already translated into window-local space, and we ask
AT-SPI for extents in Atspi.CoordType.WINDOW so everything stays in the same
frame).

Failure policy
--------------
This helper fails CLOSED to `{}` on ANY error, so the shell can fall back to
OCR. It never crashes, and never writes anything but the single JSON line to
stdout. All diagnostics go to stderr only. It always exits 0.

Note on GTK4
------------
GTK4 apps expose GtkLabel via Gtk.AccessibleText unconditionally (>= GTK 4.14),
so even non-selectable labels are readable through the AT-SPI Text interface.
"""

import argparse
import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib  # noqa: E402  (must follow require_version)


def warn(*args):
    """Emit a diagnostic to stderr only. NEVER writes to stdout."""
    print(*args, file=sys.stderr)


def resolve(pid, x, y, granularity):
    """Resolve the text under (x, y) in the app owning `pid`.

    Returns a result dict {"text": ..., "boxes": [...]} on success, or None
    (which the caller renders as `{}`) when nothing usable is found.
    """
    # 1. Grab the root desktop accessible.
    desktop = Atspi.get_desktop(0)

    # 2. Find the application accessible whose process id matches `pid`.
    app = None
    for i in range(desktop.get_child_count()):
        try:
            candidate = desktop.get_child_at_index(i)
            if candidate is None:
                continue
            # A dead/hung app can throw on any of these calls.
            if candidate.get_process_id() == pid:
                app = candidate
                break
        except Exception as exc:  # noqa: BLE001  (fail closed, keep scanning)
            warn("skipping app at index", i, "->", exc)
            continue

    if app is None:
        warn("no app matched pid", pid)
        return None

    # 3. Descend to the leaf accessible under the point. The app accessible
    #    implements Component, so we can hit-test from the top down. We keep the
    #    full descent path so we can later pick the deepest text-bearing node.
    path = [app]
    node = app
    depth = 0
    while depth < 50:
        try:
            child = node.get_accessible_at_point(
                int(x), int(y), Atspi.CoordType.WINDOW
            )
        except Exception as exc:  # noqa: BLE001
            warn("get_accessible_at_point threw at depth", depth, "->", exc)
            break
        # Stop on: no child, or the same node returned (identity/equality).
        if child is None or child == node:
            break
        path.append(child)
        node = child
        depth += 1

    # 4. Pick the DEEPEST node in the descent path that has a Text interface
    #    with a non-empty character count.
    textnode = None
    for candidate in reversed(path):
        try:
            interfaces = candidate.get_interfaces()
        except Exception as exc:  # noqa: BLE001
            warn("get_interfaces threw ->", exc)
            continue
        if "Text" not in interfaces:
            continue
        try:
            if candidate.get_character_count() > 0:
                textnode = candidate
                break
        except Exception as exc:  # noqa: BLE001
            warn("get_character_count threw ->", exc)
            continue

    if textnode is None:
        warn("no text node under point", x, y, "for pid", pid)
        return None

    # 5. Map the window-local point to a character offset within the text node.
    offset = textnode.get_offset_at_point(int(x), int(y), Atspi.CoordType.WINDOW)
    if offset < 0:
        warn("negative offset at point", x, y)
        return None

    # 6. Granularity map. Enum members are LINE/WORD/PARAGRAPH.
    gran_map = {
        "line": Atspi.TextGranularity.LINE,
        "word": Atspi.TextGranularity.WORD,
        "paragraph": Atspi.TextGranularity.PARAGRAPH,
    }
    gran = gran_map[granularity]

    # 7. Grab the string spanning the requested granularity around the offset.
    rng = textnode.get_string_at_offset(offset, gran)
    if rng is None or rng.content is None or rng.content.strip() == "":
        warn("empty/whitespace text range at offset", offset)
        return None

    # 8. Compute the bounding box(es) for the range, window-local.
    boxes = []
    rect = textnode.get_range_extents(
        rng.start_offset, rng.end_offset, Atspi.CoordType.WINDOW
    )
    if rect is not None and rect.width > 0 and rect.height > 0:
        # Preferred: a single merged rect for the whole range.
        boxes = [
            {"x": rect.x, "y": rect.y, "w": rect.width, "h": rect.height}
        ]
    else:
        # Fallback: per-character extents. One bad char must not abort.
        boxes = []
        for o in range(rng.start_offset, rng.end_offset):
            try:
                ce = textnode.get_character_extents(o, Atspi.CoordType.WINDOW)
                if ce is not None and ce.width > 0 and ce.height > 0:
                    boxes.append(
                        {"x": ce.x, "y": ce.y, "w": ce.width, "h": ce.height}
                    )
            except Exception as exc:  # noqa: BLE001
                warn("get_character_extents threw at offset", o, "->", exc)
                continue

    # 9. Return the text plus whatever boxes we found (may be [] if text
    #    present but no extents resolved).
    return {"text": rng.content, "boxes": boxes}


def main():
    parser = argparse.ArgumentParser(
        prog="fajita-textgrab-atspi",
        description="AT-SPI long-press text-grab backend for GNOME Shell Mobile.",
    )
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--x", type=float, required=True, help="window-local px")
    parser.add_argument("--y", type=float, required=True, help="window-local px")
    parser.add_argument(
        "--granularity",
        choices=["line", "word", "paragraph"],
        default="line",
    )
    args = parser.parse_args()

    result = None
    initialized = False
    try:
        # Bound D-Bus round trips so a hung app can't stall us. Both msec.
        Atspi.set_timeout(800, 15000)
        # Atspi.init() returns 0 on success. Call once.
        rc = Atspi.init()
        if rc != 0:
            warn("Atspi.init() returned nonzero:", rc)
            result = None
        else:
            initialized = True
            result = resolve(args.pid, args.x, args.y, args.granularity)
    except Exception as exc:  # noqa: BLE001  (fail closed to {})
        warn("unhandled exception during resolution ->", exc)
        result = None
    finally:
        # Only tear down if init actually succeeded.
        if initialized:
            try:
                Atspi.exit()
            except Exception as exc:  # noqa: BLE001
                warn("Atspi.exit() threw ->", exc)

    # The ONLY thing ever written to stdout: one JSON line.
    if result:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print("{}")
    sys.exit(0)


if __name__ == "__main__":
    main()
