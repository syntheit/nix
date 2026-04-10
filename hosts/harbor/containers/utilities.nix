{ config, ... }:

{
  virtualisation.oci-containers.containers = {
    # ===== BITWARDEN (shared bitwarden_default network) =====
    bitwarden = {
      image = "ghcr.io/bitwarden/self-host:beta";
      environmentFiles = [ config.sops.templates."bitwarden.env".path ];
      ports = [ "127.0.0.1:29446:8080" ];
      volumes = [
        "/arespool/appdata/bitwarden/bitwarden:/etc/bitwarden"
        "/arespool/appdata/bitwarden/logs:/var/log/bitwarden"
      ];
      dependsOn = [ "bitwarden_db" ];
      extraOptions = [ "--network=bitwarden_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    bitwarden_db = {
      image = "mariadb:10";
      environmentFiles = [ config.sops.templates."bitwarden-db.env".path ];
      volumes = [
        "/arespool/appdata/bitwarden_db/data:/var/lib/mysql"
      ];
      extraOptions = [ "--network=bitwarden_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    linkding = {
      image = "sissbruecker/linkding:latest-plus";
      environmentFiles = [ config.sops.templates."linkding.env".path ];
      ports = [ "127.0.0.1:28793:9090" ];
      volumes = [
        "/arespool/appdata/linkding:/etc/linkding/data"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
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
    syncthing = {
      image = "lscr.io/linuxserver/syncthing:latest";
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/New_York";
      };
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
  };

  # Network dependencies
  systemd.services.docker-bitwarden.after = [ "docker-networks.service" ];
  systemd.services.docker-bitwarden_db.after = [ "docker-networks.service" ];
}
