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
    # are set there). Setting package = null keeps HM from installing a bare
    # pkgs.firefox into ~/.nix-profile/bin, which would shadow the NixOS-wrapped
    # firefox (the one with autoConfig / mozilla.cfg) in /run/current-system/sw/.
    # Without this, the user PATH resolves to the unwrapped binary and
    # fx-autoconfig never loads.
    package = null;
    profiles.default = {
      id = 0;
      userChrome = builtins.readFile "${pkgs.mobile-config-firefox}/userChrome.css"
        + "\n" + builtins.readFile ../../packages/orion-chrome/urlbar-view-mobile.css
        + "\n" + builtins.readFile ../../packages/orion-chrome/toolbar-mobile.css;
      userContent = builtins.readFile "${pkgs.mobile-config-firefox}/userContent.css";
    };
  };

  # fx-autoconfig profile tier — place the loader files into the default
  # profile's chrome/utils/ directory so boot.sys.mjs is found at the path
  # that config.js (program tier, in programs.firefox.autoConfig) registers.
  # chrome.manifest is the critical file: without it the chrome:// protocol
  # mapping is never registered and the whole loader silently no-ops.
  # Target: ~/.config/mozilla/firefox/default/chrome/utils/
  # (home-manager already owns ~/.config/mozilla/firefox/default/chrome/ via
  # the userChrome entry above; these home.file entries coexist with it.)
  home.file = let
    utils = "${pkgs.fx-autoconfig}/profile/chrome/utils";
  in {
    ".config/mozilla/firefox/default/chrome/utils/chrome.manifest".source =
      "${utils}/chrome.manifest";
    ".config/mozilla/firefox/default/chrome/utils/boot.sys.mjs".source =
      "${utils}/boot.sys.mjs";
    ".config/mozilla/firefox/default/chrome/utils/fs.sys.mjs".source =
      "${utils}/fs.sys.mjs";
    ".config/mozilla/firefox/default/chrome/utils/utils.sys.mjs".source =
      "${utils}/utils.sys.mjs";
    ".config/mozilla/firefox/default/chrome/utils/uc_api.sys.mjs".source =
      "${utils}/uc_api.sys.mjs";
    ".config/mozilla/firefox/default/chrome/utils/module_loader.mjs".source =
      "${utils}/module_loader.mjs";

    # touch-spike: log touch events on the nav bar + tab strip to
    # /tmp/ff-touch-spike.log so we can verify the loader is active and
    # measure real touch coordinates on the phone screen.
    ".config/mozilla/firefox/default/chrome/JS/touch-spike.uc.mjs".source =
      ../../packages/orion-chrome/js/touch-spike.uc.mjs;

    # loader-proof: bare import-time write to /tmp/ff-loader-proof.log so we can
    # distinguish "loader runs scripts" from "window hook is wrong".
    ".config/mozilla/firefox/default/chrome/JS/loader-proof.uc.mjs".source =
      ../../packages/orion-chrome/js/loader-proof.uc.mjs;

    # urlbar-inspect: DOM geometry inspector for the suggestions panel.
    # Polls for urlbar open state and dumps BoundingClientRect + computed styles
    # for every relevant element to /tmp/ff-urlbar-dump.json.
    ".config/mozilla/firefox/default/chrome/JS/urlbar-inspect.uc.mjs".source =
      ../../packages/orion-chrome/js/urlbar-inspect.uc.mjs;

    # tab-grid: Orion-iOS-style full-screen tab grid overlay.
    # Intercepts #alltabs-button click; renders 2-column card grid with
    # PageThumbs thumbnails; touch+click events logged to /tmp/ff-grid-touch.log.
    ".config/mozilla/firefox/default/chrome/JS/tab-grid.uc.mjs".source =
      ../../packages/orion-chrome/js/tab-grid.uc.mjs;

    # urlbar-pill: C1b Orion two-row bottom-bar enhancements — publishes the
    # measured #nav-bar height as --orion-bar-height (panel re-anchor), injects
    # the pill favicon, short-domain display when blurred, and the edit-mode
    # copy-URL button. Logs to /tmp/ff-pill.log.
    ".config/mozilla/firefox/default/chrome/JS/urlbar-pill.uc.mjs".source =
      ../../packages/orion-chrome/js/urlbar-pill.uc.mjs;
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
    codex
    fastfetch
    fd
    jq
    mosh
    ripgrep
    tree
  ];
}
