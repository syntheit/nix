{
  pkgs,
  inputs,
  vars,
  ...
}:
let
  # KDE Connect remote-input bridge (RemoteDesktop portal backend). Installed
  # here in the home profile so its .portal lands in the dir the xdg-desktop-
  # portal frontend scans (NIX_XDG_DESKTOP_PORTAL_DIR = the user profile). The
  # daemon is started from the Hyprland session; routing is in ./default.nix.
  hyprKdeconnectFix = pkgs.callPackage ./pkgs/hypr-kdeconnect-fix.nix { };
in
{
  # Lean HTPC home profile. Deliberately does NOT import ../../home (the full
  # workstation profile with its ~140-package kitchen sink). It reuses the same
  # desktop-experience modules mantle uses (Hyprland, Ghostty, Zen, Rofi,
  # theming, shell) but with a curated, media-box-focused package set.
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    inputs.stylix.homeModules.stylix
    ../../home/modules/stylix.nix
    ../../home/modules/ssh.nix
    ../../home/modules/tmux.nix
    ../../home/modules/git.nix
    ../../home/modules/neovim.nix
    ../../home/modules/hyprland.nix
    ../../home/modules/rofi.nix
    ../../home/modules/ghostty.nix
    ../../home/modules/mime-apps.nix
    ../../home/modules/services.nix
    ../../home/modules/zen.nix
    ../../home/modules/dunst.nix
    ../../home/modules/copyq.nix
    ../../home/modules/wallpaper.nix
    ../../home/modules/spotify.nix
    ../../home/shell.nix
    ../../home/modules/opencode.nix
  ];

  home.username = "${vars.user.name}";
  home.homeDirectory = "/home/${vars.user.name}";
  home.stateVersion = "24.11";

  # Prompt path color = orange — vista's host tint. It's the one saturated hue
  # not used anywhere else in the prompt (blue=home boxes, cyan=raven,
  # yellow=conduit, salmon=harbor, purple stays git-branch-only).
  programs.starship.settings.directory = {
    style = "#FF8700";
    repo_root_style = "bold #FF8700";
    before_repo_root_style = "dimmed #FF8700";
  };

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    hms = "home-manager switch";
    highlight = "grep --color=always -e \"^\"";
  };

  home.packages = with pkgs; [
    # ── CLI essentials ──
    btop
    fastfetch
    ripgrep
    fd
    jq
    wget
    tree
    unzip
    tmux
    mosh
    yazi
    lazygit
    tldr
    gh
    claude-code
    nixfmt-rfc-style
    nix-output-monitor
    nodejs

    # ── Media (the point of the box) ──
    spotify
    playerctl
    vlc
    mpv
    yt-dlp
    ffmpeg-full
    pamixer
    pavucontrol

    # ── Browser ──
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default

    # ── Hyprland desktop runtime (needed by home/modules/hyprland.nix) ──
    rofi-power-menu
    hypridle
    hyprpicker
    hyprpolkitagent
    hyprsunset
    grimblast
    satty
    slurp
    nwg-displays
    networkmanagerapplet
    wl-clipboard
    libnotify
    (pkgs.callPackage ../../packages/hyprland-dynamic-borders { })

    # ── File manager + Qt/Wayland theming ──
    nautilus
    gvfs
    file-roller
    kdePackages.qtwayland
    kdePackages.qt6ct
    kdePackages.qtstyleplugin-kvantum

    # ── Bluetooth pairing (for casting to a BT speaker) ──
    bluetuith

    # ── KDE Connect remote-input bridge (RemoteDesktop portal backend) ──
    hyprKdeconnectFix
  ];

  # Run kdeconnectd as a Wayland Qt app. KDE Connect's mousepad plugin picks its
  # remote-input backend purely from Qt's platformName: "wayland" → the
  # RemoteDesktop-portal path (which hypr-kdeconnect-fix implements), "xcb" →
  # XTest (injects into XWayland, useless on Hyprland). Launched bare with
  # DISPLAY=:0 and no QT_QPA_PLATFORM, Qt loads xcb → remote input silently dies.
  # Force wayland + drop DISPLAY so the portal path is taken. Uses the wrapped
  # store binary so the qtwayland QPA plugin is on the path.
  systemd.user.services.kdeconnectd = {
    Unit = {
      Description = "KDE Connect daemon (forced Wayland Qt platform for remote input)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnectd --replace";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [ "QT_QPA_PLATFORM=wayland" ];
      UnsetEnvironment = [ "DISPLAY" ];
    };
  };

  programs.home-manager.enable = true;
}
