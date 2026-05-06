# harborfin — bespoke Jellyfin web client.
#
# Two services:
#   harborfin       — production static SPA, served by static-web-server on :8097.
#                     Built from `${cfg.srcDir}/build` (populated by `harborfin-rebuild`).
#   harborfin-dev   — opt-in Vite dev server on 0.0.0.0:5174 (Tailscale-reachable).
#                     Hot-reload from ${cfg.srcDir}. Same Vite proxy points at
#                     localhost JF + jelly-recs, so dev hits the real backend.
#
# Iteration loop: edit code → `harborfin-rebuild` → done (prod).
# Dev loop:       `sudo systemctl start harborfin-dev` → http://harbor:5174.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.harborfin;

  # Build toolchain — pinned via nixpkgs so it tracks the rest of the system.
  buildPath = lib.makeBinPath [ pkgs.nodejs_22 pkgs.pnpm ];

  rebuildScript = pkgs.writeShellScriptBin "harborfin-rebuild" ''
    set -euo pipefail

    if [ ! -d "${cfg.srcDir}" ]; then
      echo "harborfin-rebuild: source dir ${cfg.srcDir} does not exist" >&2
      exit 1
    fi

    export PATH="${buildPath}:$PATH"

    cd "${cfg.srcDir}"

    echo "→ pnpm install"
    pnpm install --prefer-frozen-lockfile

    echo "→ pnpm build"
    pnpm build

    if ! systemctl is-active --quiet harborfin; then
      echo "→ first build: starting harborfin"
      sudo systemctl start harborfin
    fi

    echo "✓ build/ updated. http://$(${pkgs.hostname}/bin/hostname):${toString cfg.port}/"
  '';
in
{
  options.services.harborfin = {
    enable = lib.mkEnableOption "harborfin Jellyfin web client (static, served by static-web-server)";

    srcDir = lib.mkOption {
      type = lib.types.path;
      description = "Path to the harborfin source directory (where pnpm build runs).";
      example = "/home/matv/Projects/harborfin";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8097;
      description = "HTTP port for the production static server.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. With harbor's firewall (Tailscale/wg trusted only), 0.0.0.0
        means "reachable from Tailscale and from conduit over WireGuard, blocked
        from the public internet." conduit's Caddy reaches us via WireGuard.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "matv";
      description = "User the production static-web-server runs as. Needs read access to ${toString cfg.srcDir}/build.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the prod port to the public internet. Default: false (Tailscale/wg only).";
    };

    dev = {
      enable = lib.mkEnableOption "harborfin-dev — Vite dev server, Tailscale-reachable";

      port = lib.mkOption {
        type = lib.types.port;
        default = 5174;
        description = "Vite dev server port. Bound to 0.0.0.0 so Tailscale clients can hit it.";
      };

      jellyfinURL = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8096";
        description = "Where the Vite dev proxy forwards JF API calls.";
      };

      recsURL = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:5300";
        description = "Where the Vite dev proxy forwards /api/recs/* calls.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "matv";
        description = "User the dev service runs as. Needs read+write on srcDir for vite cache.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Production: static SPA ---
    systemd.services.harborfin = {
      description = "harborfin static SPA (static-web-server → ${toString cfg.srcDir}/build)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Don't try to start if there's no build yet. First `harborfin-rebuild` will start it.
      unitConfig.ConditionPathExists = "${cfg.srcDir}/build/index.html";

      serviceConfig = {
        # No --page-fallback here: it 404s on every missing path including
        # hashed JS chunks (`/_app/immutable/foo.{HASH}.js`), which makes a
        # stale index.html serve HTML for missing modules and the browser
        # rejects the response as a bad MIME. SPA fallback is done by Caddy
        # on conduit, which only rewrites *non-asset* paths to /index.html.
        ExecStart = "${pkgs.static-web-server}/bin/static-web-server --root ${cfg.srcDir}/build --host ${cfg.address} --port ${toString cfg.port} --compression-static true";
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

    # --- Dev: Vite hot-reload, Tailscale-reachable ---
    systemd.services.harborfin-dev = lib.mkIf cfg.dev.enable {
      description = "harborfin Vite dev server (0.0.0.0:${toString cfg.dev.port})";
      after = [ "network.target" ];
      # Manual-start by default so a `nixos-rebuild switch` doesn't yank a
      # Vite session out from under whoever is hacking on the UI.
      wantedBy = [ ];

      path = [ pkgs.nodejs_22 pkgs.pnpm ];

      environment = {
        HARBORFIN_JELLYFIN_URL = cfg.dev.jellyfinURL;
        HARBORFIN_RECS_URL = cfg.dev.recsURL;
        # pnpm needs a writable home for its store cache.
        HOME = "/home/${cfg.dev.user}";
        # Vite picks these up automatically.
        HOST = "0.0.0.0";
        PORT = toString cfg.dev.port;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.dev.user;
        WorkingDirectory = cfg.srcDir;
        # Ensure deps are present (idempotent), then exec vite dev.
        ExecStart = pkgs.writeShellScript "harborfin-dev-start" ''
          set -euo pipefail
          export PATH="${buildPath}:$PATH"
          if [ ! -d node_modules ]; then
            pnpm install --prefer-frozen-lockfile
          fi
          exec pnpm run dev --host 0.0.0.0 --port ${toString cfg.dev.port}
        '';
        Restart = "on-failure";
        RestartSec = "5s";
        # No restart-on-rebuild — vite's HMR is the truth here.
      };
    };

    # `harborfin-rebuild` available in PATH for matv (and root).
    environment.systemPackages = [ rebuildScript ];

    # Optional: open the prod port to the public internet. Default Tailscale/wg only.
    networking.firewall.allowedTCPPorts =
      lib.optionals cfg.openFirewall [ cfg.port ];
  };
}
