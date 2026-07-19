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

      /* Inset the top-bar content from the screen edges — the OnePlus 6T's
         rounded corners clip elements sitting flush to the edge. NOTE: the
         panel lays out #panelLeft/#panelCenter/#panelRight in its own
         vfunc_allocate using the FULL width and IGNORES #panel padding — so the
         only lever that actually moves the clock + battery inward is padding on
         the boxes themselves. Tune these two px values. */
      #panelLeft  { padding-left: 24px; }
      #panelRight { padding-right: 24px; }

      /* iOS-style battery: a solid monochrome pill with the % number inside, a
         terminal nub, and a charging bolt. On the black bar it's a white pill /
         black number. In the home/overview the panel is transparent over a
         light wallpaper, so the whole bar goes a soft near-black (iOS/Android
         use a softened dark, not harsh #000) and the battery becomes a dark
         pill with a light number. */
      .fajita-battery { spacing: 0px; }
      .fajita-battery-body {
        background-color: white;
        border-radius: 4px;
        min-width: 16px;
        min-height: 12px;
        padding: 0px 2px;
      }
      .fajita-battery-nub {
        background-color: white;
        min-width: 2px;
        min-height: 5px;
        border-radius: 0px 3px 3px 0px;
        margin-left: 1px;
      }
      .fajita-battery-num { color: black; font-size: 9px; font-weight: bold; }
      .fajita-battery-bolt { color: black; min-width: 7px; min-height: 10px; margin-left: 1px; }

      /* Home/overview: bare text + symbolic icons go soft-dark on the light
         wallpaper; the battery pill flips to soft-dark with a light number.
         (Battery number/bolt rules come LAST so they win the light colour over
         the .panel-button cascade. If you move to a DARK wallpaper, drop this
         whole block so the bar stays white here.) */
      #panel:overview .panel-button,
      #panelArea:overview .panel-button,
      #panel:overview .clock,
      #panelArea:overview .clock,
      #panel:overview .system-status-icon,
      #panelArea:overview .system-status-icon { color: rgba(0, 0, 0, 0.82); }
      #panel:overview .fajita-battery-body,
      #panelArea:overview .fajita-battery-body,
      #panel:overview .fajita-battery-nub,
      #panelArea:overview .fajita-battery-nub { background-color: rgba(0, 0, 0, 0.82); }
      #panel:overview .fajita-battery-num,
      #panelArea:overview .fajita-battery-num,
      #panel:overview .fajita-battery-bolt,
      #panelArea:overview .fajita-battery-bolt { color: white; }

      /* Charging (iOS-style): green pill + white number/bolt, in both the black
         bar and the overview (the #panel:overview variants keep it green there,
         overriding the dark-invert above). */
      .fajita-battery.charging .fajita-battery-body,
      .fajita-battery.charging .fajita-battery-nub,
      #panel:overview .fajita-battery.charging .fajita-battery-body,
      #panelArea:overview .fajita-battery.charging .fajita-battery-body,
      #panel:overview .fajita-battery.charging .fajita-battery-nub,
      #panelArea:overview .fajita-battery.charging .fajita-battery-nub { background-color: #34c759; }
      .fajita-battery.charging .fajita-battery-num,
      .fajita-battery.charging .fajita-battery-bolt,
      #panel:overview .fajita-battery.charging .fajita-battery-num,
      #panelArea:overview .fajita-battery.charging .fajita-battery-num,
      #panel:overview .fajita-battery.charging .fajita-battery-bolt,
      #panelArea:overview .fajita-battery.charging .fajita-battery-bolt { color: white; }

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
