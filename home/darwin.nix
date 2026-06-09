{
  lib,
  pkgs,
  inputs,
  vars,
  hostName,
  config,
  ...
}:
{
  imports = [
    # Cross-platform modules (work on both Linux and Darwin)
    inputs.nix-index-database.homeModules.nix-index
    inputs.stylix.homeModules.stylix
    ./modules/stylix.nix
    ./modules/ghostty.nix
    ./modules/git.nix
    ./modules/neovim.nix
    ./modules/ssh.nix
    ./shell.nix

    # macOS-specific modules
    ./modules/sketchybar.nix
    ./modules/app-tweaks.nix
    ./modules/vestal-darwin.nix
    ./modules/tmux.nix
    ./modules/eq.nix
    ./modules/overview.nix
    ./modules/volume-panel.nix
    ./modules/bluetooth-panel.nix
    ./modules/wifi-panel.nix
    ./modules/wallpaper-darwin.nix
    ./modules/menubar-blocker.nix
    ./modules/square-corners.nix
    ./modules/caps-led-off.nix
  ];

  home.username = vars.user.name;
  home.homeDirectory = "/Users/${vars.user.name}";

  programs.vestal.enable = true;

  home.stateVersion = "24.11";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    k = "kubectl";
    highlight = "grep --color=always -e \"^\"";
  };

  home.sessionPath = [
    # GNU coreutils unprefixed (override BSD tools with GNU versions)
    "${pkgs.coreutils}/libexec/gnubin"
    "${pkgs.findutils}/libexec/gnubin"
    "${pkgs.gnugrep}/libexec/gnubin"
    "${pkgs.gnused}/libexec/gnubin"
    "${pkgs.gawk}/libexec/gnubin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/run/current-system/sw/bin"
  ];

  home.packages = with pkgs; [
    awscli2
    aws-sam-cli
    btop
    claude-code
    coreutils
    sops
    ssh-to-age
    fastfetch
    fd
    ffmpeg
    findutils
    gawk
    gh
    gnugrep
    gnused
    go
    mas
    nodejs
    pnpm
    ripgrep
    foyer
    mosh
    spotify-player
    switchaudio-osx
    yt-dlp
    # Operator CLI for the Malli fleet (`deus list`, `deus tui`,
    # `deus bootstrap …`). Pinned via the deus flake input in
    # ../flake.nix so each darwin host always tracks the same revision
    # the fleet machines do.
    inputs.deus.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.yazi = {
    enable = true;
    shellWrapperName = "y";
    settings.mgr = {
      sort_by = "mtime";
      sort_reverse = true;
      sort_dir_first = false;
    };
  };

  # Screenshot to harbor — Shift+Cmd+X triggers interactive selection,
  # uploads to ~/screenshots/<hostName>/ on harbor for Claude Code to read.
  home.file.".local/bin/screenshot-to-harbor" = {
    executable = true;
    text = ''
      #!/bin/bash
      FILE="$(date +%Y%m%d-%H%M%S).png"
      LOCAL="/tmp/$FILE"
      REMOTE="screenshots/${hostName}"

      # Interactive selection screenshot
      screencapture -i "$LOCAL" 2>/dev/null

      # User cancelled the selection
      [ ! -f "$LOCAL" ] && exit 0

      # Ensure remote dir exists and upload
      ssh harbor "mkdir -p ~/$REMOTE"
      scp -q "$LOCAL" "harbor:~/$REMOTE/$FILE"
      rm "$LOCAL"

      # Notification
      osascript -e "display notification \"$FILE uploaded to harbor\" with title \"Screenshot\""
    '';
  };

  # Suppress "Last login: ..." message in new terminal windows
  home.file.".hushlogin".text = "";

  programs.home-manager.enable = true;
}
