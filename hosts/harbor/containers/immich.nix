{ config, ... }:

{
  virtualisation.oci-containers.containers = {
    # ===== IMMICH + VPN (shared immich_default network) =====
    vpn = {
      image = "qmcgaw/gluetun";
      environmentFiles = [ config.sops.templates."vpn.env".path ];
      environment = {
        HEALTH_RESTART_VPN = "on"; # Auto-restart VPN if health check fails
        HEALTH_TARGET_ADDRESSES = "cloudflare.com:443,github.com:443";
        HEALTH_SMALL_CHECK_TYPE = "icmp";
      };
      ports = [
        "12283:2283"
        "15096:5096"
      ];
      volumes = [
        "/arespool/appdata/vpn/ovpn/windscribe.ovpn:/gluetun/custom.conf:ro"
      ];
      extraOptions = [
        "--network=immich_default"
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun"
        "--health-cmd" "wget -q -O /dev/null https://cloudflare.com || exit 1"
        "--health-interval" "30s"
        "--health-timeout" "10s"
        "--health-retries" "3"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    immich_server = {
      image = "ghcr.io/immich-app/immich-server:release";
      environmentFiles = [ config.sops.templates."immich.env".path ];
      environment = {
        NVIDIA_DRIVER_CAPABILITIES = "all";
        NVIDIA_VISIBLE_DEVICES = "all";
      };
      ports = [ "127.0.0.1:2283:2283" ];
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
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    immich_redis = {
      image = "valkey/valkey:9";
      extraOptions = [
        "--network=immich_default"
        "--network-alias=redis"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    edge = {
      image = "caddy:2-alpine";
      dependsOn = [ "vpn" ];
      volumes = [
        "/arespool/appdata/vpn/caddy/config:/etc/caddy"
        "/arespool/appdata/vpn/caddy/data:/data"
        "/arespool/appdata/vpn/certs/photos.matv.io:/certs:ro"
      ];
      extraOptions = [ "--network=container:vpn" "--entrypoint" "/bin/sh" ];
      cmd = [ "-lc" "echo 'Waiting for Immich...'; until nc -z immich_server 2283; do sleep 1; done; exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
  };

  # Network + NVIDIA dependencies
  systemd.services.docker-vpn.after = [ "docker-networks.service" ];
  systemd.services.docker-edge.after = [ "docker-vpn.service" ];
  systemd.services.docker-immich_server.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_server.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_machine_learning.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_machine_learning.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-immich_postgres.after = [ "docker-networks.service" ];
  systemd.services.docker-immich_redis.after = [ "docker-networks.service" ];
}
