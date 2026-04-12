{ config, ... }:

{
  # Game server data on NVMe (arespool)
  # Symlink ensures Wings' paths match between container and host,
  # since Wings creates game containers on the host Docker daemon
  systemd.tmpfiles.rules = [
    "d /arespool/appdata/pelican 0755 root root -"
    "d /arespool/appdata/pelican/wings-data 0755 root root -"
    "d /arespool/appdata/pelican/wings-config 0755 root root -"
    "d /arespool/appdata/pelican/panel-data 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/storage 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/storage/logs 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/storage/logs/supervisord 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/storage/app/public 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/storage/framework/cache 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/storage/framework/sessions 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/storage/framework/views 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/database 0755 82 82 -"
    "d /arespool/appdata/pelican/panel-data/plugins 0755 82 82 -"
    "d /arespool/appdata/pelican/mariadb 0755 root root -"
    "d /var/log/pelican 0755 root root -"
    "d /tmp/pelican 0755 root root -"
    "L+ /var/lib/pelican - - - - /arespool/appdata/pelican/wings-data"
  ];

  virtualisation.oci-containers.containers = {
    # ===== PELICAN GAME SERVER MANAGEMENT (pelican_default network) =====

    # Panel — web UI for managing game servers
    pelican_panel = {
      image = "ghcr.io/pelican-dev/panel:latest";
      environment = {
        APP_URL = "https://games.matv.io";
        APP_ENV = "production";
        APP_DEBUG = "false";
        BEHIND_PROXY = "true";
        TRUSTED_PROXIES = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.1";
        DB_CONNECTION = "mariadb";
        DB_HOST = "pelican_db";
        DB_PORT = "3306";
        DB_DATABASE = "pelican";
        DB_USERNAME = "pelican";
        CACHE_STORE = "redis";
        SESSION_DRIVER = "redis";
        QUEUE_CONNECTION = "redis";
        REDIS_HOST = "pelican_cache";
        XDG_DATA_HOME = "/pelican-data";
      };
      environmentFiles = [ config.sops.templates."pelican-panel.env".path ];
      ports = [ "2080:80" ]; # Accessible via WireGuard (wg0 is trusted)
      volumes = [
        "/arespool/appdata/pelican/panel-data:/pelican-data"
      ];
      dependsOn = [ "pelican_db" "pelican_cache" ];
      extraOptions = [
        "--network=pelican_default"
        "--add-host=host.docker.internal:host-gateway"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };

    # MariaDB — database for Panel
    pelican_db = {
      image = "mariadb:10.11";
      environment = {
        MYSQL_DATABASE = "pelican";
        MYSQL_USER = "pelican";
      };
      environmentFiles = [ config.sops.templates."pelican-db.env".path ];
      volumes = [
        "/arespool/appdata/pelican/mariadb:/var/lib/mysql"
      ];
      extraOptions = [
        "--network=pelican_default"
        "--network-alias=pelican_db"
      ];
    };

    # Redis — cache/session/queue for Panel
    pelican_cache = {
      image = "redis:alpine";
      extraOptions = [
        "--network=pelican_default"
        "--network-alias=pelican_cache"
      ];
    };

    # Wings — game server daemon (creates Docker containers for each game server)
    pelican_wings = {
      image = "ghcr.io/pelican-dev/wings:latest";
      environment = {
        TZ = "America/New_York";
        WINGS_UID = "988";
        WINGS_GID = "988";
        WINGS_USERNAME = "pelican";
      };
      ports = [
        "8080:8080" # Wings API + WebSocket (proxied via Caddy on conduit)
        "2022:2022" # SFTP for game server file access
      ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "/var/lib/docker/containers/:/var/lib/docker/containers/"
        "/arespool/appdata/pelican/wings-config:/etc/pelican"
        "/var/lib/pelican:/var/lib/pelican"
        "/var/log/pelican:/var/log/pelican"
        "/tmp/pelican:/tmp/pelican"
        "/etc/ssl/certs:/etc/ssl/certs:ro"
      ];
      extraOptions = [
        "--tty"
        "--network=pelican_default"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
  };

  # Network dependencies
  systemd.services.docker-pelican_panel.after = [ "docker-networks.service" ];
  systemd.services.docker-pelican_db.after = [ "docker-networks.service" ];
  systemd.services.docker-pelican_cache.after = [ "docker-networks.service" ];
  systemd.services.docker-pelican_wings.after = [ "docker-networks.service" ];
}
