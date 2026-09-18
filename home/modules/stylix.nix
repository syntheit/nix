{ pkgs, lib, config, ... }:

let
  isLinux = pkgs.stdenv.isLinux;
in
lib.mkMerge [
  # ── Shared config (all platforms) ──
  {
    # Stylix Configuration (Home Manager Isolation Mode)
    # This file manages all Stylix theming for user applications.
    # We use Home Manager-only isolation to prevent recursion with system-level configs.
    stylix.enable = true;
    stylix.autoEnable = false; # Keep manual control of fonts/cursor
    stylix.enableReleaseChecks = false; # Disable strict release checks for unstable

    # Theme configuration
    stylix.polarity = "dark";
    stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyodark.yaml";
    stylix.image = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/os/nix-black-4k.png";
      sha256 = "144mz3nf6mwq7pmbmd3s9xq7rx2sildngpxxj5vhwz76l1w5h5hx";
    };

    # Fonts
    stylix.fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
    };

    # Font sizes (default is 12pt for applications, 10pt for desktop)
    stylix.fonts.sizes = {
      applications = 10;
      desktop = 10;
    };

    # Ghostty is configured directly in ghostty.nix (avoids theme ordering / float issues)
    stylix.targets.ghostty.enable = false;
  }

  # ── Linux-only targets ──
  (lib.mkIf isLinux {
    home.pointerCursor = {
      package = pkgs.kdePackages.breeze;
      name = "breeze_cursors";
      size = 24;
      gtk.enable = true;
    };

    stylix.targets.rofi.enable = false; # Disabled to use manual theme in rofi.nix
    stylix.targets.hyprland.enable = true;
    stylix.targets.gtk.enable = true;
    stylix.targets.qt.enable = true;
    stylix.targets.qt.platform = "qtct";
    stylix.targets.dunst.enable = true;

    gtk.iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };

    # Publish the desktop's light/dark preference. xdg-desktop-portal-gtk reads
    # this dconf key to answer the `color-scheme` key of the portal's
    # org.freedesktop.appearance namespace -- that portal value is what apps
    # set to "System" appearance consult (Zen/Firefox, libadwaita, Electron).
    #
    # Nothing here ever set it, so the portal reported 0 ("no preference").
    # Zen used to fall back to reading the GTK theme's colours, which are dark
    # because of the gtk.css stylix writes, so it looked dark anyway. The
    # 2026-08-31 rebuild took Zen 1.21.6b -> 1.21.15b and that fallback stopped
    # happening -- with "no preference" Zen now just renders light. Verified:
    # `busctl --user call org.freedesktop.portal.Desktop \
    #    /org/freedesktop/portal/desktop org.freedesktop.portal.Settings Read \
    #    ss org.freedesktop.appearance color-scheme` returned `u 0` before this
    # key was set and `u 1` after. Keyed off stylix.polarity so the two can't
    # drift apart.
    dconf.settings."org/gnome/desktop/interface".color-scheme =
      if config.stylix.polarity == "light" then "prefer-light" else "prefer-dark";
  })
]
