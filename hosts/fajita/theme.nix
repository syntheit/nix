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
