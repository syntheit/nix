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
    hostName = "${vars.network.hostname}";
    networkmanager = {
      enable = true;
      # Ensure NetworkManager uses the secret service for storing WiFi passwords
      # This requires libsecret which is provided by gnome-keyring
      # NetworkManager will automatically use the secret service when available
    };
    # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
    # (the default) this is the recommended approach. When using systemd-networkd it's
    # still possible to use this option, but it's recommended to use it in conjunction
    # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
    useDHCP = lib.mkDefault true;
  };

  systemd.services.NetworkManager-wait-online.enable = false;

  # NextDNS via systemd-resolved
  # Configure NetworkManager to use systemd-resolved for DNS
  networking.networkmanager.dns = "systemd-resolved";
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  services.resolved = {
    enable = true;
    dnssec = "false";
    domains = [ "~." ];
    fallbackDns = [ ];
    dnsovertls = "true";
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
    hostPlatform = lib.mkDefault "x86_64-linux";
    config.allowUnfree = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    git
    smartmontools
    iw
    libsecret  # Required for NetworkManager to use secret service (gnome-keyring)
    # Thumbnailer packages for Nemo file previews
    gdk-pixbuf  # Basic image formats (PNG, JPEG, BMP, GIF, TIFF, etc.)
    libheif  # HEIF and AVIF image formats
    libheif.out  # HEIF output plugin
    nufraw  # RAW image format support
    nufraw-thumbnailer  # RAW image thumbnailer
    ffmpegthumbnailer  # Video thumbnail generation
    poppler-utils  # PDF thumbnail generation
    # Affinity Suite
    inputs.affinity-nix.packages.x86_64-linux.v3
  ];

  # Link thumbnailer files so Nemo can find them
  environment.pathsToLink = [
    "share/thumbnailers"
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.nix-ld.enable = true;
  programs.zsh.enable = true;
  programs.adb.enable = true;
  programs.ssh = {
    startAgent = true;
    enableAskPassword = true;
    askPassword = "${pkgs.gnome-keyring}/bin/gnome-keyring-ask";
  };

  # Set zsh as the default shell for the system
  users.defaultUserShell = pkgs.zsh;

  # Firewall configuration
  # TODO: Configure firewall rules as needed
  # networking.firewall.enable = true;
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  # networking.firewall.allowedUDPPorts = [ ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users."${vars.user.name}" = {
    isNormalUser = true;
    description = "${vars.user.fullname}";
    shell = pkgs.zsh;  # Explicitly set zsh as the user's shell
    extraGroups = [
      "networkmanager"
      "wheel"
      "audio"
      "docker"
      "video"
      "libvirtd"
      "adbusers"
    ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}

