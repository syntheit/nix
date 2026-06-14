{
  pkgs,
  inputs,
  vars,
  ...
}:
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
  ];

  home.username = "${vars.user.name}";
  home.homeDirectory = "/home/${vars.user.name}";
  home.stateVersion = "24.11";

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
  ];

  programs.home-manager.enable = true;
}
