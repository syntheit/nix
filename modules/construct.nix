# Construct — Daniel's life-OS web companion app.
# Static SvelteKit build served by darkhttpd. No docker, no node runtime.
# Iteration loop: edit → `construct-rebuild` → done.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.construct;

  # Build toolchain — pinned via nixpkgs so it tracks the rest of the system.
  buildPath = lib.makeBinPath [ pkgs.nodejs_22 pkgs.pnpm ];

  rebuildScript = pkgs.writeShellScriptBin "construct-rebuild" ''
    set -euo pipefail

    if [ ! -d "${cfg.srcDir}" ]; then
      echo "construct-rebuild: source dir ${cfg.srcDir} does not exist" >&2
      exit 1
    fi

    # Pnpm-invoked binaries (svelte-kit, vite) shell out to `node`, so node
    # must be on PATH in addition to pnpm itself.
    export PATH="${buildPath}:$PATH"

    cd "${cfg.srcDir}"

    echo "→ pnpm install"
    pnpm install --prefer-frozen-lockfile

    echo "→ pnpm build"
    pnpm build

    # darkhttpd reads files per request — no restart needed.
    # If the service hadn't started yet (first build), kick it.
    if ! systemctl is-active --quiet construct-app; then
      echo "→ first build: starting construct-app"
      sudo systemctl start construct-app
    fi

    echo "✓ build/ updated. http://$(${pkgs.hostname}/bin/hostname):${toString cfg.port}/"
  '';
in
{
  options.services.construct = {
    enable = lib.mkEnableOption "Construct life-OS web app (static, served by darkhttpd)";

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
        0.0.0.0 means "reachable from any device on Tailscale, blocked from the public internet".
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "matv";
      description = "User the service runs as. Needs read access to ${toString cfg.srcDir}/build.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port to the public internet. Default: false (Tailscale/wg only).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.construct-app = {
      description = "Construct life-OS web app (static-web-server → ${toString cfg.srcDir}/build)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Don't try to start if there's no build yet. First `construct-rebuild` will start it.
      unitConfig.ConditionPathExists = "${cfg.srcDir}/build/index.html";

      serviceConfig = {
        # static-web-server with --page-fallback gives SPA-style routing:
        # any path that isn't a real file falls through to index.html (200 OK),
        # and SvelteKit's client-side router takes over.
        ExecStart = "${pkgs.static-web-server}/bin/static-web-server --root ${cfg.srcDir}/build --host ${cfg.address} --port ${toString cfg.port} --page-fallback ${cfg.srcDir}/build/index.html --compression-static true";
        Restart = "on-failure";
        RestartSec = "5s";

        User = cfg.user;

        # Hardening — read-only access to home is enough; static-web-server only reads files.
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

    # `construct-rebuild` available in PATH for matv (and root).
    environment.systemPackages = [ rebuildScript ];

    # Optional: open the port to the public internet. Default Tailscale-only.
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
