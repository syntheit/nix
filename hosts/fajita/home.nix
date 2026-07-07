{ pkgs, inputs, ... }:
{
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    ../../home/shell.nix
    ../../home/modules/git.nix
    ../../home/modules/ssh.nix
    ../../home/modules/tmux.nix
    ../../home/modules/opencode.nix
  ];

  home.username = "daniel";
  home.homeDirectory = "/home/daniel";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  # Firefox userChrome.css / userContent.css from pmOS's mobile-config-firefox.
  # This rearranges the chrome (hides tab strip, full-width URL bar, hidden
  # spacers, full-viewport URL dropdown, etc.) so FF fits a phone screen.
  # Without this, even with fractional-scale + browser.uidensity=2, the chrome
  # still looks "desktop-y" because it's not actually narrower — pmOS works
  # because of these CSS overrides, not because of the prefs alone.
  programs.firefox = {
    enable = true;
    # We let the NixOS module own the firefox package (policies + autoconfig
    # are set there). Home-manager just needs to deploy the profile + chrome
    # CSS — point at the system's firefox to avoid duplicate installs.
    package = pkgs.firefox;
    profiles.default = {
      id = 0;
      userChrome = builtins.readFile "${pkgs.mobile-config-firefox}/userChrome.css";
      userContent = builtins.readFile "${pkgs.mobile-config-firefox}/userContent.css";
    };
  };

  home.packages = with pkgs; [
    bat
    btop
    claude-code
    fastfetch
    fd
    jq
    mosh
    ripgrep
    tree
  ];
}
