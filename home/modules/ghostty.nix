{ pkgs, lib, ... }:

{
  programs.ghostty = {
    enable = true;
    # On macOS, Ghostty is installed via Homebrew cask — skip the nix package
    package = if pkgs.stdenv.isDarwin then null else pkgs.ghostty;
    enableZshIntegration = true;
    settings = {
      # Colors — kitty default palette (vibrant, saturated)
      background = "000000";
      foreground = "dddddd";
      cursor-color = "dddddd";
      selection-background = "444444";
      selection-foreground = "dddddd";
      palette = [
        "0=#000000"
        "1=#cc0403"
        "2=#19cb00"
        "3=#cecb00"
        "4=#0d73cc"
        "5=#cb1ed1"
        "6=#0dcdcd"
        "7=#dddddd"
        "8=#767676"
        "9=#f2201f"
        "10=#23fd00"
        "11=#fffd00"
        "12=#1a8fff"
        "13=#fd28ff"
        "14=#14ffff"
        "15=#ffffff"
      ];

      # Appearance
      background-opacity = 0.8;
      background-blur-radius = 20;

      # Font
      font-family = "JetBrainsMono Nerd Font Mono";
      font-size = 12;

      # Window
      window-decoration = false;
      window-padding-x = 0;
      window-padding-y = 0;
      window-padding-color = "extend";
      # Cursor
      cursor-style = "underline";
      adjust-cursor-thickness = 2;
      shell-integration-features = "no-cursor";

      # Terminal
      term = "xterm-256color";

      # macOS
      macos-option-as-alt = true;
      macos-titlebar-style = "hidden";

      # Linux
      gtk-single-instance = true;
      gtk-tabs-location = "hidden";

      # Keybindings
      keybind = [
        "ctrl+tab=next_tab"
        "ctrl+shift+tab=previous_tab"
        "ctrl+shift+t=new_tab"
        "ctrl+shift+w=close_surface"
      ];
    };
  };
}
