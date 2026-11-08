# construct (v2) — Daniel's life portal. Hono + node:sqlite API serving a Vite/React SPA.
# Replaces services.construct (the Next.js app) once it reaches parity; both run side by side until then.
# Iteration loop: edit → `construct-life-rebuild` → done.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.constructLife;
  home = config.users.users.${cfg.user}.home;
  node = pkgs.nodejs_24;
  garminPython = pkgs.python3.withPackages (p: [ p.garminconnect ]);

  baseUrl = "https://construct.matv.io";

  # One-time sign-in link for a device: open it in a browser or paste it into the Android app.
  linkScript = pkgs.writeShellScriptBin "construct-link" ''
    exec env CONSTRUCT_DB=/var/lib/construct/construct.db CONSTRUCT_BASE_URL=${baseUrl} \
      ${node}/bin/node ${cfg.srcDir}/dist/cli.js session-link "$@"
  '';

  # `construct routes|api|capture|openapi`: the portal's API for Claude Code and scripts. Runs in-process on the
  # production DB (no server, no session) with the service's sources. Seerr and Jellyfin (culture canon/recs, sync) read their
  # keys from the sops files, owner = the service user. Needs `construct-life-rebuild` once for dist/cli.js.
  cliScript = pkgs.writeShellScriptBin "construct" ''
    exec env \
      CONSTRUCT_DB=/var/lib/construct/construct.db \
      CONSTRUCT_LIFE=${cfg.lifeDir} \
      CONSTRUCT_BASE_URL=${baseUrl} \
      CONSTRUCT_AI_MODEL=claude-sonnet-5-5 \
      SEERR_URL=${cfg.seerrUrl} \
      SEERR_API_KEY_FILE=${config.sops.secrets.seerr_api_key.path} \
      ${lib.optionalString (cfg.jellyfinUrl != null) "JELLYFIN_URL=${cfg.jellyfinUrl} JELLYFIN_API_KEY_FILE=${config.sops.secrets.jellyfin_api_key.path} \\"}
      CAR_HUNT_DIR=${cfg.carHuntDir} \
      APARTMENT_HUNT_EXPORT=${cfg.apartmentExport} \
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
      default = "${home}/Projects/the_construct/app";
      defaultText = lib.literalExpression ''"''${home of cfg.user}/Projects/the_construct/app"'';
      description = "Source directory; `pnpm build` writes dist/ here.";
    };

    lifeDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/Projects/the_construct/life";
      defaultText = lib.literalExpression ''"''${home of cfg.user}/Projects/the_construct/life"'';
      description = "Documents (Markdown + front matter) the app reads and writes.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4322;
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "User the service runs as; paths default to this user's home.";
    };

    seerrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:5055";
      description = "Seerr base URL for culture (watchlist + TMDB lookups).";
    };

    jellyfinUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Jellyfin base URL for the culture watch history (API key: sops secret jellyfin_api_key); null turns it off.";
    };

    apartmentExport = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/construct/hunt/apartments.json";
      description = ''
        The apartment hunt engine's export (github.com/syntheit/hunt). The engine's host pushes it with
        `rsync apartments.json raven:/var/lib/construct/hunt/apartments.json` (atomic: rsync renames into place).
      '';
    };

    carHuntDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/construct/car-hunt";
      description = ''
        Where construct reads car-hunt's output: `app/static/deals.json` and `db/car.db` under this directory (car-hunt's own layout).
        Car-hunt lives on harbor; its scripts/refresh.sh pushes both files here with
        `rsync -R app/static/deals.json db/car.db raven:/var/lib/construct/car-hunt/`.
      '';
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
        HOME = home;
        CONSTRUCT_DB = "/var/lib/construct/construct.db";
        CONSTRUCT_LIFE = cfg.lifeDir;
        ANTHROPIC_KEY_FILE = config.sops.secrets.anthropic_key.path;
        CONSTRUCT_AI_MODEL = "claude-sonnet-5-5";
        ANTHROPIC_WORKSPACE_ID = "wrkspc_01LpEQYMaLkXFBGsrjGRwfYm";
        CONSTRUCT_OWNER_EMAIL = "daniel@matv.io"; # must match the Cloudflare Access login email
        CONSTRUCT_BASE_URL = baseUrl; # prefix for pairing links
        SEERR_URL = cfg.seerrUrl;
        SEERR_API_KEY_FILE = config.sops.secrets.seerr_api_key.path;
        CAR_HUNT_DIR = cfg.carHuntDir;
        APARTMENT_HUNT_EXPORT = cfg.apartmentExport;
        GARMIN_PYTHON = "${garminPython}/bin/python3";
        GARMIN_TOKEN_DIR = "/var/lib/construct/garmin";
        FDROID_DIR = "/var/lib/construct/fdroid"; # android/scripts/release.sh publishes here
        FDROID_PASSWORD_FILE = config.sops.secrets.fdroid_password.path;
        GARMIN_SYNC_SCRIPT = "${cfg.srcDir}/garmin/garmin_sync.py";
        TZ = "America/Argentina/Buenos_Aires";
      } // lib.optionalAttrs (cfg.jellyfinUrl != null) {
        JELLYFIN_URL = cfg.jellyfinUrl;
        JELLYFIN_API_KEY_FILE = config.sops.secrets.jellyfin_api_key.path;
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

    # Landing dirs for the hunt engine's and car-hunt's rsync pushes (the service user owns them; the files are world-readable).
    systemd.tmpfiles.rules = [
      "d ${builtins.dirOf cfg.apartmentExport} 0755 ${cfg.user} users -"
      "d ${cfg.carHuntDir} 0755 ${cfg.user} users -"
      "d ${cfg.carHuntDir}/app 0755 ${cfg.user} users -"
      "d ${cfg.carHuntDir}/app/static 0755 ${cfg.user} users -"
      "d ${cfg.carHuntDir}/db 0755 ${cfg.user} users -"
    ];

    # The Android release lives in construct-android.nix: it builds on x86_64 only.
    environment.systemPackages = [
      rebuildScript
      linkScript
      cliScript
      # One-time Garmin login (email, password, MFA), run by Daniel in a terminal.
      (pkgs.writeShellScriptBin "construct-garmin-login" ''
        exec sudo -u ${cfg.user} env GARMIN_TOKEN_DIR=/var/lib/construct/garmin ${garminPython}/bin/python3 ${cfg.srcDir}/garmin/garmin_login.py
      '')
    ];
  };
}
