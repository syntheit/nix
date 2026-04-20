{ pkgs, lib, ... }:

{
  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
    # themeFile is managed by Stylix (via stylix.targets.kitty.enable)
    keybindings = {
      "ctrl+tab" = "next_tab";
      "ctrl+shift+tab" = "previous_tab";
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+w" = "close_tab";
    };
    settings = {
      # FORCE: Override Stylix's default opacity to use my preferred value
      background_opacity = lib.mkForce "0.8";
      # Override themed background to pure black so blur isn't tinted
      background = lib.mkForce "#000000";
      dynamic_background_opacity = true;
      shell = "${pkgs.zsh}/bin/zsh"; # Set zsh as the default shell for kitty
      cursor_shape = "underline"; # Use underline cursor instead of thin line
      cursor_underline_thickness = "2.0"; # Thickness of the underline cursor
      shell_integration = "no-cursor"; # Prevent shell integration from overriding cursor shape
      # Use xterm-256color for SSH sessions to avoid terminfo errors
      term = "xterm-256color";
      tab_bar_style = "hidden";
      single_instance = "yes";
      allow_remote_control = "yes";
      listen_on = "unix:/tmp/kitty-sock";
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      hide_window_decorations = "yes"; # Remove title bar
      window_margin_width = 0;
      window_padding_width = 0;
      macos_option_as_alt = "yes"; # Send Alt escape sequences instead of macOS special characters
    };
  };
}
