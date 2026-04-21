{ pkgs, ... }:

{
  imports = [
    ./media.nix
    ./immich.nix
    ./retrospend.nix
    ./utilities.nix
    ./gaming.nix
    ./registry.nix
    ./seafile.nix
  ];

  # Docker (start at boot — this is a server)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    liveRestore = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ ];
    };
    daemon.settings = {
      default-ulimits = {
        nofile = {
          Name = "nofile";
          Hard = 65536;
          Soft = 65536;
        };
      };
      log-driver = "json-file";
      log-opts = {
        max-size = "50m";
        max-file = "3";
      };
    };
  };

  # Create Docker networks for multi-container stacks
  systemd.services.docker-networks = {
    description = "Create Docker networks for multi-container stacks";
    after = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "create-docker-networks" ''
        ${pkgs.docker}/bin/docker network create nextcloud_default || true
        ${pkgs.docker}/bin/docker network create downloader_media_network || true
        ${pkgs.docker}/bin/docker network create retrospend_default || true
        ${pkgs.docker}/bin/docker network create immich_default || true
        ${pkgs.docker}/bin/docker network create karakeep_default || true
        ${pkgs.docker}/bin/docker network create docmost_default || true
        ${pkgs.docker}/bin/docker network create pelican_default || true
        ${pkgs.docker}/bin/docker network create seafile_default || true
      '';
    };
  };

  virtualisation.oci-containers.backend = "docker";

  # Shared Ollama — GPU-accelerated LLM inference for Retrospend + Karakeep
  virtualisation.oci-containers.containers.ollama = {
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
  };

  systemd.services.docker-ollama.after = [ "docker-networks.service" "nvidia-container-toolkit-cdi-generator.service" ];
  systemd.services.docker-ollama.wants = [ "nvidia-container-toolkit-cdi-generator.service" ];

  # Connect shared Ollama to Karakeep's network so both stacks can reach it
  systemd.services.docker-ollama-karakeep-connect = {
    description = "Connect shared Ollama to Karakeep network";
    after = [ "docker-ollama.service" "docker-networks.service" ];
    partOf = [ "docker-ollama.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "connect-ollama-karakeep" ''
        until ${pkgs.docker}/bin/docker inspect ollama >/dev/null 2>&1; do sleep 1; done
        ${pkgs.docker}/bin/docker network connect --alias ollama karakeep_default ollama 2>/dev/null || true
      '';
    };
  };
}
