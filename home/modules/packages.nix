{ pkgs, inputs, ... }:

{
  # Prisma engines - use nixpkgs engines system-wide instead of per-project flakes
  home.sessionVariables = {
    PRISMA_SCHEMA_ENGINE_BINARY = "${pkgs.prisma-engines}/bin/schema-engine";
    PRISMA_QUERY_ENGINE_BINARY = "${pkgs.prisma-engines}/bin/query-engine";
    PRISMA_QUERY_ENGINE_LIBRARY = "${pkgs.prisma-engines}/lib/libquery_engine.node";
    PRISMA_FMT_BINARY = "${pkgs.prisma-engines}/bin/prisma-fmt";
    PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING = "1";
  };

  home.packages = with pkgs; [
    # CLI tools
    htop
    btop
    fastfetch
    tldr
    wget
    tree
    ripgrep
    fd
    unzip
    cowsay
    dig
    bc
    openssl
    traceroute
    usbutils
    pv
    inetutils
    sshfs
    libarchive
    ack
    pciutils
    hwinfo
    lsof
    e2fsprogs
    gnumake
    duf
    plocate
    nixfmt
    nix-output-monitor
    ookla-speedtest
    screen

    # Development
    prisma-engines
    typst
    jq
    htmlq
    kubectl
    kubernetes-helm
    devenv
    distrobox
    code-cursor
    antigravity
    google-chrome
    dbeaver-bin
    vscode
    opencode
    awscli2
    zip
    aws-sam-cli
    claude-code
    yt-dlp
    pnpm
    nodejs
    python3
    go

    # Media
    imagemagick
    ffmpeg-full
    obs-studio
    spotify
    playerctl
    vlc
    transmission_4
    qbittorrent
    mousai

    # Graphics & documents
    libreoffice
    ghostscript
    pdftk
    loupe
    baobab

    # Hyprland & desktop
    rofi-power-menu
    hypridle
    hyprpicker
    hyprpolkitagent
    hyprsunset
    grimblast
    pavucontrol
    pamixer
    nwg-displays
    networkmanagerapplet
    wl-clipboard
    copyq
    (pkgs.callPackage ../../packages/hyprland-dynamic-borders { })

    # System & apps
    tor-browser
    brave
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    signal-desktop
    telegram-desktop
    slack
    nextcloud-client
    virt-manager
    papirus-icon-theme
    popsicle
    prismlauncher
    lshw-gui
    parted
    gptfdisk
    cpupower-gui
    jre8
    gvfs
    nemo
    nautilus
    mission-center
    resources
    gnome-2048
    gnome-calculator
    gparted
    gnome-disk-utility
    papers
    snapshot
    zathura
    bluetuith
    libnotify
    kdePackages.qt6ct
    libsForQt5.qt5ct
    kdePackages.qtwayland
    libsForQt5.qtwayland
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    ladybird
    obsidian
  ];
}
