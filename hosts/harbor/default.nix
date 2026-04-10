{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ./secrets.nix
    ./storage.nix
    ./containers
    ./access.nix
    ./monitoring.nix
  ];

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

  # Compressed in-memory swap — OOM protection without disk swap
  zramSwap = {
    enable = true;
    memoryPercent = 25; # ~16GB compressed swap
  };

  # Radicale — CalDAV/CardDAV for contacts & calendar
  services.radicale = {
    enable = true;
    settings = {
      server.hosts = [ "127.0.0.1:5232" ];
      auth = {
        type = "htpasswd";
        htpasswd_filename = "/arespool/appdata/radicale/htpasswd";
        htpasswd_encryption = "bcrypt";
      };
      storage.filesystem_folder = "/arespool/appdata/radicale/collections";
    };
  };

  # Paperless-ngx — document management with OCR
  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    port = 28981;
    dataDir = "/arespool/appdata/paperless";
    passwordFile = config.sops.secrets.paperless_admin_password.path;
    settings = {
      PAPERLESS_URL = "https://paperless.matv.io";
      PAPERLESS_TIME_ZONE = "America/New_York";
      PAPERLESS_OCR_LANGUAGE = "eng";
    };
  };

  system.stateVersion = "23.05";
}
