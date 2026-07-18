# Shell theme — the ONE place fajita's GNOME Shell theme is defined.
#
# Marble is a SHELL theme: it styles the panel / Quick Settings / popovers via
# theme/gnome-shell/gnome-shell.css and is applied through the User Themes
# extension (org/gnome/shell/extensions/user-theme name) — NOT via `gtk-theme`,
# which stays Adwaita-dark for GTK apps. The extension itself is turned on in
# default.nix's enabled-extensions list (it must live with that authoritative
# list to avoid a dconf key clash).
#
# Pick the accent + light/dark right here; packages/marble-shell-theme runs the
# generator at build time and passthru.themeName maps the choice to the folder
# name selected below. Both modes are built so switching dark<->light is a
# one-line change here (no need to rebuild the generator differently).
{
  pkgs,
  inputs,
  ...
}:
let
  # ── define the theme ──────────────────────────────────────────────────
  accent = "blue"; # hue-210 blue (colors.json); or use a custom `hue` below
  variant = "dark"; # active mode: "dark" | "light"

  marbleTheme = pkgs.callPackage ../../packages/marble-shell-theme {
    src = inputs.marble-shell-theme;
    inherit accent;
    mode = null; # build BOTH dark + light; `variant` selects the active one

    # Bare top bar: no pill/background behind the panel elements…
    extraArgs = [ "--panel-no-pill" ];
    # …and force the panel itself to solid black (Marble's default is a dark
    # blue-grey rgba(21,23,25); this makes it pure black). No !important, so the
    # more-specific #panel:overview / .unlock-screen / .login-screen rules keep
    # their transparency; only the normal top bar goes black.
    extraCss = ''
      #panel { background-color: black; }

      /* On-screen keyboard: the non-letter/function keys (.default-key — Shift,
         Backspace, ?123, Enter, punctuation) inherit BUTTON-COLOR = the bright
         ACCENT-COLOR, so brightening the accent made them loud. Mute just those
         to a desaturated steel blue; letter keys and the QS accent are untouched. */
      .keyboard-key.default-key { background-color: rgba(72, 103, 133, 1); }
      .keyboard-key.default-key:hover { background-color: rgba(88, 120, 150, 1); }
      .keyboard-key.default-key:active,
      .keyboard-key.default-key:checked,
      .keyboard-key.default-key:latched,
      .keyboard-key.shift-key-uppercase { background-color: rgba(104, 140, 172, 1); }

      /* Solid keyboard — no see-through. Marble's #keyboard panel is
         rgba(24,26,27,0.95) and the long-press popup uses the same token, so the
         app behind bleeds through. Make them fully opaque; the letter keys then
         sit on a solid surface and keep their look without leaking the app. */
      #keyboard { background-color: rgba(24, 26, 27, 1); }
      .keyboard-subkeys { -arrow-background-color: rgba(24, 26, 27, 1); }
    '';

    # Brighter, less-gloomy blue in dark mode. Marble's dark accent is a very
    # dark navy (ACCENT-COLOR dark l:26); lift the active-toggle accent family
    # toward a GNOME-Adwaita-like bright blue. Only the .dark values change, so
    # the light variant is untouched. hue stays 210 (from `accent = "blue"`).
    colorsOverride = {
      elements = {
        "ACCENT-COLOR".dark = {
          s = 70;
          l = 56;
          a = 1;
        }; # resting active toggle
        "ACCENT_HOVER".dark = {
          s = 72;
          l = 50;
          a = 1;
        }; # hover
        "ACCENT_ACTIVE".dark = {
          s = 74;
          l = 44;
          a = 1;
        }; # pressed
      };
    };
  };
in
{
  # Ship the generated theme (both variants) + the User Themes extension into
  # the system profile. GNOME finds themes under $XDG_DATA_DIRS/…/themes and
  # extensions under …/gnome-shell/extensions — the same path the cursor theme
  # and the torch extension already rely on.
  environment.systemPackages = [
    marbleTheme
    pkgs.gnome-shell-extensions # ships user-theme@gnome-shell-extensions.gcampax.github.com
  ];

  # Select the active Marble variant. Separate dconf database entry from
  # default.nix's — NixOS merges them and the keys don't overlap.
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/shell/extensions/user-theme" = {
          name = marbleTheme.themeName variant; # e.g. "Marble-blue-dark"
        };
      };
    }
  ];
}
