{
  pkgs,
  vars,
  inputs,
  ...
}:
{
  imports = [
    inputs.nixos-avf.nixosModules.avf
  ];

  networking.hostName = "raven";
  system.stateVersion = "26.05";

  # Headless server — no graphics/Weston
  avf.defaultUser = "droid";
  avf.enableGraphics = false;

  # SSH — key-only auth
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  users.users."droid".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
  ];

  # Docker (start at boot — this is a server)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers = {
    website = {
      image = "synzeit/website:arm64";
      ports = [ "3000:3000" ];
      environment = {
        NODE_ENV = "production";
      };
    };
  };

  # Nix
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      auto-optimise-store = true;
      max-jobs = "auto";
      cores = 0;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Cloudflared tunnel for remote SSH
  services.cloudflared = {
    enable = true;
    tunnels = {
      "raven" = {
        ingress = {
          "matv.io" = "http://localhost:3000";
          "raven.matv.io" = "ssh://localhost:22";
        };
        default = "http_status:404";
        credentialsFile = "/etc/cloudflared/credentials.json";
      };
    };
  };

  # Packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    mosh
    cloudflared
  ];

  # Shell
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # User — avf module creates droid, we just add docker group
  users.users."droid".extraGroups = [ "docker" ];
  users.users."droid".shell = pkgs.zsh;

  # Firewall
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # Security
  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults lecture = never
    '';
  };
}
