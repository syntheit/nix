# Elliot — Telegram monitoring bot powered by Claude Code
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.elliot;

  configJson = builtins.toJSON {
    telegram = {
      token_file = cfg.telegramTokenFile;
      allowed_user_ids = cfg.allowedUserIDs;
      alert_chat_id = cfg.alertChatID;
    };
    claude = {
      path = "claude";
      model = cfg.model;
      max_budget_usd = cfg.maxBudgetUSD;
      mcp_binary = "${pkgs.elliot}/bin/elliot-mcp";
    };
    data_dir = cfg.dataDir;
    health_check = {
      enabled = cfg.healthCheck.enable;
      interval = cfg.healthCheck.interval;
    };
    session = {
      max_recent_messages = cfg.session.maxRecentMessages;
      summarize_after = cfg.session.summarizeAfter;
    };
    tools = {
      ping_allowlist = cfg.pingAllowlist;
      command_timeout = cfg.commandTimeout;
      prometheus_url = cfg.prometheusURL;
      gatus_url = cfg.gatusURL;
      scrutiny_url = cfg.scrutinyURL;
    };
  };
in
{
  options.services.elliot = {
    enable = lib.mkEnableOption "Elliot Telegram monitoring bot";

    telegramTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the Telegram bot token";
    };

    allowedUserIDs = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      description = "Telegram user IDs allowed to interact with the bot";
    };

    alertChatID = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Telegram chat ID for health check alerts (0 to disable)";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "opus";
      description = "Claude model to use";
    };

    maxBudgetUSD = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Maximum dollar amount per Claude invocation";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/elliot";
    };

    anthropicApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to env file containing ANTHROPIC_API_KEY for API-based auth (pay-per-token).
      '';
    };

    claudeOAuthTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to env file containing CLAUDE_CODE_OAUTH_TOKEN (long-lived subscription token).
        Generate with `claude setup-token` — it prints a token to stdout. Save it in a
        sops secret as `CLAUDE_CODE_OAUTH_TOKEN=<token>`.
      '';
    };

    healthCheck = {
      enable = lib.mkEnableOption "scheduled health checks";
      interval = lib.mkOption {
        type = lib.types.str;
        default = "4h";
        description = "Health check interval (Go duration format)";
      };
    };

    session = {
      maxRecentMessages = lib.mkOption {
        type = lib.types.int;
        default = 10;
      };
      summarizeAfter = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Number of exchanges before triggering summarization";
      };
    };

    pingAllowlist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hostnames/IPs the ping_host tool is allowed to reach";
    };

    commandTimeout = lib.mkOption {
      type = lib.types.str;
      default = "30s";
    };

    prometheusURL = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9090";
    };

    gatusURL = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:3001";
    };

    scrutinyURL = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:5153";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."elliot/config.json".text = configJson;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 elliot elliot -"
    ];

    users.users.elliot = {
      isSystemUser = true;
      group = "elliot";
      extraGroups = lib.optional config.virtualisation.docker.enable "docker";
      home = cfg.dataDir;
    };
    users.groups.elliot = { };

    systemd.services.elliot = {
      description = "Elliot Telegram monitoring bot";
      after = [ "network-online.target" ]
        ++ lib.optional config.virtualisation.docker.enable "docker.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Tools that MCP tool handlers exec directly.
      path = [
        pkgs.elliot
        pkgs.claude-code
      ]
      ++ lib.optional config.virtualisation.docker.enable config.virtualisation.docker.package
      ++ (with pkgs; [
        coreutils # uname
        procps # ps, free
        systemd # systemctl, journalctl
        util-linux # general
        iputils # ping
        wireguard-tools # wg
        zfs # zpool, zfs
        btrfs-progs # btrfs
      ]);

      serviceConfig = {
        Type = "simple";
        User = "elliot";
        Group = "elliot";
        ExecStart = "${pkgs.elliot}/bin/elliot --config /etc/elliot/config.json --prompts ${pkgs.elliot}/share/elliot/prompts";
        Restart = "always";
        RestartSec = "10s";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;

        ReadWritePaths = [
          cfg.dataDir
        ] ++ lib.optional config.virtualisation.docker.enable "/run/docker.sock";

        SupplementaryGroups = lib.optional config.virtualisation.docker.enable "docker";
        EnvironmentFile =
          lib.optional (cfg.anthropicApiKeyFile != null) cfg.anthropicApiKeyFile
          ++ lib.optional (cfg.claudeOAuthTokenFile != null) cfg.claudeOAuthTokenFile;
      };
    };
  };
}
