{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware.nix
    ../../modules/server-safety.nix
  ];

  services.serverSafety = {
    enable = true;
    user = "matv";
  };

  networking = {
    hostName = "conduit";
    # Static IP — RackNerd VPS does not use DHCP
    useDHCP = false;
    interfaces.ens3 = {
      ipv4.addresses = [{
        address = "192.3.203.146";
        prefixLength = 26;
      }];
    };
    defaultGateway = {
      address = "192.3.203.129";
      interface = "ens3";
    };
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80    # Caddy ACME HTTP-01
        443   # Caddy HTTPS
        64829 # SSH
        64830 # Rescue SSH
      ];
      allowedUDPPorts = [
        51820 # WireGuard
      ];
      trustedInterfaces = [ "wg0" ];
    };
  };

  # SSH — key-only, non-standard port
  services.openssh = {
    enable = true;
    ports = [ 64829 ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # User
  users = {
    defaultUserShell = pkgs.zsh;
    users.matv = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
      ];
    };
  };

  # Nix
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
      auto-optimise-store = true;
      max-jobs = "auto";
      cores = 0;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Passwordless sudo for remote deploys via nixos-rebuild --use-remote-sudo
  security.sudo.wheelNeedsPassword = false;

  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;

  # System packages
  environment.systemPackages = with pkgs; [
    fastfetch
    zsh
    btop
    curl
    git
    wireguard-tools
    mosh
    tmux
    jq
    bat
    duf
  ];

  # WireGuard tunnel to harbor
  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = "/etc/wireguard/private.key"; # Manually placed for now, sops later
    peers = [{
      # harbor
      publicKey = "PlMrfs2tSsfOhztKCCf4e9ozb5ZsnDdUq5Zi/gZqOWw=";
      allowedIPs = [ "10.100.0.2/32" ];
      # No endpoint — harbor connects to us
    }];
  };

  # Caddy reverse proxy — auto TLS via Let's Encrypt
  services.caddy = {
    enable = true;
    virtualHosts."watch.matv.io" = {
      extraConfig = ''
        reverse_proxy 10.100.0.2:8096
      '';
    };
    virtualHosts."photos.matv.io" = {
      extraConfig = ''
        reverse_proxy 10.100.0.2:2283
      '';
    };
  };

  # Cap journal
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    MaxRetentionSec=1month
  '';

  # BTRFS scrub
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "23.11"; # Set by nixos-infect
}
