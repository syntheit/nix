{ config, pkgs, ... }:

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
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [
        "--device=nvidia.com/gpu=all"
        "-v" "${pkgs.writeShellScript "abyss-spotlight" ''
          #!/bin/bash
          echo "[abyss] Installing Spotlight..."
          WEBDIR="/usr/share/jellyfin/web"
          if [ ! -d "$WEBDIR" ]; then
            echo "[abyss] $WEBDIR not found"
            exit 0
          fi
          mkdir -p "$WEBDIR/ui"
          curl -sL "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/spotlight.html" -o "$WEBDIR/ui/spotlight.html"
          curl -sL "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/spotlight.css" -o "$WEBDIR/ui/spotlight.css"
          CHUNK=$(find "$WEBDIR" -name "home-html.*.chunk.js" ! -name "*.bak" | head -1)
          if [ -n "$CHUNK" ]; then
            # Restore from backup if chunk is corrupted or already patched incorrectly
            if [ -f "$CHUNK.bak" ] && [ "$(wc -c < "$CHUNK")" -lt 1000 ]; then
              cp "$CHUNK.bak" "$CHUNK"
            fi
            # Patch if not already patched
            if ! grep -q "spotlight" "$CHUNK" 2>/dev/null; then
              [ ! -f "$CHUNK.bak" ] && cp "$CHUNK" "$CHUNK.bak"
              curl -sL "https://raw.githubusercontent.com/AumGupta/abyss-jellyfin/main/scripts/spotlight/home-html.chunk.js" -o "$CHUNK"
            fi
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
        "/rhopool/Downloads:/downloads"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
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
        "/rhopool/Downloads:/downloads"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [ "--network=downloader_media_network" ];

    };
    radarr = {
      image = "linuxserver/radarr";
      environment = linuxserverEnv;
      ports = [ "127.0.0.1:7878:7878" ];
      volumes = [
        "/arespool/appdata/radarr:/config"
        "/rhopool/Downloads:/downloads"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
      extraOptions = [ "--network=downloader_media_network" ];

    };
    bazarr = {
      image = "linuxserver/bazarr";
      environment = linuxserverEnv;
      ports = [ "127.0.0.1:6767:6767" ];
      volumes = [
        "/arespool/appdata/bazarr:/config"
        "/iotapool:/iotapool"
        "/lambdapool:/lambdapool"
        "/deltapool:/deltapool"
        "/thetapool:/thetapool"
        "/epsilpool:/epsilpool"
        "/rhopool:/rhopool"
        "/platapool:/platapool"
      ];
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
  systemd.services.docker-jellyfin.after = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-jellyfin.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
}
