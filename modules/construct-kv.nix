# construct-kv — SQLite-backed KV API serving cross-device state to construct-app.
# Node + Hono + better-sqlite3. Behind Tailscale on harbor:4322 by default.
# Iteration: edit code → `construct-rebuild` → done (construct.nix chains this in).
{ config, lib, pkgs, ... }:

let
  cfg = config.services.construct-kv;

  # If better-sqlite3 ever needs to compile from source instead of using its
  # prebuilt binary, add: python3 gcc gnumake pkg-config. Today prebuild-install
  # fetches a binary during pnpm install, so node + pnpm is enough.
  buildPath = lib.makeBinPath [ pkgs.nodejs_22 pkgs.pnpm ];

  rebuildScript = pkgs.writeShellScriptBin "construct-kv-rebuild" ''
    set -euo pipefail

    if [ ! -d "${cfg.srcDir}" ]; then
      echo "construct-kv-rebuild: source dir ${cfg.srcDir} does not exist" >&2
      exit 1
    fi

    export PATH="${buildPath}:$PATH"

    cd "${cfg.srcDir}"

    echo "→ pnpm install (kv)"
    pnpm install --prefer-frozen-lockfile

    echo "→ pnpm build (kv)"
    pnpm build

    echo "→ restart construct-kv"
    sudo systemctl restart construct-kv

    echo "✓ construct-kv built and (re)started on :${toString cfg.port}"
  '';
in
{
  options.services.construct-kv = {
    enable = lib.mkEnableOption "construct-kv (SQLite KV API for construct-app cross-device state)";

    srcDir = lib.mkOption {
      type = lib.types.path;
      description = "Path to the construct-kv source directory (where pnpm build runs).";
      example = "/home/matv/Projects/the_construct/tools/construct-kv";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4322;
      description = "HTTP port to bind to.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. With harbor's firewall (Tailscale/wg only on trusted interfaces),
        0.0.0.0 means "reachable from any device on Tailscale, blocked from the public internet".
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "matv";
      description = "User the service runs as. Needs to own the state dir.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port to the public internet. Default: false (Tailscale/wg only).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.construct-kv = {
      description = "construct-kv — SQLite KV API for construct-app";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Don't try to start before the first build has produced dist/index.js.
      # construct-kv-rebuild will produce it and then issue an explicit restart.
      unitConfig.ConditionPathExists = "${cfg.srcDir}/dist/index.js";

      environment = {
        CONSTRUCT_KV_PORT = toString cfg.port;
        CONSTRUCT_KV_HOST = cfg.address;
        # StateDirectory makes /var/lib/construct-kv writable for User=${cfg.user}.
        CONSTRUCT_KV_DB = "/var/lib/construct-kv/kv.sqlite";
      };

      serviceConfig = {
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/dist/index.js";
        Restart = "on-failure";
        RestartSec = "5s";

        User = cfg.user;
        StateDirectory = "construct-kv";
        StateDirectoryMode = "0750";

        # Hardening — read-only home + /var/lib/construct-kv as the only writable path.
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
        # better-sqlite3 mmaps the DB file — leaving MemoryDenyWriteExecute off.
      };
    };

    environment.systemPackages = [ rebuildScript ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
