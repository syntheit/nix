{ pkgs, lib, ... }:

{
  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
    # themeFile is managed by Stylix (via stylix.targets.kitty.enable)
    settings = {
      # FORCE: Override Stylix's default opacity to use my preferred value
      background_opacity = lib.mkForce "0.8";
      dynamic_background_opacity = true;
      shell = "${pkgs.zsh}/bin/zsh"; # Set zsh as the default shell for kitty
      cursor_shape = "underline"; # Use underline cursor instead of thin line
      cursor_underline_thickness = "2.0"; # Thickness of the underline cursor
      shell_integration = "no-cursor"; # Prevent shell integration from overriding cursor shape
      # Use xterm-256color for SSH sessions to avoid terminfo errors
      term = "xterm-256color";
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      hide_window_decorations = "yes"; # Remove title bar
      window_margin_width = 0;
      window_padding_width = 0;
    };
  };
}
