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
    ./nix-builder.nix
    ./storage.nix
    ./containers
    ./access.nix
    ./mdm.nix
    ./monitoring.nix
    ./virt.nix
    ../../modules/server-safety.nix
    ../../modules/argus.nix
    ../../modules/foyer.nix
    ../../modules/elliot.nix
    ../../modules/construct.nix
    ../../modules/jelly-recs.nix
    ../../modules/harborfin.nix
    ../../modules/asado-list.nix
  ];

  services.serverSafety = {
    enable = true;
    user = "matv";
  };

  # Argus — container update management (replaces Watchtower)
  services.argus = {
    enable = true;
    exclude = [ "immich_postgres" ];

    containers = {
      jellyfin = { policy = "manual"; };

      # Containers with database backup associations.
      # retrospend is deployed via local builds (not the registry), so Argus must
      # NOT auto-update it — pulling the stale registry :latest downgrades it below
      # the migrated DB schema and breaks the app. "manual" keeps backups, no pulls.
      retrospend = { policy = "manual"; backups = [ "retrospend" ]; };
      retrospend_sidecar = { policy = "manual"; backups = [ "retrospend" ]; };
      retrospend_postgres = { policy = "manual"; backups = [ "retrospend" ]; };
      immich_server = { backups = [ "immich" ]; };
      immich_machine_learning = { backups = [ "immich" ]; };
      docmost = { backups = [ "docmost" ]; };
      docmost_postgres = { backups = [ "docmost" ]; };
      pelican_panel = { backups = [ "pelican" ]; };
      pelican_db = { backups = [ "pelican" ]; };
      seafile = { backups = [ "seafile" ]; };
      seafile_db = { backups = [ "seafile" ]; };
    };

    # Version-coupled stacks that must update together (stop all → pull → start all).
    groups = {
      immich.members = [ "immich_server" "immich_machine_learning" ];
    };

    backups = {
      retrospend = { type = "postgres"; container = "retrospend_postgres"; database = "retrospend"; };
      docmost = { type = "postgres"; container = "docmost_postgres"; database = "docmost"; user = "docmost"; };
      pelican = { type = "mariadb"; container = "pelican_db"; };
      immich = { type = "postgres"; container = "immich_postgres"; database = "immich"; };
      seafile = { type = "mariadb"; container = "seafile_db"; };
    };
  };

  # Foyer — server dashboard
  services.foyer = {
    enable = true;
    domain = "harbor.matv.io";
    jwtSecretFile = config.sops.secrets.foyer_jwt_secret.path;
    apiKeyFiles = [ config.sops.secrets.foyer_api_key.path ];
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
    services = {
      "Jellyfin" = { url = "https://watch.matv.io"; };
      "Immich" = { url = "https://photos.matv.io"; };
      "Vaultwarden" = { url = "https://vault.matv.io"; };
      "Retrospend" = { url = "https://retrospend.app"; };
      "Linkding" = { url = "https://links.matv.io"; };
      "Seerr" = { url = "https://request.matv.io"; };
      "qBittorrent" = { url = "https://downloader.matv.io"; };
      "Prowlarr" = { url = "https://prowlarr.matv.io"; };
      "Sonarr" = { url = "https://sonarr.matv.io"; };
      "Radarr" = { url = "https://radarr.matv.io"; };
      "Bazarr" = { url = "https://bazarr.matv.io"; };
      "Memos" = { url = "https://notes.matv.io"; };
      "Scrutiny" = { url = "https://drivehealth.matv.io"; };
      "Syncthing" = { url = "https://sync.matv.io"; };
      "Tracearr" = { url = "https://tracearr.matv.io"; };
      "Radicale" = { url = "https://dav.matv.io"; };
      "Grafana" = { url = "https://grafana.matv.io"; };
      "Paperless" = { url = "https://paperless.matv.io"; };
      "Karakeep" = { url = "https://keep.matv.io"; };
      "Docmost" = { url = "https://docs.matv.io"; };
      "Seafile" = { url = "https://files.matv.io"; };
      "Website" = { url = "https://matv.io"; };
      "Headscale" = { url = "https://headscale.matv.io/health"; };
    };
    jellyfin = {
      enable = true;
      url = "http://localhost:8096";
      apiKeyFile = config.sops.secrets.foyer_jellyfin_api_key.path;
    };
    minecraft = {
      enable = true;
      address = "localhost:25565";
    };
    vmController.enable = true;
    nvidiaPackage = config.hardware.nvidia.package.bin;
  };

  # Construct — Daniel's life-OS web app. Next.js standalone backed by SQLite.
  # Cross-device state is in the app's own SQLite now (KvState table).
  # Iteration loop: edit code → `construct-rebuild` → done.
  services.construct = {
    enable = true;
    srcDir = "/home/matv/Projects/the_construct/construct-app";
    port = 4321;
    publicUrl = "http://harbor:4321";
  };

  # asado-list — static viewer for the asado & tech waitlist triage.
  # Public hostname via cloudflared (asado-list.matv.io) is gated by a
  # Cloudflare Access policy configured in the CF dashboard, NOT here.
  services.asado-list = {
    enable = true;
    srcDir = "/home/matv/Projects/asado-list/static";
    port = 4730;
  };

  # jelly-recs — content + collaborative recommendation rows for Jellyfin
  services.jelly-recs = {
    enable = true;
    jellyfinURL = "http://127.0.0.1:8096";
    jellyfinAPIKeyFile = config.sops.secrets.jelly_recs_jellyfin_api_key.path;
    # Bind to all interfaces; wg0 is firewall-trusted, so conduit's Caddy
    # reaches us via WireGuard while LAN/WAN stay closed.
    listenAddr = "0.0.0.0:5300";
  };

  # harborfin — bespoke Jellyfin web client. Production at watch2.matv.io
  # (conduit's Caddy proxies to harbor:8097); dev mode reachable over Tailscale.
  services.harborfin = {
    enable = true;
    srcDir = "/home/matv/Projects/harborfin";
    port = 8097;
    dev.enable = true;
    dev.port = 5174;
  };

  # Elliot — Telegram monitoring bot
  services.elliot = {
    enable = true;
    telegramTokenFile = config.sops.secrets.elliot_telegram_token.path;
    claudeOAuthTokenFile = config.sops.templates."elliot-claude.env".path;
    allowedUserIDs = [ 921730321 ]; # Daniel
    alertChatID = 921730321;
    model = "opus";
    healthCheck = {
      enable = true;
      interval = "4h";
    };
    pingAllowlist = [ "10.100.0.1" "conduit" ];
    gatusURL = "http://10.100.0.1:3001"; # Gatus runs on conduit, reachable via WireGuard
  };

  # Networking configuration
  networking = {
    hostId = "fdbe6a1e";
    hostName = "harbor";
    networkmanager.enable = true;
    nftables.enable = true;
    nftables.flushRuleset = false;
    firewall = {
      enable = true;
      trustedInterfaces = [ "tailscale0" "wg0" ];
      extraInputRules = ''
        ip saddr 172.31.0.0/16 tcp dport {2283,8096} accept
      '';
    };
  };

  # WireGuard tunnel to conduit (VPS gateway)
  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.100.0.2/24" ];
    privateKeyFile = config.sops.secrets.wg_conduit_private_key.path;
    peers = [{
      publicKey = "bhXOmLJsZDR0ZeF/Wnzt116Jw0tHzbfhoe2kG2+ZDAw=";
      endpoint = "192.3.203.146:51820";
      allowedIPs = [ "10.100.0.1/32" ];
      persistentKeepalive = 25;
    }];
  };

  # NextDNS — ID loaded from sops secret at runtime, stamped into a resolved
  # drop-in on every (re)start so config-only rebuilds can't leave resolved stale.
  # If sops hasn't rendered the template (e.g. age key missing), fall back to
  # Cloudflare DoT so the box still has working DNS instead of failing to start.
  systemd.services.systemd-resolved = {
    after = [ "sops-nix.service" ];
    wants = [ "sops-nix.service" ];
    serviceConfig.ExecStartPre = [
      "+${pkgs.writeShellScript "apply-nextdns" ''
        mkdir -p /etc/systemd/resolved.conf.d
        src=${config.sops.templates."nextdns-resolved.conf".path}
        if [ -f "$src" ]; then
          install -m 0644 "$src" /etc/systemd/resolved.conf.d/10-nextdns.conf
        else
          echo "apply-nextdns: sops template missing, using Cloudflare DoT fallback" >&2
          install -m 0644 ${pkgs.writeText "resolved-fallback.conf" ''
            [Resolve]
            DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com
            DNSOverTLS=yes
          ''} /etc/systemd/resolved.conf.d/10-nextdns.conf
        fi
      ''}"
    ];
    restartTriggers = [ config.sops.templates."nextdns-resolved.conf".content ];
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
    mosh # also enabled via programs.mosh for firewall + utempter
    curl
    git
    speedtest-cli
    sqlite
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
    wget
    jq
    iotop
    nethogs
    tcpdump
    sops
    ssh-to-age

  ];

  programs.mosh.enable = true;
  programs.zsh.enable = true;

  # Services configuration
  services = {
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
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

  # Passwordless sudo for wheel (TEMPORARY — remove this line and rebuild to revert)
  security.sudo.wheelNeedsPassword = false;

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

  # Radicale data directories (must exist before systemd mount namespacing)
  systemd.tmpfiles.rules = [
    "d /arespool/appdata/radicale 0750 radicale radicale -"
    "d /arespool/appdata/radicale/collections 0750 radicale radicale -"
  ];

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
