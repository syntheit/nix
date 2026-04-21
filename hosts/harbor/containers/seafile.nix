{ config, ... }:

{
  virtualisation.oci-containers.containers = {
    # ===== SEAFILE (shared seafile_default network) =====
    seafile = {
      image = "seafileltd/seafile-mc:13.0-latest";
      environmentFiles = [ config.sops.templates."seafile.env".path ];
      environment = {
        SEAFILE_SERVER_HOSTNAME = "files.matv.io";
        SEAFILE_SERVER_PROTOCOL = "https";
        SEAFILE_MYSQL_DB_HOST = "seafile_db";
        SEAFILE_MYSQL_DB_USER = "seafile";
        SEAFILE_MYSQL_DB_CCNET_DB_NAME = "ccnet_db";
        SEAFILE_MYSQL_DB_SEAFILE_DB_NAME = "seafile_db";
        SEAFILE_MYSQL_DB_SEAHUB_DB_NAME = "seahub_db";
        TIME_ZONE = "America/New_York";
        CACHE_PROVIDER = "redis";
        REDIS_HOST = "seafile_redis";
        REDIS_PORT = "6379";
        ENABLE_SEADOC = "true";
        SEAFILE_LOG_TO_STDOUT = "true";
      };
      ports = [ "127.0.0.1:4717:80" ];
      volumes = [
        "/arespool/appdata/seafile/data:/shared"
      ];
      dependsOn = [ "seafile_db" "seafile_redis" ];
      extraOptions = [ "--network=seafile_default" ];
    };

    seafile_db = {
      image = "mariadb:10.11";
      environmentFiles = [ config.sops.templates."seafile-db.env".path ];
      environment = {
        MYSQL_LOG_CONSOLE = "true";
        MARIADB_AUTO_UPGRADE = "1";
      };
      volumes = [
        "/arespool/appdata/seafile/mysql:/var/lib/mysql"
      ];
      extraOptions = [ "--network=seafile_default" ];
    };

    seafile_redis = {
      image = "redis:latest";
      extraOptions = [
        "--network=seafile_default"
        "--network-alias=seafile_redis"
      ];
    };
  };

  # Network dependencies
  systemd.services.docker-seafile.after = [ "docker-networks.service" ];
  systemd.services.docker-seafile_db.after = [ "docker-networks.service" ];
  systemd.services.docker-seafile_redis.after = [ "docker-networks.service" ];
}
