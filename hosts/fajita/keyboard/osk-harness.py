#!/usr/bin/env python3
# osk-harness.py — headless ibus-typing-booster regression harness for fajita.
# See ~/fajita-notes/keyboard-prediction.md section "harness usage" for deploy
# runbook (engine python-env discovery, mandatory flags, battery cases).
# ALWAYS run with: --no-surround --reset-after-commit 30
"""Headless typing harness for ibus-typing-booster on fajita.

Emulates an application + OSK exactly the way GNOME Shell does:
- keys go in via process_key_event_async(keyval, 0, 0) -- press, then a
  release IF the press was consumed (mirrors inputMethod.js handleVirtualKey);
  if the press was NOT consumed, the char is appended directly (mirrors the
  shell's raw-keyval fallback, which on a real phone types the char).
- commit-text / delete-surrounding-text signals mutate a local text buffer
  (the "screen").
- surrounding-text is pushed back to the engine, optionally LAGGED by N
  pending events to reproduce the real client's stale view.
- --gesture WORD[,WORD...]: synthesize a PUA-framed trace per word using the
  us-mobile QWERTY geometry (plan section 8.1), then inject press-only key
  events (F8D0 ... letters ... F8D1).

Usage:
  osk-harness.py [--lag N] [--shell-caps] [--no-surround]
                 [--reset-after-commit MS]
                 text
  osk-harness.py --gesture hola,que,hello [--shell-caps] [--no-surround]
                 [--reset-after-commit MS]
Prints a per-event trace and the final screen text.
"""
import argparse
import sys
import math
import unicodedata

import gi
gi.require_version('IBus', '1.0')
from gi.repository import IBus, GLib  # noqa: E402


# ---- us-mobile QWERTY geometry (single source of truth, plan section 8.1) ---
# Key centres: (col_centre, row_centre) in key-width units.
# Row x-offsets: row0=0, row1=0.5, row2=1.5 key-widths.
_KEY_CENTERS = {
    'q': (0.5,  0.5), 'w': (1.5,  0.5), 'e': (2.5,  0.5),
    'r': (3.5,  0.5), 't': (4.5,  0.5), 'y': (5.5,  0.5),
    'u': (6.5,  0.5), 'i': (7.5,  0.5), 'o': (8.5,  0.5),
    'p': (9.5,  0.5),
    'a': (1.0,  1.5), 's': (2.0,  1.5), 'd': (3.0,  1.5),
    'f': (4.0,  1.5), 'g': (5.0,  1.5), 'h': (6.0,  1.5),
    'j': (7.0,  1.5), 'k': (8.0,  1.5), 'l': (9.0,  1.5),
    'z': (2.0,  2.5), 'x': (3.0,  2.5), 'c': (4.0,  2.5),
    'v': (5.0,  2.5), 'b': (6.0,  2.5), 'n': (7.0,  2.5),
    'm': (8.0,  2.5),
}

# Adjacency: neighbours within 1.1 key-widths (used for anchor detection)
def _build_neighbors():
    nb = {}
    for a, (ax, ay) in _KEY_CENTERS.items():
        nb[a] = [b for b, (bx, by) in _KEY_CENTERS.items()
                 if math.sqrt((ax-bx)**2 + (ay-by)**2) <= 1.1]
    return nb
_NEIGHBORS = _build_neighbors()


def _key_seq(word):
    """Canonical key-sequence for a word: casefold, strip accents, a-z only,
    collapse consecutive duplicates. Returns '' if result < 2 chars."""
    casefolded = unicodedata.normalize('NFD', word.casefold())
    stripped = ''.join(c for c in casefolded if unicodedata.category(c) != 'Mn')
    only_az = ''.join(c for c in stripped if 'a' <= c <= 'z')
    if not only_az:
        return ''
    collapsed = only_az[0]
    for c in only_az[1:]:
        if c != collapsed[-1]:
            collapsed += c
    return collapsed if len(collapsed) >= 2 else ''


