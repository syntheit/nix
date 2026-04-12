{ config, ... }:

{
  virtualisation.oci-containers.containers = {
    # ===== IMMICH (shared immich_default network) =====
    immich_server = {
      image = "ghcr.io/immich-app/immich-server:release";
      environmentFiles = [ config.sops.templates."immich.env".path ];
      environment = {
        NVIDIA_DRIVER_CAPABILITIES = "all";
        NVIDIA_VISIBLE_DEVICES = "all";
      };
      ports = [ "2283:2283" ]; # Accessible via WireGuard (wg0 is trusted)
      volumes = [
        "/arespool/nextcloud/data/topikzero/files/ImmichUpload:/usr/src/app/upload"
        "/arespool/nextcloud/data/topikzero/files/Photos/Google Photos:/mnt/media/Google Photos:ro"
        "/arespool/nextcloud/data/topikzero/files/Photos/InstantUpload:/mnt/media/InstantUpload:ro"
        "/arespool/photos-videos:/mnt/media/photos-videos:ro"
        "/etc/localtime:/etc/localtime:ro"
      ];
      dependsOn = [ "immich_postgres" "immich_redis" ];
      extraOptions = [
        "--network=immich_default"
        "--device=nvidia.com/gpu=all"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    immich_machine_learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:release-cuda";
      environmentFiles = [ config.sops.templates."immich.env".path ];
      volumes = [
        "/arespool/appdata/immich/model-cache:/cache"
      ];
      dependsOn = [ "immich_postgres" ];
      extraOptions = [
        "--network=immich_default"
        "--network-alias=immich-machine-learning"
        "--device=nvidia.com/gpu=all"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    immich_postgres = {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
      environmentFiles = [ config.sops.templates."immich-postgres.env".path ];
      volumes = [
        "/arespool/appdata/immich/postgres/pgdata:/var/lib/postgresql/data"
      ];
      cmd = [
        "postgres"
        "-c" "shared_preload_libraries=vchord.so"
        "-c" "shared_buffers=4GB"
        "-c" "effective_cache_size=48GB"
        "-c" "work_mem=128MB"
        "-c" "maintenance_work_mem=2GB"
        "-c" "wal_buffers=64MB"
        "-c" "random_page_cost=1.1"
        "-c" "effective_io_concurrency=200"
        "-c" "max_connections=200"
      ];
      extraOptions = [
        "--network=immich_default"
        "--network-alias=database"
        "--shm-size=512m"
      ];
    };
    immich_redis = {
      image = "valkey/valkey:9";
      extraOptions = [
        "--network=immich_default"
        "--network-alias=redis"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
  };

  # Network + NVIDIA dependencies
  systemd.services.docker-immich_server.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_server.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_machine_learning.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_machine_learning.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_postgres.after = [ "docker-networks.service" ];
  systemd.services.docker-immich_redis.after = [ "docker-networks.service" ];
}
