# jelly-recs — Claude-powered recommendation rows for Jellyfin
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

    claudeOAuthTokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Env file exporting CLAUDE_CODE_OAUTH_TOKEN=<token> for the subscription
        auth flow. Generate with `claude setup-token`. Same format as elliot's
        claudeOAuthTokenFile — the same secret can be reused.
      '';
    };

    tracearrContainer = lib.mkOption {
      type = lib.types.str;
      default = "tracearr";
      description = "Name of the tracearr docker container we shell into for psql.";
    };

    claudeModel = lib.mkOption {
      type = lib.types.str;
      # 1M-context variant: standard Opus 4.7 is 200k, and our LIBRARY
      # block alone is ~280k tokens. With the 200k model the CLI silently
      # truncates the prompt before the model sees it, which produced
      # empty-schema responses every time we ran.
      default = "claude-opus-4-7[1m]";
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
      default = false;
      description = ''
        Whether to install a systemd timer that fires generation on a
        schedule. Default is false — manual-only — so a regression in
        prompt construction can't quietly burn a week of Claude quota
        in the background. Set to true once you've verified a manual
        run looks reasonable in `journalctl -u jelly-recs-generate`.
      '';
    };

    generateSchedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-1/3 04:00:00";
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

    # Long-lived HTTP server — serves /api/recs/:id and the embedded JS/CSS.
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

    # One-shot generation — invoked by timer (when autoSchedule = true)
    # or manually. restartIfChanged = false so a `nixos-rebuild switch`
    # never auto-restarts an in-flight batch — that mistake cost us a
    # session quota once and shouldn't recur.
    systemd.services."jelly-recs-generate-user@" = {
      description = "jelly-recs generation for %i (templated)";
      after = [
        "network-online.target"
        "docker.service"
      ];
      wants = [ "network-online.target" ];

      path = [
        pkgs.claude-code
      ] ++ lib.optional config.virtualisation.docker.enable config.virtualisation.docker.package;

      environment = {
        JELLY_RECS_JELLYFIN_URL = cfg.jellyfinURL;
        JELLY_RECS_JELLYFIN_API_KEY_FILE = cfg.jellyfinAPIKeyFile;
        JELLY_RECS_TRACEARR_CONTAINER = cfg.tracearrContainer;
        JELLY_RECS_STATE_DIR = cfg.stateDir;
        JELLY_RECS_CLAUDE_MODEL = cfg.claudeModel;
        HOME = cfg.stateDir;
      };

      restartIfChanged = false;
      reloadIfChanged = false;

      serviceConfig = {
        Type = "exec";
        User = "jelly-recs";
        Group = "jelly-recs";
        ExecStart = "${cfg.package}/bin/jelly-recs generate --user %i";
        RuntimeMaxSec = "10min";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        ReadWritePaths = [
          cfg.stateDir
        ] ++ lib.optional config.virtualisation.docker.enable "/run/docker.sock";

        SupplementaryGroups = lib.optional config.virtualisation.docker.enable "docker";
        EnvironmentFile = [ cfg.claudeOAuthTokenFile ];
      };
    };

    systemd.services.jelly-recs-generate = {
      description = "jelly-recs daily recommendation generation";
      after = [
        "network-online.target"
        "docker.service"
      ];
      wants = [ "network-online.target" ];

      # Tools the binary execs: claude (subscription CLI) and docker (psql shell).
      path = [
        pkgs.claude-code
      ] ++ lib.optional config.virtualisation.docker.enable config.virtualisation.docker.package;

      environment = {
        JELLY_RECS_JELLYFIN_URL = cfg.jellyfinURL;
        JELLY_RECS_JELLYFIN_API_KEY_FILE = cfg.jellyfinAPIKeyFile;
        JELLY_RECS_TRACEARR_CONTAINER = cfg.tracearrContainer;
        JELLY_RECS_STATE_DIR = cfg.stateDir;
        JELLY_RECS_CLAUDE_MODEL = cfg.claudeModel;
        # claude CLI looks under $HOME for credentials; service has no $HOME by default.
        HOME = cfg.stateDir;
      };

      # See note above: never let a rebuild auto-restart an in-flight batch.
      restartIfChanged = false;
      reloadIfChanged = false;

      serviceConfig = {
        # Type=exec returns from `systemctl start` once the process is exec'd,
        # not when it exits. Generation runs ~15 minutes for all users — we
        # don't want every manual `start` to block the shell that long.
        # The unit still goes "inactive" cleanly when the process exits, so
        # the timer's semantics are unchanged.
        Type = "exec";
        User = "jelly-recs";
        Group = "jelly-recs";
        ExecStart = "${cfg.package}/bin/jelly-recs generate";
        RuntimeMaxSec = "30min";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        ReadWritePaths = [
          cfg.stateDir
        ] ++ lib.optional config.virtualisation.docker.enable "/run/docker.sock";

        SupplementaryGroups = lib.optional config.virtualisation.docker.enable "docker";
        EnvironmentFile = [ cfg.claudeOAuthTokenFile ];
      };
    };

    systemd.timers = lib.mkIf cfg.autoSchedule {
      jelly-recs-generate = {
        description = "jelly-recs generation schedule";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.generateSchedule;
          RandomizedDelaySec = "30min";
          Persistent = true;
        };
      };
    };
  };
}
