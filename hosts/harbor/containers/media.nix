{ config, lib, pkgs, ... }:

let
  linuxserverEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ = "America/New_York";
  };
in
{
  # Seerr — media request management (native NixOS service, no Docker)
  services.seerr.enable = true;

  # Restart Seerr daily at 5am to curb Node.js memory creep
  systemd.timers.seerr-restart = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
    };
  };
  systemd.services.seerr-restart = {
    description = "Restart Seerr to reclaim memory";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl restart seerr.service";
    };
  };

  virtualisation.oci-containers.containers = {
    # Nextcloud disabled — pending full removal (data/secrets/network kept for now)
    # nextcloud = {
    #   image = "lscr.io/linuxserver/nextcloud:latest";
    #   environment = linuxserverEnv;
    #   ports = [ "127.0.0.1:9787:443" ];
    #   volumes = [
    #     "/arespool/appdata/nextcloud_config:/config"
    #     "/arespool/nextcloud/data:/arespool/nextcloud/data"
    #     "/iotapool:/iotapool"
    #     "/lambdapool:/lambdapool"
    #     "/deltapool:/deltapool"
    #     "/thetapool:/thetapool"
    #     "/epsilpool:/epsilpool"
    #     "/rhopool:/rhopool"
    #   ];
    #   dependsOn = [ "nextcloud_db" ];
    #   extraOptions = [ "--network=nextcloud_default" ];
    # };
    # nextcloud_db = {
    #   image = "linuxserver/mariadb:latest";
    #   environmentFiles = [ config.sops.templates."nextcloud-db.env".path ];
    #   volumes = [
    #     "/arespool/appdata/nextcloud-mariadb:/config"
    #   ];
    #   extraOptions = [ "--network=nextcloud_default" ];
    # };
    jellyfin = {
      image = "lscr.io/linuxserver/jellyfin:latest";
      environment = linuxserverEnv // {
        JELLYFIN_PublishedServerUrl = "watch.matv.io";
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "all";
      };
      ports = [
        "8096:8096" # Accessible via WireGuard (wg0 is trusted)
        "8920:8920"
      ];
      volumes = [
        "/arespool/appdata/jellyfin_config:/config"
        "/media:/media"
      ];
      extraOptions = [
        "--device=nvidia.com/gpu=all"
        "-v" "${pkgs.writeShellScript "jelly-recs-inject" ''
          #!/bin/bash
          # Patches Jellyfin's index.html to load our recs.js + recs.css from
          # /static/recs.{js,css} (proxied through Caddy to jelly-recs serve).
          # Idempotent: safe to re-run on every container start.
          INDEX="/usr/share/jellyfin/web/index.html"
          [ -f "$INDEX" ] || { echo "[jelly-recs] $INDEX not found"; exit 0; }
          if grep -q "static/recs.js" "$INDEX"; then
            echo "[jelly-recs] index.html already patched"
            exit 0
          fi
          [ ! -f "$INDEX.bak" ] && cp "$INDEX" "$INDEX.bak"
          # Insert before </body>. Stylesheet first so first paint isn't unstyled.
          sed -i 's|</body>|<link rel="stylesheet" href="/static/recs.css"><script src="/static/recs.js" defer></script></body>|' "$INDEX"
          echo "[jelly-recs] index.html patched"
        ''}:/custom-cont-init.d/jelly-recs-inject"
        "-v" "${pkgs.writeShellScript "abyss-spotlight" ''
          #!/bin/bash
          echo "[abyss] Installing Spotlight..."
          WEBDIR="/usr/share/jellyfin/web"
          if [ ! -d "$WEBDIR" ]; then
            echo "[abyss] $WEBDIR not found"
            exit 0
          fi
          mkdir -p "$WEBDIR/ui"

          # Download to a temp file and only install if it looks valid. GitHub
          # rate-limits raw.githubusercontent.com (HTTP 429); curl -sL happily
          # writes that error page to disk, which previously corrupted the
          # home-page chunk into a 199-byte "429: Too Many Requests" blob and
          # broke Jellyfin's UI on every restart. --fail makes curl exit non-zero
          # on 4xx/5xx so we never overwrite good files with an error body.
          fetch() {
            # fetch <url> <dest> [min_bytes]
            local url="$1" dest="$2" min="''${3:-1}" tmp
            tmp="$(mktemp)"
            if curl -sfL "$url" -o "$tmp" && [ "$(wc -c < "$tmp")" -ge "$min" ]; then
              # mktemp creates mode 0600; Jellyfin serves these as the 'abc'
              # user (PUID 1000) and would 500 on an unreadable file. Force
              # world-readable before publishing into the web root.
              chmod 644 "$tmp"
              mv "$tmp" "$dest"
              return 0
            fi
            echo "[abyss] fetch failed (or too small), keeping existing: $url"
            rm -f "$tmp"
            return 1
          }

          # Upstream (AumGupta/abyss-jellyfin) moved Spotlight install for
          # Jellyfin 12 to a loader-script + tag-injection method, replacing
          # the old "patch the home-html chunk.js in place" approach below.
          # All three assets are tens of KB, so a 1000-byte floor is plenty
          # to reject a GitHub error page while never rejecting a real file.
          fetch "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/spotlight.html" "$WEBDIR/ui/spotlight.html" 1000 || true
          fetch "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/spotlight.css" "$WEBDIR/ui/spotlight.css" 1000 || true
          fetch "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/spotlight-loader.js" "$WEBDIR/ui/spotlight-loader.js" 1000 || true

          # Undo the legacy chunk-patch method if a prior run applied it:
          # restore the pristine home-html chunk from its .bak. The pristine
          # chunk is ~543 bytes; the legacy-patched one is ~3727 bytes and
          # matches on "spotlight" (or the older "featurediframe" /
          # "abyss-spotlight-frame" markers). Only trust a .bak that looks
          # like a real pristine chunk, not a corrupted/truncated one.
          for CHUNK in "$WEBDIR"/home-html.*.chunk.js; do
            [ -f "$CHUNK" ] || continue
            if [ -f "$CHUNK.bak" ] && [ "$(wc -c < "$CHUNK.bak")" -ge 400 ] \
                && grep -Eq "featurediframe|abyss-spotlight-frame|spotlight" "$CHUNK"; then
              cp "$CHUNK.bak" "$CHUNK"
              rm -f "$CHUNK.bak"
              echo "[abyss] restored legacy-patched home chunk from backup: $CHUNK"
            fi
          done

          # Inject the loader <script> tag before </body>, only once we know
          # the loader script actually landed, and only if not already
          # present. Another init script (jelly-recs-inject) also
          # sed-patches index.html before </body>, so edit in place rather
          # than rewriting the whole file from a template.
          INDEX="$WEBDIR/index.html"
          LOADER_TAG='<script src="ui/spotlight-loader.js" data-abyss-spotlight></script>'
          if [ -f "$WEBDIR/ui/spotlight-loader.js" ] && [ -f "$INDEX" ]; then
            grep -qF 'ui/spotlight-loader.js' "$INDEX" || sed -i "s|</body>|$LOADER_TAG</body>|" "$INDEX"
            echo "[abyss] spotlight loader tag present in index.html"
          fi

          echo "[abyss] Spotlight installed"
        ''}:/custom-cont-init.d/abyss-spotlight"
      ];
    };
    # ===== DOWNLOADING STACK (shared downloader_media_network) =====
    qbittorrent = {
      image = "trigus42/qbittorrentvpn";
      environmentFiles = [ config.sops.templates."qbittorrent.env".path ];
      ports = [ "127.0.0.1:9091:8080" ];
      volumes = [
        "/arespool/appdata/qbittorrent:/config"
        # Legacy save_path compatibility: existing torrents reference
        # /downloads as their save path. Mapping that to the rhopool branch
        # keeps every torrent's stored path resolvable on resume.
        "/rhopool/media/downloads:/downloads"
        "/media:/media"
      ];
      extraOptions = [
        "--network=downloader_media_network"
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun"
        "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
        "--sysctl=net.ipv6.conf.all.disable_ipv6=0"
      ];

    };
    # Seerr runs as a native NixOS service (see services.seerr above)
    prowlarr = {
      image = "linuxserver/prowlarr:latest";
      environment = linuxserverEnv;
      ports = [ "127.0.0.1:9696:9696" ];
      volumes = [
        "/arespool/appdata/prowlarr:/config"
      ];
      dependsOn = [ "qbittorrent" ];
      extraOptions = [ "--network=downloader_media_network" ];

    };
    sonarr = {
      image = "linuxserver/sonarr";
      environment = linuxserverEnv;
      ports = [ "127.0.0.1:8989:8989" ];
      volumes = [
        "/arespool/appdata/sonarr:/config"
        # Same /downloads mapping as qbittorrent — *arr's import sees the
        # exact path qbit reports, so atomic moves work without remote-path
        # mappings.
        "/rhopool/media/downloads:/downloads"
        "/media:/media"
      ];
      extraOptions = [ "--network=downloader_media_network" ];

    };
    radarr = {
      image = "linuxserver/radarr";
      environment = linuxserverEnv;
      ports = [ "127.0.0.1:7878:7878" ];
      volumes = [
        "/arespool/appdata/radarr:/config"
        "/rhopool/media/downloads:/downloads"
        "/media:/media"
      ];
      extraOptions = [ "--network=downloader_media_network" ];

    };
    bazarr = {
      image = "linuxserver/bazarr";
      environment = linuxserverEnv;
      ports = [ "127.0.0.1:6767:6767" ];
      volumes = [
        "/arespool/appdata/bazarr:/config"
        "/media:/media"
      ];
      extraOptions = [ "--network=downloader_media_network" ];

    };

    # FlareSolverr — proxy that solves Cloudflare challenges on behalf of
    # Prowlarr. Required for TheRARBG, ilCorSaRoNeRo, Toloka, and any other
    # indexer behind CF. Stateless; no volumes needed.
    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      environment = {
        TZ = "America/New_York";
        LOG_LEVEL = "info";
      };
      ports = [ "127.0.0.1:8191:8191" ];
      extraOptions = [ "--network=downloader_media_network" ];
    };
    memos = {
      image = "neosmemo/memos:stable";
      user = "1000:1000";
      ports = [ "127.0.0.1:5230:5230" ];
      volumes = [
        "/arespool/appdata/memos:/var/opt/memos"
      ];

    };
  };

  # Network + NVIDIA dependencies
  systemd.services.docker-qbittorrent.after = [ "docker-networks.service" ];
  systemd.services.docker-sonarr.after = [ "docker-networks.service" ];
  systemd.services.docker-radarr.after = [ "docker-networks.service" ];
  systemd.services.docker-bazarr.after = [ "docker-networks.service" ];
  systemd.services.docker-prowlarr.after = [ "docker-networks.service" ];
  systemd.services.docker-flaresolverr.after = [ "docker-networks.service" ];
  systemd.services.docker-jellyfin.after = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-jellyfin.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];

  # Wait for the mergerfs union mount before starting any media-touching
  # container. Without this, on boot the container can race the mount and
  # bind-mount an empty /media; everything silently breaks until restart.
  systemd.services.docker-jellyfin.unitConfig.RequiresMountsFor    = [ "/media" ];
  systemd.services.docker-qbittorrent.unitConfig.RequiresMountsFor = [ "/media" "/rhopool/media/downloads" ];

  # qbittorrentvpn's s6 supervisor exits with status 0 when its in-container
  # VPN healthcheck fails (e.g. transient WG handshake delay at boot). The
  # default Restart=on-failure does NOT retry clean exits, so a single hiccup
  # took the whole download stack offline for 13h on 2026-05-04. Force always-
  # restart with a 30s backoff so the *arr grab pipeline self-heals.
  systemd.services.docker-qbittorrent.serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = 30;
  };
  systemd.services.docker-sonarr.unitConfig.RequiresMountsFor      = [ "/media" "/rhopool/media/downloads" ];
  systemd.services.docker-radarr.unitConfig.RequiresMountsFor      = [ "/media" "/rhopool/media/downloads" ];
  systemd.services.docker-bazarr.unitConfig.RequiresMountsFor      = [ "/media" ];
}
