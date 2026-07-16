# Hide the mouse pointer on the touch-only fajita.
#
# There is NO pointer device on this phone (libinput lists only touch/switch/
# keyboard). The arrow appears because Mutter's cursor-visibility state machine
# (src/backends/meta-backend.c) flips the pointer VISIBLE on any non-synthetic
# CLUTTER_POINTER_DEVICE event — on fajita that comes from XWayland's virtual
# core pointer (the running Xwayland is launched `-core -accessx`) and the
# locate-pointer machinery. Mutter has no "touch-only, never show cursor" gsetting,
# and X11 tools (unclutter, -nocursor) don't work under Wayland.
#
# Robust Wayland-correct fix: make the cursor sprite DRAW NOTHING. We ship an
# XCursor theme ("blank") whose every cursor is a 1x1 fully-transparent image and
# point the interface cursor-theme at it. When Mutter decides to "show" the
# cursor, it blits one transparent pixel = invisible. This survives XWayland,
# a11y and locate-pointer because they all render the *themed* sprite.
#
# See ~/fajita-notes/cursor.md for the full root-cause analysis and sources.
{ pkgs, lib, ... }:
let
  # Every standard XCursor name we want to blank. Mutter/GTK/XWayland ask for
  # these by name; anything not listed would fall back to the default cursor of
  # whatever inherited theme, so we cover the common set and inherit nothing.
  cursorNames = [
    "left_ptr" "default" "arrow" "top_left_arrow"
    "pointer" "hand" "hand1" "hand2" "pointing_hand"
    "text" "xterm" "ibeam"
    "watch" "wait" "progress" "left_ptr_watch"
    "crosshair" "cross"
    "move" "fleur" "all-scroll"
    "grab" "grabbing" "openhand" "closedhand"
    "not-allowed" "forbidden" "no-drop" "circle"
    "help" "question_arrow" "whats_this"
    "col-resize" "row-resize"
    "n-resize" "s-resize" "e-resize" "w-resize"
    "ne-resize" "nw-resize" "se-resize" "sw-resize"
    "ns-resize" "ew-resize" "nesw-resize" "nwse-resize"
    "size_ver" "size_hor" "size_fdiag" "size_bdiag" "size_all"
    "top_side" "bottom_side" "left_side" "right_side"
    "top_left_corner" "top_right_corner"
    "bottom_left_corner" "bottom_right_corner"
    "sb_v_double_arrow" "sb_h_double_arrow"
    "dnd-move" "dnd-copy" "dnd-link" "dnd-none" "copy" "link" "alias"
    "cell" "vertical-text" "context-menu" "zoom-in" "zoom-out"
  ];

  blankCursorTheme = pkgs.runCommand "blank-cursor-theme" {
    nativeBuildInputs = [ pkgs.xcursorgen pkgs.imagemagick ];
  } ''
    themeDir="$out/share/icons/blank"
    mkdir -p "$themeDir/cursors"

    cat > "$themeDir/index.theme" <<'EOF'
    [Icon Theme]
    Name=blank
    Comment=Fully transparent cursor theme (touch-only device)
    EOF

    cat > "$themeDir/cursor.theme" <<'EOF'
    [Icon Theme]
    Name=blank
    Inherits=blank
    EOF

    # A 1x1 fully-transparent PNG (RGBA 0,0,0,0).
    magick -size 1x1 xc:transparent PNG32:blank.png

    # xcursorgen config: <size> <xhot> <yhot> <png> — a single 1x1 frame.
    echo "1 0 0 blank.png" > cursor.cfg

    # Build the canonical "left_ptr" cursor once, then hardlink every other
    # cursor name to it so all shapes resolve to the transparent pixel.
    xcursorgen cursor.cfg "$themeDir/cursors/left_ptr"
    for name in ${lib.concatStringsSep " " (lib.filter (n: n != "left_ptr") cursorNames)}; do
      ln "$themeDir/cursors/left_ptr" "$themeDir/cursors/$name"
    done
  '';
in
{
  # Make the theme resolvable at /run/current-system/sw/share/icons/blank so
  # Mutter/GTK/XWayland's XCursor loader finds it.
  environment.systemPackages = [ blankCursorTheme ];

  # XWayland + GTK + Qt honour these env vars for cursor lookup (belt-and-
  # suspenders alongside the dconf key, so the XWayland pointer path is blanked
  # too). GNOME's own Wayland surfaces use the dconf cursor-theme below.
  environment.sessionVariables = {
    XCURSOR_THEME = "blank";
    XCURSOR_SIZE = "1";
  };

  # dconf: point GNOME/Mutter at the blank theme, and disable the
  # locate-pointer "flash the cursor" accelerators so nothing force-shows it.
  # These keys are ADDED to the fajita user dconf profile (default.nix already
  # declares an org/gnome/desktop/interface block; NixOS merges the two
  # attrsets, and cursor-theme/cursor-size are not set there, so no conflict).
  programs.dconf.profiles.user.databases = [{
    settings = with lib.gvariant; {
      "org/gnome/desktop/interface" = {
        cursor-theme = "blank";
        cursor-size = mkInt32 1;
        locate-pointer = false;
      };
      "org/gnome/mutter" = {
        locate-pointer-key = "";  # disable the Ctrl-flash that force-shows it
      };
    };
  }];
}
