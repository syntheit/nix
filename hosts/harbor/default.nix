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
      dependsOn = [ "nextcloud-db" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    nextcloud-db = {
      image = "linuxserver/mariadb:latest";
      environmentFiles = [ config.sops.templates."nextcloud-db.env".path ];
      volumes = [
        "/arespool/appdata/nextcloud-mariadb:/config"
      ];
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