def _make_trace(word):
    """Synthesize a gesture trace for word using the us-mobile geometry.

    Returns (letters: str, anchors: list[int], shift: bool).
    The trace is the per-key-centre path of the canonical key sequence,
    sampled at 0.3 key-width steps; keys that are waypoints (first, last,
    corners with angle >60 deg) are marked as anchors.
    """
    shift = word[0].isupper() if word else False
    ks = _key_seq(word)
    if not ks:
        return ks, [], shift

    # Waypoints: key centres in order
    waypoints = [_KEY_CENTERS[c] for c in ks if c in _KEY_CENTERS]
    if not waypoints:
        return ks, [], shift

    # Sample path at 0.3 key-width step density
    path = []
    STEP = 0.3
    for i in range(len(waypoints) - 1):
        x0, y0 = waypoints[i]
        x1, y1 = waypoints[i+1]
        dist = math.sqrt((x1-x0)**2 + (y1-y0)**2)
        steps = max(1, int(dist / STEP))
        for s in range(steps):
            t = s / steps
            path.append((x0 + t*(x1-x0), y0 + t*(y1-y0)))
    path.append(waypoints[-1])

    # Map each path point to nearest key
    def nearest_key(x, y):
        best = None
        best_d = float('inf')
        for k, (kx, ky) in _KEY_CENTERS.items():
            d = (x-kx)**2 + (y-ky)**2
            if d < best_d:
                best_d = d
                best = k
        return best

    keys_on_path = []
    for (x, y) in path:
        k = nearest_key(x, y)
        if not keys_on_path or k != keys_on_path[-1]:
            keys_on_path.append(k)

    # Keep only keys that are in ks (in order) -- filter the path back
    # to the canonical key sequence
    letters = ks  # the canonical trace IS the key sequence

    # Anchor detection: waypoints in the canonical sequence are anchors
    # (first + last always anchored, plus any with direction change > 60 deg)
    anchors = [0, len(ks) - 1]
    for i in range(1, len(ks) - 1):
        if ks[i] not in _KEY_CENTERS:
            continue
        prev_k = ks[i-1] if ks[i-1] in _KEY_CENTERS else None
        next_k = ks[i+1] if i+1 < len(ks) and ks[i+1] in _KEY_CENTERS else None
        if prev_k and next_k:
            cx, cy = _KEY_CENTERS[ks[i]]
            px, py = _KEY_CENTERS[prev_k]
            nx, ny = _KEY_CENTERS[next_k]
            # vectors: incoming and outgoing
            v1 = (cx-px, cy-py)
            v2 = (nx-cx, ny-cy)
            dot = v1[0]*v2[0] + v1[1]*v2[1]
            m1 = math.sqrt(v1[0]**2 + v1[1]**2)
            m2 = math.sqrt(v2[0]**2 + v2[1]**2)
            if m1 > 0 and m2 > 0:
                cos_a = max(-1.0, min(1.0, dot / (m1 * m2)))
                angle = math.degrees(math.acos(cos_a))
                if angle > 60:
                    anchors.append(i)

    anchors = sorted(set(anchors))
    return letters, anchors, shift


# ---- PUA keyvals (plan section 3) ------------------------------------------
_KV_GESTURE_START  = 0x01000000 | 0xF8D0
_KV_GESTURE_END    = 0x01000000 | 0xF8D1
_KV_GESTURE_ANCHOR = 0x01000000 | 0xF8D2
_KV_GESTURE_SHIFT  = 0x01000000 | 0xF8D4


