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

  # fajita is pinned to the GNOME-49 nixpkgs (2026-05-05), whose fzf predates
  # 0.73.0 — new home-manager asserts that version for its nushell integration.
  # No nushell anywhere, so just turn the integration off.
  programs.fzf.enableNushellIntegration = false;

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

  # foot is the tmux terminal on fajita. VTE-based terminals (Ptyxis/Console)
  # can't do single-finger touch scroll inside tmux — VTE has no GtkGestureDrag
  # for one-finger drag (upstream bug), so swipe-scroll never reaches the pty.
  # foot handles touch scroll itself and forwards it as wheel events, which tmux
  # (mouse on) turns into scrollback. Tuned for a phone: readable font, deep
  # scrollback, and a longer long-press so a scroll drag isn't read as a tap.
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "monospace:size=11";
        pad = "6x6";
      };
      scrollback.lines = 50000;
      touch.long-press-delay = 400;
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
