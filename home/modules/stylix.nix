{ pkgs, ... }:

{
  # Stylix Configuration (Home Manager Isolation Mode)
  # This file manages all Stylix theming for user applications.
  # We use Home Manager-only isolation to prevent recursion with system-level configs.

  # Manually enable Stylix for this user
  stylix.enable = true;
  stylix.autoEnable = false; # Keep manual control of fonts/cursor
  stylix.enableReleaseChecks = false; # Disable strict release checks for unstable
  
  # Theme configuration
  stylix.polarity = "dark";
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyodark.yaml";
  stylix.image = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/os/nix-black-4k.png";
    sha256 = "sha256-MakeSureToReplaceThisWithTheHashFromErrorMessage";
  };

  # Cursors & Fonts
  home.pointerCursor = {
    gtk.enable = true;
    package = pkgs.kdePackages.breeze;
    name = "breeze_cursors";
    size = 24;
  };
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
    applications = 10;  # Set to 10pt
    desktop = 10;       # Keep desktop at default 10pt
  };

  # Enable Targets (Stylix will theme these applications)
  stylix.targets.waybar.enable = false;
  stylix.targets.rofi.enable = false;  # Disabled to use manual theme in rofi.nix
  stylix.targets.hyprland.enable = true;
  stylix.targets.kitty.enable = true;
  stylix.targets.gtk.enable = true;
  stylix.targets.qt.enable = true;
  stylix.targets.dunst.enable = true;

  stylix.targets.qt.platform = "qtct";


  # Override icon theme to Papirus
  gtk.iconTheme = {
    name = "Papirus";
    package = pkgs.papirus-icon-theme;
  };
}
