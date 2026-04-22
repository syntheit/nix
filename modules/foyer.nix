# Foyer — self-hosted server dashboard
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.foyer;

  configJson = builtins.toJSON {
    mode = cfg.mode;
    port = cfg.port;
    domain = cfg.domain;
    cookie_domain = cfg.cookieDomain;
    data_dir = cfg.dataDir;
    hostname = config.networking.hostName;
    api_keys = [ ]; # SSH key auth is primary; API keys loaded from files below
    api_key_files = cfg.apiKeyFiles;
    authorized_keys = cfg.authorizedKeys;
    allow_signups = cfg.allowSignups;
    users = [ ]; # Users register via the web UI; first user is admin
    services = lib.mapAttrsToList (name: svc: {
      inherit name;
      url = svc.url;
    }) cfg.services;
    hosts = lib.mapAttrsToList (name: host: {
      inherit name;
      url = host.url;
      api_key = ""; # Loaded at runtime via host API key files
    }) cfg.hosts;
    jellyfin =
      if cfg.jellyfin.enable then {
        url = cfg.jellyfin.url;
        api_key_file = cfg.jellyfin.apiKeyFile;
      } else null;
  };
in
{
  options.services.foyer = {
    enable = lib.mkEnableOption "Foyer server dashboard";

    mode = lib.mkOption {
      type = lib.types.enum [ "full" "api-only" ];
      default = "full";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8420;
    };

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Public domain for this instance";
    };

    cookieDomain = lib.mkOption {
      type = lib.types.str;
      default = ".matv.io";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/foyer";
    };

    jwtSecretFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing JWT signing key (>= 32 bytes)";
    };

    apiKeyFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys authorized for API access";
    };

    allowSignups = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.url = lib.mkOption { type = lib.types.str; };
      });
      default = { };
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.url = lib.mkOption { type = lib.types.str; };
      });
      default = { };
    };

    jellyfin = {
      enable = lib.mkEnableOption "Jellyfin streams API";
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:8096";
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."foyer/config.json".text = configJson;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 foyer foyer -"
      "d ${cfg.dataDir}/files 0750 foyer foyer -"
    ];

    users.users.foyer = {
      isSystemUser = true;
      group = "foyer";
      extraGroups = lib.optional config.virtualisation.docker.enable "docker";
      home = cfg.dataDir;
    };
    users.groups.foyer = { };

    systemd.services.foyer = {
      description = "Foyer server dashboard";
      after = [ "network-online.target" ]
        ++ lib.optional config.virtualisation.docker.enable "docker.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "foyer";
        Group = "foyer";
        ExecStart = "${pkgs.foyer}/bin/foyer --config /etc/foyer/config.json --jwt-secret-file ${cfg.jwtSecretFile}";
        Restart = "always";
        RestartSec = "5s";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;

        # Read /proc and /sys for health metrics
        ReadOnlyPaths = [ "/proc" "/sys" ];

        # Docker socket access for container listing
        SupplementaryGroups = lib.optional config.virtualisation.docker.enable "docker";
      };
    };

    # Daily cleanup: expired files, pastes, old service checks
    systemd.services.foyer-cleanup = {
      description = "Foyer cleanup";
      serviceConfig = {
        Type = "oneshot";
        User = "foyer";
        Group = "foyer";
        ExecStart = "${pkgs.foyer}/bin/foyer --cleanup --config /etc/foyer/config.json --jwt-secret-file ${cfg.jwtSecretFile}";
      };
    };

    systemd.timers.foyer-cleanup = {
      description = "Foyer daily cleanup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:30:00";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
