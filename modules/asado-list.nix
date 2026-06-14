# Asado-list — static viewer for the asado & tech waitlist triage.
# Self-contained HTML/CSV/JSON served by static-web-server, fronted by Cloudflare
# Access (policy lives in the CF dashboard, NOT in this config).
{ config, lib, pkgs, ... }:

let
  cfg = config.services.asado-list;
in
{
  options.services.asado-list = {
    enable = lib.mkEnableOption "asado-list static viewer";

    srcDir = lib.mkOption {
      type = lib.types.path;
      description = "Directory containing viewer.html, ranked.csv, ranked.json.";
      example = "/home/matv/Projects/asado-list/static";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4730;
      description = "HTTP port to bind to.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. Harbor's firewall trusts tailscale0/wg0 only, so 0.0.0.0
        means "reachable over Tailscale + via cloudflared tunnel, blocked from
        the public internet."
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "matv";
      description = "User the service runs as. Needs read access to srcDir.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.asado-list = {
      description = "Asado-list static viewer (static-web-server → ${toString cfg.srcDir})";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig.ConditionPathExists = "${cfg.srcDir}/viewer.html";

      serviceConfig = {
        ExecStart = "${pkgs.static-web-server}/bin/static-web-server --root ${cfg.srcDir} --host ${cfg.address} --port ${toString cfg.port} --compression-static true --directory-listing true";
        Restart = "on-failure";
        RestartSec = "5s";

        User = cfg.user;

        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
      };
    };
  };
}
