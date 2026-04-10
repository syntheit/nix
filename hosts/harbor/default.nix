{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ./hardware-configuration.nix ];

  # sops-nix — secrets decrypted at activation time to /run/secrets/
  sops.defaultSopsFile = ../../secrets/harbor.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.nextdns_id = { };
  sops.secrets.nextcloud_db_root_pw = { };
  sops.secrets.nextcloud_db_name = { };
  sops.secrets.nextcloud_db_user = { };
  sops.secrets.nextcloud_db_pw = { };
  sops.secrets.qbittorrent_webui_password = { };
  sops.secrets.linkding_superuser_name = { };
  sops.secrets.linkding_superuser_password = { };
  sops.secrets.bitwarden_installation_id = { };
  sops.secrets.bitwarden_installation_key = { };
  sops.secrets.bitwarden_db_password = { };
  sops.secrets.retrospend_postgres_password = { };
  sops.secrets.retrospend_auth_secret = { };
  sops.secrets.retrospend_worker_api_key = { };
  sops.secrets.retrospend_openrouter_api_key = { };
  sops.secrets.retrospend_smtp_user = { };
  sops.secrets.retrospend_smtp_password = { };
  sops.secrets.immich_db_password = { };
  sops.secrets.vpn_openvpn_user = { };
  sops.secrets.vpn_openvpn_password = { };

  # qBittorrent env file
  sops.templates."qbittorrent.env".content = ''
    VPN_TYPE=wireguard
    WEBUI_PASSWORD=${config.sops.placeholder.qbittorrent_webui_password}
  '';

  # Bitwarden env file
  sops.templates."bitwarden.env".content = ''
    BW_DOMAIN=vault.matv.io
    BW_INSTALLATION_ID=${config.sops.placeholder.bitwarden_installation_id}
    BW_INSTALLATION_KEY=${config.sops.placeholder.bitwarden_installation_key}
    BW_DB_PROVIDER=mysql
    BW_DB_SERVER=bitwarden_db
    BW_DB_DATABASE=bitwarden_vault
    BW_DB_USERNAME=bitwarden
    BW_DB_PASSWORD=${config.sops.placeholder.bitwarden_db_password}
  '';

  # Bitwarden DB env file
  sops.templates."bitwarden-db.env".content = ''
    MARIADB_RANDOM_ROOT_PASSWORD=true
    MARIADB_USER=bitwarden
    MARIADB_PASSWORD=${config.sops.placeholder.bitwarden_db_password}
    MARIADB_DATABASE=bitwarden_vault
  '';

  # Retrospend env file (shared by app + sidecar)
  sops.templates."retrospend.env".content = ''
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${config.sops.placeholder.retrospend_postgres_password}
    POSTGRES_DB_NAME=retrospend
    DATABASE_URL=postgresql://postgres:${config.sops.placeholder.retrospend_postgres_password}@postgres:5432/retrospend
    AUTH_SECRET=${config.sops.placeholder.retrospend_auth_secret}
    WORKER_API_KEY=${config.sops.placeholder.retrospend_worker_api_key}
    OPENROUTER_API_KEY=${config.sops.placeholder.retrospend_openrouter_api_key}
    OPENROUTER_MODEL=qwen/qwen-2.5-7b-instruct
    SIDECAR_URL=http://sidecar:8080
    PUBLIC_URL=https://retrospend.app
    UPLOAD_DIR=/data/uploads
    SHOW_LANDING_PAGE=true
    ENABLE_LEGAL_PAGES=true
    AUDIT_PRIVACY_MODE=anonymized
    SMTP_HOST=smtppro.zoho.com
    SMTP_PORT=587
    SMTP_USER=${config.sops.placeholder.retrospend_smtp_user}
    SMTP_PASSWORD=${config.sops.placeholder.retrospend_smtp_password}
    EMAIL_FROM=Retrospend <noreply@retrospend.app>
  '';

  # Retrospend Postgres env file
  sops.templates."retrospend-postgres.env".content = ''
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${config.sops.placeholder.retrospend_postgres_password}
    POSTGRES_DB=retrospend
  '';

  # Immich env file (shared by server + ML + postgres)
  sops.templates."immich.env".content = ''
    DB_USERNAME=postgres
    DB_PASSWORD=${config.sops.placeholder.immich_db_password}
    DB_DATABASE_NAME=immich
    IMMICH_VERSION=release
    UPLOAD_LOCATION=/arespool/nextcloud/data/topikzero/files/ImmichUpload
  '';

  # Immich Postgres env file
  sops.templates."immich-postgres.env".content = ''
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${config.sops.placeholder.immich_db_password}
    POSTGRES_DB=immich
    POSTGRES_INITDB_ARGS=--data-checksums
    DB_STORAGE_TYPE=SSD
  '';

  # VPN (Gluetun) env file
  sops.templates."vpn.env".content = ''
    VPN_SERVICE_PROVIDER=custom
    VPN_TYPE=openvpn
    OPENVPN_CUSTOM_CONFIG=/gluetun/custom.conf
    OPENVPN_USER=${config.sops.placeholder.vpn_openvpn_user}
    OPENVPN_PASSWORD=${config.sops.placeholder.vpn_openvpn_password}
    FIREWALL_VPN_INPUT_PORTS=2283,5096
    FIREWALL_OUTBOUND_SUBNETS=172.24.0.0/16
    PUID=1000
    PGID=1000
  '';

  # Linkding env file
  sops.templates."linkding.env".content = ''
    LD_SUPERUSER_NAME=${config.sops.placeholder.linkding_superuser_name}
    LD_SUPERUSER_PASSWORD=${config.sops.placeholder.linkding_superuser_password}
    LD_CSRF_TRUSTED_ORIGINS=https://links.matv.io
    LD_DISABLE_BACKGROUND_TASKS=False
    LD_DISABLE_URL_VALIDATION=False
  '';

  # Nextcloud MariaDB env file — rendered from sops secrets at boot
  sops.templates."nextcloud-db.env".content = ''
    PUID=1000
    PGID=1000
    MYSQL_ROOT_PASSWORD=${config.sops.placeholder.nextcloud_db_root_pw}
    TZ=America/New_York
    MYSQL_DATABASE=${config.sops.placeholder.nextcloud_db_name}
    MYSQL_USER=${config.sops.placeholder.nextcloud_db_user}
    MYSQL_PASSWORD=${config.sops.placeholder.nextcloud_db_pw}
  '';

  # Boot configuration
  boot = {
    loader.systemd-boot.enable = true;
    loader.systemd-boot.configurationLimit = 20;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [ "zfs" ];
    blacklistedKernelModules = [ "nouveau" ];
    kernelParams = [
      "i915.enable_guc=2"
      "zfs.zfs_arc_max=34359738368" # 32GB — half of RAM, leaves room for Docker/OS
    ];
    zfs = {
      forceImportRoot = false;
      extraPools = [
        "arespool"
        "lambdapool"
        "iotapool"
        "thetapool"
        "deltapool"
        "epsilpool"
        "rhopool"
        "platapool"
      ];
    };
    # tmpfs for /tmp — reduces SSD writes
    tmp.useTmpfs = true;
    tmp.tmpfsSize = "16G";
    # Server-tuned sysctl
    kernel.sysctl = {
      "vm.swappiness" = 10; # Low — prefer reclaiming ZFS ARC over swapping
      "vm.vfs_cache_pressure" = 50; # ZFS handles its own caching
      "vm.dirty_bytes" = 268435456; # 256MB — flush dirty pages at fixed thresholds
      "vm.dirty_background_bytes" = 67108864; # 64MB
    };
  };

  # Compressed in-memory swap — OOM protection without disk swap
  zramSwap = {
    enable = true;
    memoryPercent = 25; # ~16GB compressed swap
  };

  # Networking configuration
  networking = {
    hostId = "fdbe6a1e";
    hostName = "harbor";
    networkmanager.enable = true;
    nftables.enable = true;
    firewall = {
      enable = true;
      extraInputRules = ''
        ip saddr 172.31.0.0/16 tcp dport {2283,8096} accept
      '';
    };
  };

  # NextDNS — ID loaded from sops secret at runtime
  sops.templates."nextdns-resolved.conf".content = ''
    [Resolve]
    DNS=45.90.28.0#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNS=2a07:a8c0::#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNS=45.90.30.0#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNS=2a07:a8c1::#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNSOverTLS=yes
  '';

  systemd.services.apply-nextdns = {
    description = "Apply NextDNS config from sops secret";
    after = [ "sops-nix.service" "systemd-resolved.service" ];
    wants = [ "sops-nix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "apply-nextdns" ''
        mkdir -p /etc/systemd/resolved.conf.d
        cp ${config.sops.templates."nextdns-resolved.conf".path} /etc/systemd/resolved.conf.d/10-nextdns.conf
        systemctl restart systemd-resolved
      '';
    };
  };

  time.timeZone = "America/New_York";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  # GPU drivers — headless server, no X11 needed
  # nvidia driver required for container toolkit (Jellyfin GPU transcoding)
  services.xserver.videoDrivers = [ "nvidia" "intel" ];

  # Hardware configuration
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };
    cpu.intel.updateMicrocode = true;
    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = false; # No GUI on a headless server
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
    nvidia-container-toolkit.enable = true;
  };

  # Nixpkgs configuration
  nixpkgs.config.allowUnfree = true;

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
      download-buffer-size = 134217728; # 128MB — faster downloads
      min-free = 1073741824; # 1GB — auto-GC when free space drops below
      max-free = 3221225472; # 3GB — stop GC once this much space is free
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # User configuration
  users = {
    defaultUserShell = pkgs.zsh;
    users = {
      matv = {
        isNormalUser = true;
        description = "Daniel";
        extraGroups = [
          "networkmanager"
          "wheel"
          "docker"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
        ];
      };
    };
  };

  # System packages and programs
  environment.systemPackages = with pkgs; [
    fastfetch
    zsh
    btop
    cloudflared
    mosh
    git
    speedtest-cli
    lshw
    dmidecode
    pciutils
    smartmontools
    nvme-cli
    duf
    bat
    python3
    plocate
    tmux
    ncdu
    curl
    wget
    jq
    iotop
    nethogs
    tcpdump

    # Dead man's switch — arm before risky rebuilds, disarm after verifying access
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

  programs.zsh.enable = true;

  # Services configuration
  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
      extraConfig = ''
        AllowTcpForwarding yes
      '';
      ports = [ 64829 ];
    };
    resolved = {
      enable = true;
      settings = {
        Resolve = {
          DNSOverTLS = "yes";
        };
      };
    };
    # SMART drive monitoring
    smartd = {
      enable = true;
      autodetect = true;
      notifications.wall.enable = true;
    };
    # ZFS automatic scrub — detects silent data corruption
    zfs.autoScrub = {
      enable = true;
      interval = "monthly";
    };
    # BTRFS periodic scrub on root filesystem
    btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = [ "/" ];
    };
    # File indexing for locate/plocate
    locate = {
      enable = true;
      package = pkgs.plocate;
    };
    # Seerr — media request management (native NixOS service, no Docker)
    seerr.enable = true;
  };

  # Cap journal size to prevent unbounded growth
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1month
  '';

  # Kill runaway processes before the system becomes unresponsive
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
  };

  # Docker (start at boot — this is a server)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };

  # Create Docker networks for multi-container stacks
  systemd.services.docker-networks = {
    description = "Create Docker networks for multi-container stacks";
    after = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "create-docker-networks" ''
        ${pkgs.docker}/bin/docker network create nextcloud_default || true
        ${pkgs.docker}/bin/docker network create downloader_media_network || true
        ${pkgs.docker}/bin/docker network create bitwarden_default || true
        ${pkgs.docker}/bin/docker network create retrospend_default || true
        ${pkgs.docker}/bin/docker network create immich_default || true
      '';
    };
  };
  # Network dependencies
  systemd.services.docker-nextcloud.after = [ "docker-networks.service" ];
  systemd.services.docker-nextcloud_db.after = [ "docker-networks.service" ];
  systemd.services.docker-qbittorrent.after = [ "docker-networks.service" ];
  systemd.services.docker-sonarr.after = [ "docker-networks.service" ];
  systemd.services.docker-radarr.after = [ "docker-networks.service" ];
  systemd.services.docker-bazarr.after = [ "docker-networks.service" ];
  systemd.services.docker-jackett.after = [ "docker-networks.service" ];
  systemd.services.docker-bitwarden.after = [ "docker-networks.service" ];
  systemd.services.docker-bitwarden_db.after = [ "docker-networks.service" ];
  systemd.services.docker-retrospend.after = [ "docker-networks.service" ];
  systemd.services.docker-retrospend_sidecar.after = [ "docker-networks.service" ];
  systemd.services.docker-retrospend_postgres.after = [ "docker-networks.service" ];
  systemd.services.docker-retrospend_ollama.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-retrospend_ollama.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-vpn.after = [ "docker-networks.service" ];
  systemd.services.docker-edge.after = [ "docker-vpn.service" ];
  systemd.services.docker-immich_server.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_server.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_machine_learning.after = [ "docker-networks.service" ];
  systemd.services.docker-immich_postgres.after = [ "docker-networks.service" ];
  systemd.services.docker-immich_redis.after = [ "docker-networks.service" ];
  # NVIDIA CDI dependency
  systemd.services.docker-jellyfin.after = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-jellyfin.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];

  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers = {
    nextcloud = {
      image = "lscr.io/linuxserver/nextcloud:latest";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
      };
      ports = [ "127.0.0.1:9787:443" ];
      volumes = [
        "/arespool/appdata/nextcloud_config:/config"
        "/arespool/nextcloud/data:/arespool/nextcloud/data"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
      ];
      dependsOn = [ "nextcloud_db" ];
      extraOptions = [ "--network=nextcloud_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    nextcloud_db = {
      image = "linuxserver/mariadb:latest";
      environmentFiles = [ config.sops.templates."nextcloud-db.env".path ];
      volumes = [
        "/arespool/appdata/nextcloud-mariadb:/config"
      ];
      extraOptions = [ "--network=nextcloud_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    jellyfin = {
      image = "lscr.io/linuxserver/jellyfin:latest";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
        JELLYFIN_PublishedServerUrl = "watch.matv.io";
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "all";
      };
      ports = [
        "127.0.0.1:8096:8096"
        "127.0.0.1:8920:8920"
      ];
      volumes = [
        "/micron01/appdata/jellyfin_config:/config"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [
        "--device=nvidia.com/gpu=all"
        "-v" "${pkgs.writeShellScript "abyss-spotlight" ''
          #!/bin/bash
          echo "[abyss] Installing Spotlight..."
          WEBDIR="/usr/share/jellyfin/web"
          if [ ! -d "$WEBDIR" ]; then
            echo "[abyss] $WEBDIR not found"
            exit 0
          fi
          mkdir -p "$WEBDIR/ui"
          curl -sL "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/spotlight.html" -o "$WEBDIR/ui/spotlight.html"
          curl -sL "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/spotlight.css" -o "$WEBDIR/ui/spotlight.css"
          CHUNK=$(find "$WEBDIR" -name "home-html.*.chunk.js" ! -name "*.bak" | head -1)
          if [ -n "$CHUNK" ]; then
            # Restore from backup if chunk is corrupted or already patched incorrectly
            if [ -f "$CHUNK.bak" ] && [ "$(wc -c < "$CHUNK")" -lt 1000 ]; then
              cp "$CHUNK.bak" "$CHUNK"
            fi
            # Patch if not already patched
            if ! grep -q "spotlight" "$CHUNK" 2>/dev/null; then
              [ ! -f "$CHUNK.bak" ] && cp "$CHUNK" "$CHUNK.bak"
              curl -sL "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/home-html.chunk.js" -o "$CHUNK"
            fi
          fi
          echo "[abyss] Spotlight installed"
        ''}:/custom-cont-init.d/abyss-spotlight"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    # ===== DOWNLOADING STACK (shared downloader_media_network) =====
    qbittorrent = {
      image = "trigus42/qbittorrentvpn";
      environmentFiles = [ config.sops.templates."qbittorrent.env".path ];
      ports = [ "127.0.0.1:9091:8080" ];
      volumes = [
        "/arespool/appdata/qbittorrent:/config"
        "/rhopool/Downloads:/downloads"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [
        "--network=downloader_media_network"
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun"
        "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
        "--sysctl=net.ipv6.conf.all.disable_ipv6=0"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    # Seerr runs as a native NixOS service (see services.seerr below)
    jackett = {
      image = "lscr.io/linuxserver/jackett:latest";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
        AUTO_UPDATE = "true";
      };
      ports = [ "127.0.0.1:9117:9117" ];
      volumes = [
        "/arespool/appdata/jackett:/config"
        "/rhopool/Downloads:/downloads"
      ];
      dependsOn = [ "qbittorrent" ];
      extraOptions = [ "--network=downloader_media_network" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    sonarr = {
      image = "linuxserver/sonarr";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
      };
      ports = [ "127.0.0.1:8989:8989" ];
      volumes = [
        "/arespool/appdata/sonarr:/config"
        "/rhopool/Downloads:/downloads"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [ "--network=downloader_media_network" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    radarr = {
      image = "linuxserver/radarr";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
      };
      ports = [ "127.0.0.1:7878:7878" ];
      volumes = [
        "/arespool/appdata/radarr:/config"
        "/rhopool/Downloads:/downloads"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [ "--network=downloader_media_network" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    bazarr = {
      image = "linuxserver/bazarr";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
      };
      ports = [ "127.0.0.1:6767:6767" ];
      volumes = [
        "/arespool/appdata/bazarr:/config"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [ "--network=downloader_media_network" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    portainer = {
      image = "portainer/portainer-ce:latest";
      ports = [ "127.0.0.1:9443:9443" ];
      volumes = [
        "/arespool/appdata/Portainer:/data"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    memos = {
      image = "neosmemo/memos:stable";
      user = "1000:1000";
      ports = [ "127.0.0.1:5230:5230" ];
      volumes = [
        "/arespool/appdata/memos:/var/opt/memos"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    scrutiny = {
      image = "ghcr.io/analogj/scrutiny:master-omnibus";
      ports = [
        "127.0.0.1:5153:8080"
        "127.0.0.1:39419:8086"
      ];
      volumes = [
        "/run/udev:/run/udev:ro"
        "/arespool/appdata/srcutiny/config:/opt/scrutiny/config"
        "/arespool/appdata/srcutiny/influxdb:/opt/scrutiny/influxdb"
      ];
      extraOptions = [
        "--cap-add=SYS_RAWIO"
        "--cap-add=SYS_ADMIN"
        "--device=/dev/nvme0"
        "--device=/dev/nvme1"
        "--device=/dev/nvme2"
        "--device=/dev/sda"
        "--device=/dev/sdb"
        "--device=/dev/sdc"
        "--device=/dev/sdd"
        "--device=/dev/sde"
        "--device=/dev/sdf"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    syncthing = {
      image = "lscr.io/linuxserver/syncthing:latest";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
      };
      ports = [
        "127.0.0.1:8384:8384"
        "22000:22000/tcp"
        "22000:22000/udp"
        "21027:21027/udp"
      ];
      volumes = [
        "/arespool/appdata/syncthing/config:/config"
        "/arespool/nextcloud/data/topikzero/files/Sync:/config/Sync"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    # ===== IMMICH + VPN (shared immich_default network) =====
    vpn = {
      image = "qmcgaw/gluetun";
      environmentFiles = [ config.sops.templates."vpn.env".path ];
      environment = {
        HEALTH_RESTART_VPN = "on"; # Auto-restart VPN if health check fails
        HEALTH_TARGET_ADDRESSES = "cloudflare.com:443,github.com:443";
        HEALTH_SMALL_CHECK_TYPE = "icmp";
      };
      ports = [
        "12283:2283"
        "15096:5096"
      ];
      volumes = [
        "/arespool/appdata/vpn/ovpn/windscribe.ovpn:/gluetun/custom.conf:ro"
      ];
      extraOptions = [
        "--network=immich_default"
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun"
        "--health-cmd" "wget -q -O /dev/null https://cloudflare.com || exit 1"
        "--health-interval" "30s"
        "--health-timeout" "10s"
        "--health-retries" "3"
      ];
    };
    immich_server = {
      image = "ghcr.io/immich-app/immich-server:release";
      environmentFiles = [ config.sops.templates."immich.env".path ];
      environment = {
        NVIDIA_DRIVER_CAPABILITIES = "all";
        NVIDIA_VISIBLE_DEVICES = "all";
      };
      ports = [ "127.0.0.1:2283:2283" ];
      volumes = [
        "/arespool/nextcloud/data/topikzero/files/ImmichUpload:/usr/src/app/upload"
        "/arespool/nextcloud/data/topikzero/files/Photos/Google Photos:/mnt/media/Google Photos:ro"
        "/arespool/nextcloud/data/topikzero/files/Photos/InstantUpload:/mnt/media/InstantUpload:ro"
        "/arespool/photos-videos:/mnt/media/photos-videos:ro"
        "/etc/localtime:/etc/localtime:ro"
      ];
      dependsOn = [ "immich_postgres" "immich_redis" ];
      extraOptions = [
        "--network=immich_default"
        "--device=nvidia.com/gpu=all"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    immich_machine_learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:release";
      environmentFiles = [ config.sops.templates."immich.env".path ];
      volumes = [
        "/arespool/appdata/immich/model-cache:/cache"
      ];
      dependsOn = [ "immich_postgres" ];
      extraOptions = [ "--network=immich_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    immich_postgres = {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
      environmentFiles = [ config.sops.templates."immich-postgres.env".path ];
      volumes = [
        "/arespool/appdata/immich/postgres/pgdata:/var/lib/postgresql/data"
      ];
      extraOptions = [
        "--network=immich_default"
        "--network-alias=database"
        "--shm-size=128m"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    immich_redis = {
      image = "valkey/valkey:9";
      extraOptions = [
        "--network=immich_default"
        "--network-alias=redis"
      ];
    };
    edge = {
      image = "caddy:2-alpine";
      dependsOn = [ "vpn" ];
      volumes = [
        "/arespool/appdata/vpn/caddy/config:/etc/caddy"
        "/arespool/appdata/vpn/caddy/data:/data"
        "/arespool/appdata/vpn/certs/photos.matv.io:/certs:ro"
      ];
      extraOptions = [ "--network=container:vpn" "--entrypoint" "/bin/sh" ];
      cmd = [ "-lc" "echo 'Waiting for Immich...'; until nc -z immich_server 2283; do sleep 1; done; exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile" ];
    };
    # ===== RETROSPEND (shared retrospend_default network) =====
    retrospend = {
      image = "synzeit/retrospend:latest";
      environmentFiles = [ config.sops.templates."retrospend.env".path ];
      ports = [ "127.0.0.1:1997:1997" ];
      volumes = [
        "retrospend_uploads:/data/uploads"
      ];
      dependsOn = [ "retrospend_postgres" "retrospend_sidecar" ];
      extraOptions = [ "--network=retrospend_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    retrospend_sidecar = {
      image = "synzeit/retrospend-sidecar:latest";
      environmentFiles = [ config.sops.templates."retrospend.env".path ];
      volumes = [
        "retrospend_sidecar_data:/app/data"
        "retrospend_backup_data:/backups"
      ];
      dependsOn = [ "retrospend_postgres" ];
      extraOptions = [
        "--network=retrospend_default"
        "--network-alias=sidecar"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    retrospend_postgres = {
      image = "postgres:16-alpine";
      environmentFiles = [ config.sops.templates."retrospend-postgres.env".path ];
      volumes = [
        "retrospend_postgres_data:/var/lib/postgresql/data"
      ];
      extraOptions = [
        "--network=retrospend_default"
        "--network-alias=postgres"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    retrospend_ollama = {
      image = "ollama/ollama:latest";
      volumes = [
        "retrospend_ollama_data:/root/.ollama"
      ];
      extraOptions = [
        "--network=retrospend_default"
        "--network-alias=ollama"
        "--device=nvidia.com/gpu=all"
        "--dns=1.1.1.1"
        "--dns=1.0.0.1"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    # ===== BITWARDEN (shared bitwarden_default network) =====
    bitwarden = {
      image = "ghcr.io/bitwarden/self-host:beta";
      environmentFiles = [ config.sops.templates."bitwarden.env".path ];
      ports = [ "127.0.0.1:29446:8080" ];
      volumes = [
        "/arespool/appdata/bitwarden/bitwarden:/etc/bitwarden"
        "/arespool/appdata/bitwarden/logs:/var/log/bitwarden"
      ];
      dependsOn = [ "bitwarden_db" ];
      extraOptions = [ "--network=bitwarden_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    bitwarden_db = {
      image = "mariadb:10";
      environmentFiles = [ config.sops.templates."bitwarden-db.env".path ];
      volumes = [
        "/arespool/appdata/bitwarden_db/data:/var/lib/mysql"
      ];
      extraOptions = [ "--network=bitwarden_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    linkding = {
      image = "sissbruecker/linkding:latest-plus";
      environmentFiles = [ config.sops.templates."linkding.env".path ];
      ports = [ "127.0.0.1:28793:9090" ];
      volumes = [
        "/arespool/appdata/linkding:/etc/linkding/data"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    watchtower = {
      image = "containrrr/watchtower:1.7.1";
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      cmd = [ "--label-enable" "--cleanup" "--interval" "3600" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    tracearr = {
      image = "ghcr.io/connorgallopo/tracearr:supervised";
      ports = [ "127.0.0.1:7898:3000" ];
      environment = {
        TZ = "America/New_York";
        LOG_LEVEL = "info";
      };
      volumes = [
        "tracearr_tracearr_postgres:/data/postgres"
        "tracearr_tracearr_redis:/data/redis"
        "tracearr_tracearr_data:/data/tracearr"
      ];
      extraOptions = [
        "--shm-size=256m"
        "--memory=2g"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
  };

  # =====================================================
  # COCKROACH ACCESS INFRASTRUCTURE
  # Never restart access services during nixos-rebuild switch.
  # Changes only take effect on reboot. This prevents losing access.
  # =====================================================

  services.cloudflared = {
    enable = true;
    tunnels = {
      "harbor" = {
        ingress = {
          "admin.matv.io" = "ssh://localhost:64829";
          "containers.matv.io" = {
            service = "https://localhost:9443";
            originRequest.noTLSVerify = true;
          };
          "request.matv.io" = "http://localhost:5055";
          "links.matv.io" = "http://localhost:28793";
          "cloud.matv.io" = {
            service = "https://localhost:9787";
            originRequest.noTLSVerify = true;
          };
          "downloader.matv.io" = "http://localhost:9091";
          "jackett.matv.io" = "http://localhost:9117";
          "sonarr.matv.io" = "http://localhost:8989";
          "radarr.matv.io" = "http://localhost:7878";
          "bazarr.matv.io" = "http://localhost:6767";
          "notes.matv.io" = "http://localhost:5230";
          "vault.matv.io" = "http://localhost:29446";
          "drivehealth.matv.io" = "http://localhost:5153";
          "sync.matv.io" = "http://localhost:8384";
          "watch.matv.io" = "http://localhost:8096";
          "retrospend.app" = "http://localhost:1997";
          "tracearr.matv.io" = "http://localhost:7898";
        };
        default = "http_status:404";
        credentialsFile = "/etc/cloudflared/credentials.json";
      };
    };
  };
  systemd.services.cloudflared-tunnel-harbor.restartIfChanged = false;

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  systemd.services.tailscaled.restartIfChanged = false;

  # Rescue SSH — independent of services.openssh, reachable over Tailscale on port 64830.
  # If main sshd or tunnel breaks, this still works.
  systemd.services.sshd-rescue = {
    description = "Rescue SSH daemon";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = false;
    serviceConfig = {
      ExecStart = "${pkgs.openssh}/bin/sshd -D -f /etc/ssh/sshd_rescue_config";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  environment.etc."ssh/sshd_rescue_config".text = ''
    Port 64830
    PidFile /run/sshd-rescue.pid
    HostKey /etc/ssh/ssh_host_ed25519_key
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
    AllowUsers matv
    StrictModes yes
  '';

  # Dead man's switch — rolls back to saved generation if not disarmed
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

  system.stateVersion = "23.05";
}
