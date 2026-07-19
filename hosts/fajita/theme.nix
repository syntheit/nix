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

      /* Most of the iOS-style top bar (battery pill, inset, charging, lock/login
         shadows, clock shadow) lives in the BASE gnome-shell theme — see
         packages/gnome-mobile/patches/topbar-base-css.patch — because the User
         Themes extension (this Marble theme) is disabled on the lock/login
         screens, so base is the only way to reach them.

         EXCEPTION: the home-screen (overview) dark-invert must live HERE in
         Marble, not in the base theme. St gives the user theme higher cascade
         priority than the base theme, so Marble's own `#panel:overview
         .panel-button { color }` beats a base-theme override — the clock stayed
         white. Putting the invert in Marble lets it win. (This only ever applies
         on the home screen, where Marble is active; lock/login aren't :overview,
         so nothing is lost.) */
      #panel:overview .panel-button,
      #panel:overview .clock,
      #panel:overview .panel-button.clock-display .clock,
      #panel:overview .system-status-icon { color: rgba(0, 0, 0, 0.82); }
      #panel:overview .fajita-battery-body,
      #panel:overview .fajita-battery-nub { background-color: rgba(0, 0, 0, 0.82); }
      #panel:overview .fajita-battery-num,
      #panel:overview .fajita-battery-bolt { color: white; }
      #panel:overview .fajita-battery.charging .fajita-battery-body,
      #panel:overview .fajita-battery.charging .fajita-battery-nub { background-color: #34c759; }
      #panel:overview .fajita-battery.charging .fajita-battery-num,
      #panel:overview .fajita-battery.charging .fajita-battery-bolt { color: white; }

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

      /* OSK suggestion strip: tuck the pills up toward the app edge
         (Daniel-tuned via screenshots 2026-07-19). */
      .word-suggestions { padding-top: 2px; padding-bottom: 10px; }

      /* OSK swipe-typing trail dots (fajita swipe bundle). Retune via dconf/CSS live. */
      .gesture-trail-dot {
        background-color: rgba(53, 132, 228, 0.75);
        border-radius: 7px;
      }
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
