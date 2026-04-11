{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware.nix
  ];

  networking = {
    hostName = "conduit";
    # Static IP — RackNerd VPS does not use DHCP
    useDHCP = false;
    usePredictableInterfaceNames = false; # Single NIC VPS — keep eth0
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "192.3.203.146";
        prefixLength = 26;
      }];
    };
    defaultGateway = {
      address = "192.3.203.129";
      interface = "eth0";
    };
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80    # Caddy ACME HTTP-01
        443   # Caddy HTTPS
        64829 # SSH
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
      PermitRootLogin = "prohibit-password"; # TODO: change to "no" after initial setup
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
    users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
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

    # Dead man's switch
    (writeShellScriptBin "arm-watchdog" ''
      mkdir -p /var/lib/nixos-watchdog
      readlink /run/current-system > /var/lib/nixos-watchdog/rollback-target
      echo "Saved rollback target: $(cat /var/lib/nixos-watchdog/rollback-target)"
      systemctl start nixos-watchdog.timer
      echo "Watchdog armed. You have 10 minutes to disarm with: sudo disarm-watchdog"
    '')
    (writeShellScriptBin "disarm-watchdog" ''
      systemctl stop nixos-watchdog.timer
      systemctl stop nixos-watchdog.service 2>/dev/null || true
      rm -f /var/lib/nixos-watchdog/rollback-target
      echo "Watchdog disarmed. Config is permanent."
    '')
  ];

  # Dead man's switch
  systemd.services.nixos-watchdog = {
    description = "Dead man's switch - rolls back to saved generation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "watchdog-rollback" ''
        if [ -f /var/lib/nixos-watchdog/rollback-target ]; then
          TARGET=$(cat /var/lib/nixos-watchdog/rollback-target)
          echo "Watchdog triggered! Rolling back to: $TARGET"
          nix-env -p /nix/var/nix/profiles/system --set "$TARGET"
          "$TARGET/bin/switch-to-configuration" switch
          rm -f /var/lib/nixos-watchdog/rollback-target
        else
          echo "No rollback target found, rebooting as fallback"
          systemctl reboot
        fi
      '';
    };
  };

  systemd.timers.nixos-watchdog = {
    description = "Dead man's switch timer (10 min)";
    timerConfig = {
      OnActiveSec = "10min";
      Unit = "nixos-watchdog.service";
      RemainAfterElapse = false;
    };
  };

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

  system.stateVersion = "25.05";
}