class Harness:
    def __init__(self, lag, osk_cap, shell_caps=False, no_surround=False,
                 reset_after_commit=0):
        self.lag = lag
        self.reset_after_commit = reset_after_commit
        self.text = ''
        self.preedit = ''
        self.preedit_ever = []
        self.candidates_log = []
        self.pending_surrounding = []
        self.loop = GLib.MainLoop()
        self.bus = IBus.Bus()
        if not self.bus.is_connected():
            sys.exit('cannot connect to ibus bus')
        self.ctx = self.bus.create_input_context('osk-harness')
        if shell_caps:
            caps = IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.FOCUS
            if not no_surround:
                caps |= IBus.Capabilite.SURROUNDING_TEXT
            if hasattr(IBus.Capabilite, 'OSK'):
                caps |= IBus.Capabilite.OSK
        else:
            caps = (IBus.Capabilite.PREEDIT_TEXT
                    | IBus.Capabilite.FOCUS
                    | IBus.Capabilite.SURROUNDING_TEXT
                    | IBus.Capabilite.LOOKUP_TABLE
                    | IBus.Capabilite.AUXILIARY_TEXT)
            if osk_cap and hasattr(IBus.Capabilite, 'OSK'):
                caps |= IBus.Capabilite.OSK
        self.no_surround = no_surround
        self.ctx.set_capabilities(caps)
        self.ctx.connect('commit-text', self.on_commit)
        self.ctx.connect('delete-surrounding-text', self.on_delete)
        self.ctx.connect('update-preedit-text', self.on_preedit)
        self.ctx.connect('update-lookup-table', self.on_lookup)
        ge = self.bus.get_global_engine()
        self.prev_engine = ge.get_name() if ge else None
        print(f'global engine before: {self.prev_engine}')
        self.bus.set_global_engine('typing-booster')
        self.ctx.focus_in()
        self.push_surrounding(force=True)

    # --- app model ----------------------------------------------------------
    def on_commit(self, _ctx, ibus_text):
        s = ibus_text.get_text()
        self.text += s
        print(f'  COMMIT {s!r:12} screen={self.text!r}')
        self.queue_surrounding()
        if self.reset_after_commit:
            # mimic mutter/gnome-shell: the client resets the input context
            # shortly after applying a commit (inputMethod.js vfunc_reset)
            def do_reset():
                print('  CLIENT-RESET (mimicking mutter post-commit reset)')
                self.ctx.reset()
                return GLib.SOURCE_REMOVE
            GLib.timeout_add(self.reset_after_commit, do_reset)

    def on_delete(self, _ctx, offset, nchars):
        # offset is relative to cursor (cursor at end of self.text)
        start = len(self.text) + offset
        end = start + nchars
        removed = self.text[start:end]
        self.text = self.text[:start] + self.text[end:]
        print(f'  DELETE offset={offset} n={nchars} removed={removed!r} '
              f'screen={self.text!r}')
        self.queue_surrounding()

    def on_preedit(self, _ctx, ibus_text, _cursor, _visible):
        self.preedit = ibus_text.get_text()
        if self.preedit:
            self.preedit_ever.append(self.preedit)
            print(f'  PREEDIT {self.preedit!r}   <-- should never happen')

    def on_lookup(self, _ctx, table, _visible):
        cands = []
        for i in range(min(table.get_number_of_candidates(), 5)):
            cands.append(table.get_candidate(i).get_text())
        if cands:
            self.candidates_log.append(cands)
            print(f'  CANDIDATES {cands}')

    # --- surrounding text with optional lag ---------------------------------
    def queue_surrounding(self):
        self.pending_surrounding.append(self.text)
        while len(self.pending_surrounding) > self.lag:
            state = self.pending_surrounding.pop(0)
            self.send_surrounding(state)

    def push_surrounding(self, force=False):
        if force:
            while self.pending_surrounding:
                self.send_surrounding(self.pending_surrounding.pop(0))
            self.send_surrounding(self.text)

    def send_surrounding(self, state):
        if self.no_surround:
            return
        t = IBus.Text.new_from_string(state)
        self.ctx.set_surrounding_text(t, len(state), len(state))

    # --- key input ----------------------------------------------------------
    def press(self, char):
        """Send a single character keypress. Returns consumed bool."""
        keyval = IBus.unicode_to_keyval(char)
        consumed = {'v': None}

        def on_press(ctx, res):
            try:
                consumed['v'] = ctx.process_key_event_async_finish(res)
            except GLib.Error as e:
                print(f'  press error: {e}')
                consumed['v'] = False
            self.loop.quit()

        self.ctx.process_key_event_async(keyval, 0, 0, -1, None, on_press)
        self.loop.run()
        if consumed['v']:
            # mirror handleVirtualKey: send release, ignore result
            def on_release(ctx, res):
                try:
                    ctx.process_key_event_async_finish(res)
                except GLib.Error:
                    pass
                self.loop.quit()
            self.ctx.process_key_event_async(
                keyval, 0, IBus.ModifierType.RELEASE_MASK, -1, None,
                on_release)
            self.loop.run()
        else:
            # shell fallback: raw keyval -> app receives the char
            self.text += char
            print(f'  FALLBACK {char!r}  screen={self.text!r}')
            self.queue_surrounding()
        return consumed['v']

    def press_keyval(self, keyval, press_only=False):
        """Send a keyval directly (press-only, no release -- mirrors injectGestureTrace).
        Always returns True (PUA markers are always consumed by the engine)."""
        consumed = {'v': None}

        def on_press(ctx, res):
            try:
                consumed['v'] = ctx.process_key_event_async_finish(res)
            except GLib.Error as e:
                print(f'  press_keyval error kv=0x{keyval:08x}: {e}')
                consumed['v'] = False
            self.loop.quit()

        self.ctx.process_key_event_async(keyval, 0, 0, -1, None, on_press)
        self.loop.run()
        return consumed['v']

    def inject_gesture(self, word):
        """Synthesize and inject a PUA-framed gesture trace for word.

        Follows plan section 5.5 injectGestureTrace: press-only, same-
        connection ordering guaranteed, await on the last event."""
        letters, anchors, shift = _make_trace(word)
        print(f'  GESTURE word={word!r} ks={letters!r} anchors={anchors} shift={shift}')
        anchor_set = set(anchors)
        seq = [_KV_GESTURE_START]
        if shift:
            seq.append(_KV_GESTURE_SHIFT)
        for i, c in enumerate(letters):
            if i in anchor_set:
                seq.append(_KV_GESTURE_ANCHOR)
            kv = IBus.unicode_to_keyval(c)
            if kv == IBus.KEY_VoidSymbol:
                kv = 0x01000000 | ord(c)
            seq.append(kv)
        seq.append(_KV_GESTURE_END)

        # Send all but last fire-and-forget; await last (mirrors injectGestureTrace)
        for kv in seq[:-1]:
            self.press_keyval(kv, press_only=True)
        # Await final (F8D1) -- this is when the engine decodes and commits
        self.press_keyval(seq[-1], press_only=True)

    def inject_gesture_raw(self, raw):
        """Inject a raw trace string: 'holkjhgfa:0,3,8[:shift]'
        Format: letters:anchor_indices[:shift]"""
        parts = raw.split(':')
        letters = parts[0]
        anchors = [int(x) for x in parts[1].split(',') if x] if len(parts) > 1 else []
        shift = len(parts) > 2 and parts[2] == 'shift'
        print(f'  GESTURE-RAW trace={letters!r} anchors={anchors} shift={shift}')
        anchor_set = set(anchors)
        seq = [_KV_GESTURE_START]
        if shift:
            seq.append(_KV_GESTURE_SHIFT)
        for i, c in enumerate(letters):
            if i in anchor_set:
                seq.append(_KV_GESTURE_ANCHOR)
            kv = IBus.unicode_to_keyval(c)
            if kv == IBus.KEY_VoidSymbol:
                kv = 0x01000000 | ord(c)
            seq.append(kv)
        seq.append(_KV_GESTURE_END)
        for kv in seq[:-1]:
            self.press_keyval(kv, press_only=True)
        self.press_keyval(seq[-1], press_only=True)

    def settle(self, ms):
        GLib.timeout_add(ms, self.loop.quit)
        self.loop.run()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lag', type=int, default=0,
                    help='surrounding-text updates held back N events')
    ap.add_argument('--osk-cap', action='store_true',
                    help='advertise IBus.Capabilite.OSK')
    ap.add_argument('--shell-caps', action='store_true')
    ap.add_argument('--no-surround', action='store_true')
    ap.add_argument('--reset-after-commit', type=int, default=0,
                    metavar='MS', help='send ctx.reset() N ms after each '
                    'commit-text, mimicking mutter real-client behavior')
    ap.add_argument('--gesture', metavar='WORD[,WORD...]',
                    help='inject synthetic gesture trace(s) for the given '
                    'comma-separated words (uses us-mobile geometry)')
    ap.add_argument('--gesture-trace', metavar='TRACE[:ANCHORS[:shift]]',
                    help='inject a raw gesture trace: letters:anchor_indices '
                    'e.g. "hola:0,3" or "hola:0,3:shift"')
    ap.add_argument('text', nargs='?', default='',
                    help='characters to type (tap mode)')
    args = ap.parse_args()

    h = Harness(args.lag, args.osk_cap, args.shell_caps, args.no_surround,
                args.reset_after_commit)
    h.settle(500)  # engine focus/context settle

    if args.gesture:
        words = [w.strip() for w in args.gesture.split(',') if w.strip()]
        for word in words:
            h.inject_gesture(word)
            h.settle(300)  # let decode + commit propagate
            h.push_surrounding(force=True)
            h.settle(150)

    elif args.gesture_trace:
        h.inject_gesture_raw(args.gesture_trace)
        h.settle(300)
        h.push_surrounding(force=True)
        h.settle(150)

    if args.text:
        for ch in args.text:
            print(f'KEY {ch!r} (consumed={h.press(ch)})')
            h.settle(120)

    h.settle(600)
    h.push_surrounding(force=True)
    h.settle(200)
    print(f'\nFINAL SCREEN: {h.text!r}')
    print(f'preedit ever shown: {h.preedit_ever or "no"}')
    if h.candidates_log:
        print(f'last candidates: {h.candidates_log[-1]}')
    h.ctx.focus_out()
    if h.prev_engine and h.prev_engine != 'typing-booster':
        h.bus.set_global_engine(h.prev_engine)
        print(f'restored global engine: {h.prev_engine}')


if __name__ == '__main__':
    main()
