# construct (v2) — Daniel's life portal. Hono + node:sqlite API serving a Vite/React SPA.
# Replaces services.construct (the Next.js app) once it reaches parity; both run side by side until then.
# Iteration loop: edit → `construct-life-rebuild` → done.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.constructLife;
  node = pkgs.nodejs_24;
  garminPython = pkgs.python3.withPackages (p: [ p.garminconnect ]);

  baseUrl = "https://construct.matv.io";

  # One-time sign-in link for a device: open it in a browser or paste it into the Android app.
  linkScript = pkgs.writeShellScriptBin "construct-link" ''
    exec env CONSTRUCT_DB=/var/lib/construct/construct.db CONSTRUCT_BASE_URL=${baseUrl} \
      ${node}/bin/node ${cfg.srcDir}/dist/cli.js session-link "$@"
  '';

  # `construct routes|api|capture|openapi`: the portal's API for Claude Code and scripts. Runs in-process on the
  # production DB (no server, no session); the service's env minus Jellyfin. Seerr (TMDB lookups for culture canon/recs) reads
  # its key from the sops file, owner matv. Needs `construct-life-rebuild` once for dist/cli.js.
  cliScript = pkgs.writeShellScriptBin "construct" ''
    exec env \
      CONSTRUCT_DB=/var/lib/construct/construct.db \
      CONSTRUCT_LIFE=${cfg.lifeDir} \
      CONSTRUCT_BASE_URL=${baseUrl} \
      CONSTRUCT_AI_MODEL=claude-sonnet-5-5 \
      SEERR_URL=http://localhost:5055 \
      SEERR_API_KEY_FILE=${config.sops.secrets.seerr_api_key.path} \
      CAR_HUNT_DIR=/home/${cfg.user}/Projects/car-hunt \
      GARMIN_PYTHON=${garminPython}/bin/python3 \
      GARMIN_TOKEN_DIR=/var/lib/construct/garmin \
      GARMIN_SYNC_SCRIPT=${cfg.srcDir}/garmin/garmin_sync.py \
      TZ=America/Argentina/Buenos_Aires \
      ${node}/bin/node ${cfg.srcDir}/dist/cli.js "$@"
  '';

  rebuildScript = pkgs.writeShellScriptBin "construct-life-rebuild" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ node pkgs.pnpm ]}:$PATH"
    cd "${cfg.srcDir}"
    echo "→ pnpm install"
    pnpm install --prefer-frozen-lockfile
    echo "→ build"
    pnpm build
    echo "→ restart construct-life"
    sudo systemctl restart construct-life
    echo "✓ http://$(${pkgs.hostname}/bin/hostname):${toString cfg.port}/"
  '';
in
{
  options.services.constructLife = {
    enable = lib.mkEnableOption "construct life portal (v2)";

    srcDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/matv/Projects/the_construct/app";
      description = "Source directory; `pnpm build` writes dist/ here.";
    };

    lifeDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/matv/Projects/the_construct/life";
      description = "Documents (Markdown + front matter) the app reads and writes.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4322;
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "matv";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra env (CF_ACCESS_TEAM, CF_ACCESS_AUD, ANTHROPIC_WORKSPACE_ID). Not secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.construct-life = {
      description = "construct life portal (v2)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "${cfg.srcDir}/dist/server.js";

      # claude (local AI backend) comes from the user profile.
      path = [ node pkgs.git "/etc/profiles/per-user/${cfg.user}" ];

      environment = {
        NODE_ENV = "production";
        HOST = "0.0.0.0"; # firewall: tailnet only; public traffic arrives via cloudflared on localhost
        PORT = toString cfg.port;
        HOME = "/home/${cfg.user}";
        CONSTRUCT_DB = "/var/lib/construct/construct.db";
        CONSTRUCT_LIFE = cfg.lifeDir;
        ANTHROPIC_KEY_FILE = config.sops.secrets.anthropic_key.path;
        CONSTRUCT_AI_MODEL = "claude-sonnet-5-5";
        ANTHROPIC_WORKSPACE_ID = "wrkspc_01LpEQYMaLkXFBGsrjGRwfYm";
        CONSTRUCT_OWNER_EMAIL = "daniel@matv.io"; # must match the Cloudflare Access login email
        CONSTRUCT_BASE_URL = baseUrl; # prefix for pairing links
        SEERR_URL = "http://localhost:5055";
        SEERR_API_KEY_FILE = config.sops.secrets.seerr_api_key.path;
        JELLYFIN_DATA = "/arespool/appdata/jellyfin_config/data/data";
        CAR_HUNT_DIR = "/home/${cfg.user}/Projects/car-hunt";
        GARMIN_PYTHON = "${garminPython}/bin/python3";
        GARMIN_TOKEN_DIR = "/var/lib/construct/garmin";
        FDROID_DIR = "/var/lib/construct/fdroid"; # android/scripts/release.sh publishes here
        FDROID_PASSWORD_FILE = config.sops.secrets.fdroid_password.path;
        GARMIN_SYNC_SCRIPT = "${cfg.srcDir}/garmin/garmin_sync.py";
        TZ = "America/Argentina/Buenos_Aires";
      } // cfg.environment;

      serviceConfig = {
        ExecStart = "${node}/bin/node ${cfg.srcDir}/dist/server.js";
        WorkingDirectory = cfg.srcDir;
        User = cfg.user;
        StateDirectory = "construct";
        Restart = "on-failure";
        RestartSec = "5s";
        # Home stays writable: the local AI backend runs Claude Code, which writes ~/.claude.
        ProtectSystem = "full";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
      };
    };

    # One-time Garmin login (email, password, MFA), run by Daniel in a terminal.
    environment.systemPackages = [
      rebuildScript
      linkScript
      cliScript
      # Build, sign and publish the Android app to the private F-Droid repo.
      (pkgs.writeShellScriptBin "construct-android-release" ''
        set -euo pipefail
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        base64 -d ${config.sops.secrets.android_keystore_b64.path} > "$tmp/construct.p12"
        cd ${cfg.srcDir}/../android
        export FDROID_DIR=/var/lib/construct/fdroid KEY_ALIAS=construct
        export KEYSTORE_FILE="$tmp/construct.p12"
        export KEYSTORE_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path}
        export KEY_PASSWORD_FILE=${config.sops.secrets.android_keystore_password.path}
        nix develop -c scripts/release.sh
      '')
      (pkgs.writeShellScriptBin "construct-garmin-login" ''
        exec sudo -u ${cfg.user} env GARMIN_TOKEN_DIR=/var/lib/construct/garmin ${garminPython}/bin/python3 ${cfg.srcDir}/garmin/garmin_login.py
      '')
    ];
  };
}
