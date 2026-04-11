{ config, ... }:

let
  linuxserverEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ = "America/New_York";
  };
in
{
  virtualisation.oci-containers.containers = {
    # ===== VAULTWARDEN (standalone, SQLite) =====
    vaultwarden = {
      image = "vaultwarden/server:latest";
      environmentFiles = [ config.sops.templates."vaultwarden.env".path ];
      ports = [ "127.0.0.1:29446:80" ];
      volumes = [
        "/arespool/appdata/vaultwarden:/data"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };

    # ===== LINKDING =====
    linkding = {
      image = "sissbruecker/linkding:latest-plus";
      environmentFiles = [ config.sops.templates."linkding.env".path ];
      ports = [ "127.0.0.1:28793:9090" ];
      volumes = [
        "/arespool/appdata/linkding:/etc/linkding/data"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };

    # ===== SCRUTINY (drive health monitoring) =====
    scrutiny = {
      image = "ghcr.io/analogj/scrutiny:master-omnibus";
      ports = [
        "127.0.0.1:5153:8080"
        "127.0.0.1:39419:8086"
      ];
      volumes = [
        "/run/udev:/run/udev:ro"
        "/arespool/appdata/srcutiny/config:/opt/scrutiny/config"
        "/arespool/appdata/srcutiny/influxdb:/opt/scrutiny/influxdb"
      ];
      extraOptions = [
        "--cap-add=SYS_RAWIO"
        "--cap-add=SYS_ADMIN"
        "--device=/dev/nvme0"
        "--device=/dev/nvme1"
        "--device=/dev/nvme2"
        "--device=/dev/sda"
        "--device=/dev/sdb"
        "--device=/dev/sdc"
        "--device=/dev/sdd"
        "--device=/dev/sde"
        "--device=/dev/sdf"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };

    # ===== SYNCTHING =====
    syncthing = {
      image = "lscr.io/linuxserver/syncthing:latest";
      environment = linuxserverEnv;
      ports = [
        "127.0.0.1:8384:8384"
        "22000:22000/tcp"
        "22000:22000/udp"
        "21027:21027/udp"
      ];
      volumes = [
        "/arespool/appdata/syncthing/config:/config"
        "/arespool/nextcloud/data/topikzero/files/Sync:/config/Sync"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };

    # ===== TRACEARR =====
    tracearr = {
      image = "ghcr.io/connorgallopo/tracearr:supervised";
      ports = [ "127.0.0.1:7898:3000" ];
      environment = {
        TZ = "America/New_York";
        LOG_LEVEL = "info";
      };
      volumes = [
        "tracearr_tracearr_postgres:/data/postgres"
        "tracearr_tracearr_redis:/data/redis"
        "tracearr_tracearr_data:/data/tracearr"
      ];
      extraOptions = [
        "--shm-size=256m"
        "--memory=2g"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };

    # ===== KARAKEEP (shared karakeep_default network) =====
    karakeep = {
      image = "ghcr.io/karakeep-app/karakeep:release";
      environmentFiles = [ config.sops.templates."karakeep.env".path ];
      ports = [ "127.0.0.1:3030:3000" ];
      volumes = [
        "/arespool/appdata/karakeep:/data"
      ];
      dependsOn = [ "karakeep_meilisearch" "karakeep_chrome" ];
      extraOptions = [ "--network=karakeep_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    karakeep_meilisearch = {
      image = "getmeili/meilisearch:v1.11";
      environmentFiles = [ config.sops.templates."karakeep-meilisearch.env".path ];
      volumes = [
        "karakeep_meilisearch_data:/meili_data"
      ];
      extraOptions = [ "--network=karakeep_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    karakeep_chrome = {
      image = "gcr.io/zenika-hub/alpine-chrome:latest";
      environment = {
        CHROME_FLAGS = "--disable-gpu --no-sandbox --disable-dev-shm-usage --remote-debugging-address=0.0.0.0 --remote-debugging-port=9222";
      };
      cmd = [ "chromium-browser" "--headless" "--disable-gpu" "--no-sandbox" "--disable-dev-shm-usage" "--remote-debugging-address=0.0.0.0" "--remote-debugging-port=9222" ];
      extraOptions = [ "--network=karakeep_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };

    # ===== DOCMOST (shared docmost_default network) =====
    docmost = {
      image = "docmost/docmost:latest";
      environmentFiles = [ config.sops.templates."docmost.env".path ];
      ports = [ "127.0.0.1:3040:3000" ];
      volumes = [
        "/arespool/appdata/docmost/storage:/app/data/storage"
      ];
      dependsOn = [ "docmost_postgres" "docmost_redis" ];
      extraOptions = [ "--network=docmost_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    docmost_postgres = {
      image = "postgres:16-alpine";
      environmentFiles = [ config.sops.templates."docmost-postgres.env".path ];
      volumes = [
        "/arespool/appdata/docmost/postgres:/var/lib/postgresql/data"
      ];
      extraOptions = [ "--network=docmost_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    docmost_redis = {
      image = "redis:7-alpine";
      cmd = [ "redis-server" "--appendonly" "yes" ];
      volumes = [
        "docmost_redis_data:/data"
      ];
      extraOptions = [ "--network=docmost_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
  };

  # Network dependencies
  systemd.services.docker-karakeep.after = [ "docker-networks.service" ];
  systemd.services.docker-karakeep_meilisearch.after = [ "docker-networks.service" ];
  systemd.services.docker-karakeep_chrome.after = [ "docker-networks.service" ];
  systemd.services.docker-docmost.after = [ "docker-networks.service" ];
  systemd.services.docker-docmost_postgres.after = [ "docker-networks.service" ];
  systemd.services.docker-docmost_redis.after = [ "docker-networks.service" ];
}
