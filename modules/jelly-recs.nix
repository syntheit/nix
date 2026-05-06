# jelly-recs — content + collaborative recommendation rows for Jellyfin
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.jelly-recs;
in
{
  options.services.jelly-recs = {
    enable = lib.mkEnableOption "jelly-recs recommendation engine";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.jelly-recs;
      defaultText = "pkgs.jelly-recs";
    };

    jellyfinURL = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8096";
      description = "Base URL for the Jellyfin server (no trailing slash).";
    };

    jellyfinAPIKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the Jellyfin API key (raw, no surrounding quotes).";
    };

    tracearrContainer = lib.mkOption {
      type = lib.types.str;
      default = "tracearr";
      description = "Name of the tracearr docker container we shell into for psql.";
    };

    listenAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:5300";
      description = ''
        HTTP listen address for `jelly-recs serve`. Defaults to localhost so
        the service is only reachable through Caddy. Set to e.g.
        "10.100.0.2:5300" to expose it directly on a WireGuard interface.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/jelly-recs";
    };

    autoSchedule = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to install a systemd timer that fires generation on a
        schedule. The hybrid engine takes <30 s per user and uses no paid
        APIs, so running often is cheap. Set false to disable.
      '';
    };

    generateSchedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 04:00:00";
      description = "systemd OnCalendar expression (only used when autoSchedule = true).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [
      # World-readable so any user on the host can run `jelly-recs status`
      # and inspect recs without sudo. Contents are user ids + recommended
      # titles — already visible in Jellyfin's UI, so no privacy gain from
      # locking it down further.
      "d ${cfg.stateDir} 0755 jelly-recs jelly-recs -"
    ];

    users.users.jelly-recs = {
      isSystemUser = true;
      group = "jelly-recs";
      # Needs docker group to exec into the tracearr container for psql.
      extraGroups = lib.optional config.virtualisation.docker.enable "docker";
      home = cfg.stateDir;
    };
    users.groups.jelly-recs = { };

    # Long-lived HTTP server — serves /api/recs/:id.
    systemd.services.jelly-recs-server = {
      description = "jelly-recs HTTP server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        JELLY_RECS_JELLYFIN_URL = cfg.jellyfinURL;
        JELLY_RECS_JELLYFIN_API_KEY_FILE = cfg.jellyfinAPIKeyFile;
        JELLY_RECS_TRACEARR_CONTAINER = cfg.tracearrContainer;
        JELLY_RECS_STATE_DIR = cfg.stateDir;
        JELLY_RECS_LISTEN_ADDR = cfg.listenAddr;
      };

      serviceConfig = {
        Type = "simple";
        User = "jelly-recs";
        Group = "jelly-recs";
        ExecStart = "${cfg.package}/bin/jelly-recs serve";
        Restart = "on-failure";
        RestartSec = "10s";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;

        ReadWritePaths = [ cfg.stateDir ];
      };
    };

    # Per-user generate (templated). Hybrid engine: catalog scoring +
    # tracearr cross-user signal. No external APIs, no LLM.
    systemd.services."jelly-recs-generate-user@" = {
      description = "jelly-recs generation for %i";
      after = [
        "network-online.target"
        "docker.service"
      ];
      wants = [ "network-online.target" ];

      path = lib.optional config.virtualisation.docker.enable config.virtualisation.docker.package;

      environment = {
        JELLY_RECS_JELLYFIN_URL = cfg.jellyfinURL;
        JELLY_RECS_JELLYFIN_API_KEY_FILE = cfg.jellyfinAPIKeyFile;
        JELLY_RECS_TRACEARR_CONTAINER = cfg.tracearrContainer;
        JELLY_RECS_STATE_DIR = cfg.stateDir;
        HOME = cfg.stateDir;
      };

      serviceConfig = {
        Type = "exec";
        User = "jelly-recs";
        Group = "jelly-recs";
        ExecStart = "${cfg.package}/bin/jelly-recs generate --user %i";
        RuntimeMaxSec = "5min";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        ReadWritePaths = [
          cfg.stateDir
        ] ++ lib.optional config.virtualisation.docker.enable "/run/docker.sock";

        SupplementaryGroups = lib.optional config.virtualisation.docker.enable "docker";
      };
    };

    # Full-batch generate (all active users).
    systemd.services.jelly-recs-generate = {
      description = "jelly-recs full-batch generation";
      after = [
        "network-online.target"
        "docker.service"
      ];
      wants = [ "network-online.target" ];

      path = lib.optional config.virtualisation.docker.enable config.virtualisation.docker.package;

      environment = {
        JELLY_RECS_JELLYFIN_URL = cfg.jellyfinURL;
        JELLY_RECS_JELLYFIN_API_KEY_FILE = cfg.jellyfinAPIKeyFile;
        JELLY_RECS_TRACEARR_CONTAINER = cfg.tracearrContainer;
        JELLY_RECS_STATE_DIR = cfg.stateDir;
        HOME = cfg.stateDir;
      };

      serviceConfig = {
        Type = "exec";
        User = "jelly-recs";
        Group = "jelly-recs";
        ExecStart = "${cfg.package}/bin/jelly-recs generate";
        RuntimeMaxSec = "10min";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        ReadWritePaths = [
          cfg.stateDir
        ] ++ lib.optional config.virtualisation.docker.enable "/run/docker.sock";

        SupplementaryGroups = lib.optional config.virtualisation.docker.enable "docker";
      };
    };

    systemd.timers = lib.mkIf cfg.autoSchedule {
      jelly-recs-generate = {
        description = "jelly-recs generation schedule";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.generateSchedule;
          RandomizedDelaySec = "10min";
          Persistent = true;
        };
      };
    };
  };
}
