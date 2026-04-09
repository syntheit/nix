{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ./hardware-configuration.nix ];

  # Boot configuration
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [ "zfs" ];
    blacklistedKernelModules = [ "nouveau" ];
    kernelParams = [ "i915.enable_guc=2" ];
    zfs = {
      forceImportRoot = false;
      extraPools = [
        "arespool"
        "lambdapool"
        "iotapool"
        "thetapool"
        "deltapool"
        "epsilpool"
        "rhopool"
        "platapool"
      ];
    };
  };

  # Networking configuration
  networking = {
    hostId = "fdbe6a1e";
    hostName = "harbor";
    networkmanager.enable = true;
    nftables.enable = true;
    firewall = {
      enable = true;
      extraInputRules = ''
        ip saddr 172.31.0.0/16 tcp dport {2283,8096} accept
      '';
    };
  };

  networking.nameservers = [
    "45.90.28.0#d8522d.dns.nextdns.io"
    "2a07:a8c0::#d8522d.dns.nextdns.io"
    "45.90.30.0#d8522d.dns.nextdns.io"
    "2a07:a8c1::#d8522d.dns.nextdns.io"
  ];

  time.timeZone = "America/New_York";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  services.xserver = {
    xkb = {
      layout = "us";
      variant = "";
    };
    videoDrivers = [
      "nvidia"
      "intel"
    ];
  };

  # Hardware configuration
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };
    cpu.intel.updateMicrocode = true;
    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
    nvidia-container-toolkit.enable = true;
  };

  # Nixpkgs configuration
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "nvidia-x11"
        "nvidia-settings"
      ];
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

  # User configuration
  users = {
    defaultUserShell = pkgs.zsh;
    users = {
      matv = {
        isNormalUser = true;
        description = "Daniel";
        extraGroups = [
          "networkmanager"
          "wheel"
          "docker"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
        ];
      };
    };
  };

  # System packages and programs
  environment.systemPackages = with pkgs; [
    fastfetch
    zsh
    btop
    cloudflared
    mosh
    git
    speedtest-cli
    lshw
    dmidecode
    pciutils
    smartmontools
    nvme-cli
    duf
    bat
    python3
    plocate

    # Dead man's switch — arm before risky rebuilds, disarm after verifying access
    (writeShellScriptBin "arm-watchdog" ''
      mkdir -p /var/lib/nixos-watchdog
      readlink /run/current-system > /var/lib/nixos-watchdog/rollback-target
      echo "Saved rollback target: $(cat /var/lib/nixos-watchdog/rollback-target)"
      systemctl start nixos-watchdog.timer
      echo "Watchdog armed. You have 10 minutes to disarm with: sudo disarm-watchdog"
    '')
    (writeShellScriptBin "disarm-watchdog" ''
      systemctl stop nixos-watchdog.timer
      systemctl stop nixos-watchdog.service 2>/dev/null || true
      rm -f /var/lib/nixos-watchdog/rollback-target
      echo "Watchdog disarmed. Config is permanent."
    '')
  ];

  programs.zsh.enable = true;

  # Services configuration
  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = true; # TODO: disable after confirming key auth works via flake
        KbdInteractiveAuthentication = true; # TODO: disable after confirming key auth works via flake
      };
      extraConfig = ''
        AllowTcpForwarding yes
        GatewayPorts yes
      '';
      ports = [ 64829 ];
    };
    resolved = {
      enable = true;
      settings = {
        Resolve = {
          DNSOverTLS = "yes";
        };
      };
    };
  };

  # Docker (start at boot — this is a server)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers = {
    portainer = {
      image = "portainer/portainer-ce:latest";
      ports = [ "9443:9443" ];
      volumes = [
        "/arespool/appdata/Portainer:/data"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
    };
  };

  # =====================================================
  # COCKROACH ACCESS INFRASTRUCTURE
  # Never restart access services during nixos-rebuild switch.
  # Changes only take effect on reboot. This prevents losing access.
  # =====================================================

  services.cloudflared = {
    enable = true;
    tunnels = {
      "harbor" = {
        ingress = {
          "admin.matv.io" = "ssh://localhost:64829";
          "containers.matv.io" = {
            service = "https://localhost:9443";
            originRequest.noTLSVerify = true;
          };
          "request.matv.io" = "http://localhost:5055";
          "links.matv.io" = "http://localhost:28793";
          "cloud.matv.io" = {
            service = "https://localhost:9787";
            originRequest.noTLSVerify = true;
          };
          "downloader.matv.io" = "http://localhost:9091";
          "jackett.matv.io" = "http://localhost:9117";
          "sonarr.matv.io" = "http://localhost:8989";
          "radarr.matv.io" = "http://localhost:7878";
          "bazarr.matv.io" = "http://localhost:6767";
          "notes.matv.io" = "http://localhost:5230";
          "vault.matv.io" = "http://localhost:29446";
          "drivehealth.matv.io" = "http://localhost:5153";
          "sync.matv.io" = "http://localhost:8384";
          "watch.matv.io" = "http://localhost:8096";
          "retrospend.app" = "http://localhost:1997";
          "tracearr.matv.io" = "http://localhost:7898";
        };
        default = "http_status:404";
        credentialsFile = "/etc/cloudflared/credentials.json";
      };
    };
  };
  systemd.services.cloudflared-tunnel-harbor.restartIfChanged = false;

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  systemd.services.tailscaled.restartIfChanged = false;

  # Rescue SSH — independent of services.openssh, reachable over Tailscale on port 64830.
  # If main sshd or tunnel breaks, this still works.
  systemd.services.sshd-rescue = {
    description = "Rescue SSH daemon";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = false;
    serviceConfig = {
      ExecStart = "${pkgs.openssh}/bin/sshd -D -f /etc/ssh/sshd_rescue_config";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  environment.etc."ssh/sshd_rescue_config".text = ''
    Port 64830
    PidFile /run/sshd-rescue.pid
    HostKey /etc/ssh/ssh_host_ed25519_key
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
    AllowUsers matv
    StrictModes yes
  '';

  # Dead man's switch — rolls back to saved generation if not disarmed
  systemd.services.nixos-watchdog = {
    description = "Dead man's switch - rolls back to saved generation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "watchdog-rollback" ''
        if [ -f /var/lib/nixos-watchdog/rollback-target ]; then
          TARGET=$(cat /var/lib/nixos-watchdog/rollback-target)
          echo "Watchdog triggered! Rolling back to: $TARGET"
          nix-env -p /nix/var/nix/profiles/system --set "$TARGET"
          "$TARGET/bin/switch-to-configuration" switch
          rm -f /var/lib/nixos-watchdog/rollback-target
        else
          echo "No rollback target found, rebooting as fallback"
          systemctl reboot
        fi
      '';
    };
  };

  systemd.timers.nixos-watchdog = {
    description = "Dead man's switch timer (10 min)";
    timerConfig = {
      OnActiveSec = "10min";
      Unit = "nixos-watchdog.service";
      RemainAfterElapse = false;
    };
  };

  system.stateVersion = "23.05";
}
