{ pkgs, ... }:

{
  imports = [
    ./media.nix
    ./immich.nix
    ./retrospend.nix
    ./utilities.nix
  ];

  # Docker (start at boot — this is a server)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    liveRestore = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
    daemon.settings = {
      default-ulimits = {
        nofile = {
          Name = "nofile";
          Hard = 65536;
          Soft = 65536;
        };
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
        ${pkgs.docker}/bin/docker network create bitwarden_default || true
        ${pkgs.docker}/bin/docker network create retrospend_default || true
        ${pkgs.docker}/bin/docker network create immich_default || true
      '';
    };
  };

  virtualisation.oci-containers.backend = "docker";

  # Watchtower — auto-update labeled containers
  virtualisation.oci-containers.containers.watchtower = {
    image = "containrrr/watchtower:1.7.1";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
    ];
    cmd = [ "--label-enable" "--cleanup" "--interval" "3600" ];
    labels = { "com.centurylinklabs.watchtower.enable" = "true"; };
  };
}
