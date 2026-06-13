# Construct — Daniel's life-OS web app.
# Next.js (standalone) backed by SQLite. Auth via Better Auth.
# Iteration loop: edit → `construct-rebuild` → done.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.construct;

  buildPath = lib.makeBinPath [
    pkgs.nodejs_22
    pkgs.pnpm
    pkgs.openssl
    pkgs.pkg-config
    pkgs.prisma-engines
  ];

  # Prisma needs explicit engine paths on NixOS (no precompiled NixOS binaries
  # upstream). Same set the dev flake uses.
  prismaEnv = ''
    export PRISMA_QUERY_ENGINE_LIBRARY="${pkgs.prisma-engines}/lib/libquery_engine.node"
    export PRISMA_QUERY_ENGINE_BINARY="${pkgs.prisma-engines}/bin/query-engine"
    export PRISMA_SCHEMA_ENGINE_BINARY="${pkgs.prisma-engines}/bin/schema-engine"
    export PRISMA_SKIP_POSTINSTALL_GENERATE="1"
  '';

  rebuildScript = pkgs.writeShellScriptBin "construct-rebuild" ''
    set -euo pipefail

    if [ ! -d "${cfg.srcDir}" ]; then
      echo "construct-rebuild: source dir ${cfg.srcDir} does not exist" >&2
      exit 1
    fi

    export PATH="${buildPath}:$PATH"
    ${prismaEnv}

    cd "${cfg.srcDir}"

    echo "→ pnpm install"
    pnpm install --prefer-frozen-lockfile

    echo "→ prisma migrate deploy"
    mkdir -p "${cfg.srcDir}/data"
    DATABASE_URL="${cfg.databaseUrl}" pnpm exec prisma generate
    DATABASE_URL="${cfg.databaseUrl}" pnpm exec prisma migrate deploy

    echo "→ next build"
    pnpm build

    # adapter-static is gone — Next.js standalone emits its own server.
    # Restart picks up the new bundle + any schema migrations.
    echo "→ restart construct-app"
    sudo systemctl restart construct-app

    echo "✓ build complete. http://$(${pkgs.hostname}/bin/hostname):${toString cfg.port}/"
  '';
in
{
  options.services.construct = {
    enable = lib.mkEnableOption "Construct life-OS web app";

    srcDir = lib.mkOption {
      type = lib.types.path;
      description = "Path to the construct-app source directory (where pnpm build runs).";
      example = "/home/matv/Projects/the_construct/construct-app";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4321;
      description = "HTTP port to bind to.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. With harbor's firewall (Tailscale/wg only on trusted interfaces),
        0.0.0.0 means reachable from any device on Tailscale, blocked from the public internet.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "matv";
      description = "User the service runs as.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port to the public internet. Default: false (Tailscale/wg only).";
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "file:${cfg.srcDir}/data/app.db";
      description = "Prisma DATABASE_URL. Defaults to SQLite under srcDir/data/.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://harbor:${toString cfg.port}";
      description = ''
        Public URL the app considers itself reachable at. Used by Better Auth
        for trustedOrigins / baseURL and for OpenGraph metadata.
      '';
    };

    authSecretFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/construct-app/secret.env";
      description = ''
        Path to an env-format file containing AUTH_SECRET=... (and optionally
        TRUSTED_ORIGINS=...). The file is loaded via systemd EnvironmentFile,
        not built into the Nix store. Generate the secret with:
          sudo mkdir -p /var/lib/construct-app
          sudo bash -c 'echo "AUTH_SECRET=\"$(openssl rand -base64 32)\"" > /var/lib/construct-app/secret.env'
          sudo chmod 400 /var/lib/construct-app/secret.env
          sudo chown ${cfg.user} /var/lib/construct-app/secret.env
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.construct-app = {
      description = "Construct life-OS web app (Next.js standalone)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Don't start until first build has produced the standalone server.
      unitConfig.ConditionPathExists = "${cfg.srcDir}/.next/standalone/server.js";

      environment = {
        NODE_ENV = "production";
        HOSTNAME = cfg.address;
        PORT = toString cfg.port;
        DATABASE_URL = cfg.databaseUrl;
        PUBLIC_URL = cfg.publicUrl;
        PRISMA_QUERY_ENGINE_LIBRARY = "${pkgs.prisma-engines}/lib/libquery_engine.node";
        PRISMA_QUERY_ENGINE_BINARY = "${pkgs.prisma-engines}/bin/query-engine";
        PRISMA_SCHEMA_ENGINE_BINARY = "${pkgs.prisma-engines}/bin/schema-engine";
      };

      serviceConfig = {
        # Next.js standalone bundles its own server entrypoint. Run it under
        # the same node that built it.
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/.next/standalone/server.js";

        # AUTH_SECRET (+ optionally TRUSTED_ORIGINS) loaded from disk, not from
        # the Nix store. systemd EnvironmentFile is the cleanest way.
        EnvironmentFile = cfg.authSecretFile;

        WorkingDirectory = cfg.srcDir;
        Restart = "on-failure";
        RestartSec = "5s";
        User = cfg.user;

        # Hardening — service writes only to its data dir (SQLite + WAL).
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "${cfg.srcDir}/data" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        LockPersonality = true;
      };
    };

    environment.systemPackages = [ rebuildScript ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
