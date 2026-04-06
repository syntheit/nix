{
  lib,
  pkgs,
  vars,
  extraLibs,
  inputs,
  ...
}:
{
  imports = extraLibs.scanPaths ./.;

  networking = {
    networkmanager = {
      enable = true;
      # Ensure NetworkManager uses the secret service for storing WiFi passwords
      # This requires libsecret which is provided by gnome-keyring
      # NetworkManager will automatically use the secret service when available
    };
  };

  systemd.services.NetworkManager-wait-online.enable = false;

  # NextDNS via systemd-resolved
  # Configure NetworkManager to use systemd-resolved for DNS
  networking.networkmanager.dns = "systemd-resolved";
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSSEC = "false";
        Domains = [ "~." ];
        FallbackDNS = [ ];
        DNSOverTLS = "true";
      };
    };
  };
  # Configure NextDNS servers via systemd-resolved
  # These will be used by systemd-resolved
  networking.nameservers = [
    "45.90.28.0#57bc2c.dns.nextdns.io"
    "2a07:a8c0::#57bc2c.dns.nextdns.io"
    "45.90.30.0#57bc2c.dns.nextdns.io"
    "2a07:a8c1::#57bc2c.dns.nextdns.io"
  ];

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];
    settings.auto-optimise-store = true;
    settings.max-jobs = "auto";
    settings.cores = 0;
    settings.download-buffer-size = 134217728;
    # Nix garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs = {
    # hostPlatform is set per-host in hardware-configuration.nix
    config.allowUnfree = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    git
    lm_sensors
    iw
    libsecret # Required for NetworkManager to use secret service (gnome-keyring)
    # Thumbnailer packages for file manager previews
    gdk-pixbuf # Basic image formats (PNG, JPEG, BMP, GIF, TIFF, etc.)
    libheif # HEIF and AVIF image formats
    libheif.out # HEIF output plugin
    nufraw # RAW image format support
    nufraw-thumbnailer # RAW image thumbnailer
    ffmpegthumbnailer # Video thumbnail generation
    poppler-utils # PDF thumbnail generation
    android-tools
    # Affinity Suite
    inputs.affinity-nix.packages.${pkgs.stdenv.hostPlatform.system}.v3
    xhost # Required for GParted access to display on Wayland
    ntfs3g # NTFS read/write support and utilities
    cifs-utils # Samba/Windows network shares
    nfs-utils # NFS network shares
    hfsprogs # HFS+ support
    apfs-fuse # APFS support (read-only)
  ];

  # Link thumbnailer files so file managers can find them
  environment.pathsToLink = [
    "share/thumbnailers"
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      openssl
    ];
  };
  programs.zsh.enable = true;
  programs.ssh = {
    startAgent = true;
    enableAskPassword = true;
    askPassword = "${pkgs.gnome-keyring}/bin/gnome-keyring-ask";
  };

  # Set zsh as the default shell for the system
  users.defaultUserShell = pkgs.zsh;

  networking.firewall = {
    enable = true;
    logRefusedConnections = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users."${vars.user.name}" = {
    isNormalUser = true;
    description = "${vars.user.fullname}";
    shell = pkgs.zsh; # Explicitly set zsh as the user's shell
    extraGroups = [
      "networkmanager"
      "wheel"
      "audio"
      "docker"
      "video"
      "libvirtd"
    ];
  };

  # Fingerprint authentication for sudo and login
  # Only enabled per-host where fprintd is available (see hosts/ionian/hardware.nix)

  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };
}
