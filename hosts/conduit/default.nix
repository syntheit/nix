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
        8443  # Wings WebSocket/API (via Caddy)
        64829 # SSH
        64830 # Rescue SSH
      ];
      allowedUDPPorts = [
        51820 # WireGuard
      ];
      # Masquerade game traffic going to harbor via WireGuard
      # Without this, harbor would route responses via its own gateway
      extraCommands = ''
        iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
      '';
      extraStopCommands = ''
        iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE 2>/dev/null || true
      '';
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
      trusted-users = [ "root" "matv" ];
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

  # Network performance tuning
  boot.kernel.sysctl = {
    # BBR congestion control — much better for long-distance connections (BA→NYC)
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    # Increase UDP/TCP buffer sizes for WireGuard throughput
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    # TCP buffer auto-tuning
    "net.ipv4.tcp_rmem" = "4096 1048576 16777216";
    "net.ipv4.tcp_wmem" = "4096 1048576 16777216";
    # Enable TCP fast open
    "net.ipv4.tcp_fastopen" = 3;
  };

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

  # NAT port forwarding — game traffic through WireGuard to harbor
  networking.nat = {
    enable = true;
    externalInterface = "ens3";
    forwardPorts = [
      { destination = "10.100.0.2:25565"; proto = "tcp"; sourcePort = 25565; } # Minecraft
      { destination = "10.100.0.2:34197"; proto = "udp"; sourcePort = 34197; } # Factorio
    ];
  };

  # Caddy reverse proxy — auto TLS via Let's Encrypt
  services.caddy = {
    enable = true;
    globalConfig = ''
      servers {
        protocols h1 h2 h3
      }
    '';
    virtualHosts."watch.matv.io" = {
      extraConfig = ''
        encode gzip zstd
        reverse_proxy 10.100.0.2:8096 {
          flush_interval -1
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          transport http {
            read_buffer 16KiB
          }
        }
      '';
    };
    virtualHosts."status.matv.io" = {
      extraConfig = ''
        reverse_proxy localhost:3001
      '';
    };
    virtualHosts."photos.matv.io" = {
      extraConfig = ''
        encode gzip zstd
        reverse_proxy 10.100.0.2:2283 {
          flush_interval -1
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          transport http {
            read_buffer 16KiB
          }
        }
      '';
    };
    virtualHosts."games.matv.io" = {
      extraConfig = ''
        encode gzip zstd
        reverse_proxy 10.100.0.2:2080 {
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
        }
      '';
    };
    # Wings API + WebSocket on separate port (game console, file manager)
    virtualHosts."games.matv.io:8443" = {
      extraConfig = ''
        reverse_proxy 10.100.0.2:8080 {
          flush_interval -1
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
        }
      '';
    };
  };

  # Fail2ban — block brute force attempts
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "168h"; # Max 1 week ban
      factor = "4";
    };
    jails.sshd = {
      settings = {
        filter = "sshd[mode=aggressive]";
        port = "64829";
      };
    };
  };

  # Gatus — status page monitoring all services from outside the network
  systemd.services.gatus = {
    description = "Gatus status monitor";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.gatus}/bin/gatus";
      DynamicUser = true;
      StateDirectory = "gatus";
      Environment = "GATUS_CONFIG_PATH=/etc/gatus/config.yaml";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  environment.etc."gatus/config.yaml".text = ''
    storage:
      type: sqlite
      path: /var/lib/gatus/data.db
      maximum-number-of-results: 64800
      maximum-number-of-events: 500

    web:
      address: 0.0.0.0
      port: 3001

    ui:
      title: Status | matv.io
      description: Service status for matv.io infrastructure
      header: Status
      link: https://status.matv.io

    endpoints:
      # ===== HARBOR SERVICES (via Cloudflare Tunnel) =====
      - name: Nextcloud
        group: harbor
        url: https://cloud.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Vaultwarden
        group: harbor
        url: https://vault.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Retrospend
        group: harbor
        url: https://retrospend.app
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Linkding
        group: harbor
        url: https://links.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Seerr
        group: harbor
        url: https://request.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: qBittorrent
        group: harbor
        url: https://downloader.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Prowlarr
        group: harbor
        url: https://prowlarr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Sonarr
        group: harbor
        url: https://sonarr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Radarr
        group: harbor
        url: https://radarr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Bazarr
        group: harbor
        url: https://bazarr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Memos
        group: harbor
        url: https://notes.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Scrutiny
        group: harbor
        url: https://drivehealth.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Syncthing
        group: harbor
        url: https://sync.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Tracearr
        group: harbor
        url: https://tracearr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Radicale
        group: harbor
        url: https://dav.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Grafana
        group: harbor
        url: https://grafana.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Paperless
        group: harbor
        url: https://paperless.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Karakeep
        group: harbor
        url: https://keep.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Docmost
        group: harbor
        url: https://docs.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      # ===== CONDUIT SERVICES (via VPS gateway) =====
      - name: Jellyfin
        group: conduit
        url: https://watch.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Immich
        group: conduit
        url: https://photos.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      # ===== RAVEN SERVICES =====
      - name: Website
        group: raven
        url: https://matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      # ===== INFRASTRUCTURE =====
      - name: WireGuard Tunnel
        group: infra
        url: icmp://10.100.0.2
        interval: 1m
        conditions:
          - "[CONNECTED] == true"

      - name: Harbor SSH
        group: infra
        url: tcp://10.100.0.2:64829
        interval: 1m
        conditions:
          - "[CONNECTED] == true"
  '';

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
