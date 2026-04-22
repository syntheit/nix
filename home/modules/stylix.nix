{ pkgs, lib, ... }:

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

    gtk.gtk4.theme = null;

    gtk.iconTheme = {
      name = "Papirus";
      package = pkgs.papirus-icon-theme;
    };
  })
]
