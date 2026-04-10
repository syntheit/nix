{ config, ... }:

{
  virtualisation.oci-containers.containers = {
    # ===== RETROSPEND (shared retrospend_default network) =====
    retrospend = {
      image = "synzeit/retrospend:latest";
      environmentFiles = [ config.sops.templates."retrospend.env".path ];
      ports = [ "127.0.0.1:1997:1997" ];
      volumes = [
        "retrospend_uploads:/data/uploads"
      ];
      dependsOn = [ "retrospend_postgres" "retrospend_sidecar" ];
      extraOptions = [ "--network=retrospend_default" ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    retrospend_sidecar = {
      image = "synzeit/retrospend-sidecar:latest";
      environmentFiles = [ config.sops.templates."retrospend.env".path ];
      volumes = [
        "retrospend_sidecar_data:/app/data"
        "retrospend_backup_data:/backups"
      ];
      dependsOn = [ "retrospend_postgres" ];
      extraOptions = [
        "--network=retrospend_default"
        "--network-alias=sidecar"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    retrospend_postgres = {
      image = "postgres:16-alpine";
      environmentFiles = [ config.sops.templates."retrospend-postgres.env".path ];
      volumes = [
        "retrospend_postgres_data:/var/lib/postgresql/data"
      ];
      extraOptions = [
        "--network=retrospend_default"
        "--network-alias=postgres"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
    retrospend_ollama = {
      image = "ollama/ollama:latest";
      volumes = [
        "retrospend_ollama_data:/root/.ollama"
      ];
      extraOptions = [
        "--network=retrospend_default"
        "--network-alias=ollama"
        "--device=nvidia.com/gpu=all"
        "--dns=1.1.1.1"
        "--dns=1.0.0.1"
      ];
      labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
    };
  };

  # Network + NVIDIA dependencies
  systemd.services.docker-retrospend.after = [ "docker-networks.service" ];
  systemd.services.docker-retrospend_sidecar.after = [ "docker-networks.service" ];
  systemd.services.docker-retrospend_postgres.after = [ "docker-networks.service" ];
  systemd.services.docker-retrospend_ollama.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-retrospend_ollama.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
}
