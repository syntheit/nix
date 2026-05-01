{
  config,
  lib,
  pkgs,
  vars,
  inputs,
  ...
}:
{
  imports = [
    inputs.nixos-avf.nixosModules.avf
    ../../modules/server-safety.nix
    ../../modules/foyer.nix
    ./secrets.nix
  ];

  services.serverSafety = {
    enable = true;
    user = "droid";
  };

  # Foyer — server dashboard
  services.foyer = {
    enable = true;
    domain = "raven.matv.io";
    jwtSecretFile = config.sops.secrets.foyer_jwt_secret.path;
    apiKeyFiles = [ config.sops.secrets.foyer_api_key.path ];
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
    services = {
      "Website" = { url = "https://matv.io"; };
      "Status" = { url = "https://status.matv.io"; };
    };
    # Read CPU temperature from Android host via SSH
    temperatureCommand = "ssh -p 8022 -i /var/lib/foyer/android-ssh-key -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(ip route | awk '/default/ {print $3}') 'for z in /sys/class/thermal/thermal_zone*/; do t=$(cat \"$z/type\" 2>/dev/null); case \"$t\" in BIG|MID|LITTLE) echo $(( $(cat \"$z/temp\") / 1000 ));; esac; done' | sort -rn | head -1";
  };

  # Copy SSH key so the foyer user can read it (SSH rejects keys not owned by the caller)
  systemd.services.foyer.serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/install -m 0600 -o foyer -g foyer /home/droid/.ssh/mainkey /var/lib/foyer/android-ssh-key"
  ];

  # Override deprecated option set by nixos-avf module
  services.resolved.settings.Resolve.DNSSEC = lib.mkForce "false";

  networking.hostName = "raven";
  system.stateVersion = "26.05";

  # Headless server — no graphics/Weston
  avf.defaultUser = "droid";
  avf.enableGraphics = false;

  # SSH — key-only auth
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PrintLastLog = false;
    };
  };

  users.users."droid".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
  ];

  # Docker (start at boot — this is a server)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    liveRestore = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers = {
    website = {
      image = "synzeit/website:arm64";
      ports = [ "127.0.0.1:3000:3000" ];
      environment = {
        NODE_ENV = "production";
      };
    };
  };

  # Nix
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
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

  # Journal — cap size to reduce journald memory footprint
  services.journald.extraConfig = ''
    SystemMaxUse=200M
    MaxRetentionSec=1month
  '';

  # Network tunables — BBR congestion control + larger buffers for tunnel traffic
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    "net.ipv4.tcp_fastopen" = 3;
  };

  # Gatus — declarative status page monitoring harbor + raven services
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
      address: 127.0.0.1
      port: 3001

    ui:
      title: Status | matv.io
      description: Service status for matv.io infrastructure
      header: Status
      link: https://status.matv.io
      hide-response-time: true

    endpoints:
      # ===== HARBOR SERVICES =====
      - name: Jellyfin
        group: harbor
        url: https://watch.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Immich
        group: harbor
        url: https://photos.matv.io
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

      # ===== RAVEN SERVICES =====
      - name: Website
        group: raven
        url: https://matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Dashboard
        group: raven
        url: https://raven.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Status Page
        group: raven
        url: https://status.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"
  '';

  # Cloudflared tunnel
  services.cloudflared = {
    enable = true;
    tunnels = {
      "raven" = {
        ingress = {
          "matv.io" = "http://localhost:3000";
          "raven.matv.io" = "http://localhost:8420";
          "raven-ssh.matv.io" = "ssh://localhost:22";
        };
        default = "http_status:404";
        credentialsFile = "/etc/cloudflared/credentials.json";
      };
    };
  };

  # Packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    mosh
    cloudflared
  ];

  # Shell
  programs.mosh.enable = true;
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # User — avf module creates droid, we just add docker group
  users.users."droid".extraGroups = [ "docker" ];
  users.users."droid".shell = pkgs.zsh;

  # Firewall
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Tailscale — VPN access independent of Cloudflare tunnel
  services.tailscale.enable = true;
  systemd.services.tailscaled.restartIfChanged = false;

  # Prevent cloudflared tunnel from restarting during rebuilds
  systemd.services.cloudflared-tunnel-raven.restartIfChanged = false;

  # Security
  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults lecture = never
    '';
  };
}
