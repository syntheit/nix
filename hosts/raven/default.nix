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

  # Uptime Kuma — independent monitoring for harbor services
  services.uptime-kuma = {
    enable = true;
    appriseSupport = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
    };
  };

  # Cloudflared tunnel for remote SSH
  services.cloudflared = {
    enable = true;
    tunnels = {
      "raven" = {
        ingress = {
          "matv.io" = "http://localhost:3000";
          "status.matv.io" = "http://localhost:3001";
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

  # Shell
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # User — avf module creates droid, we just add docker group
  users.users."droid".extraGroups = [ "docker" ];
  users.users."droid".shell = pkgs.zsh;

  # Firewall
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Tailscale — VPN access independent of Cloudflare tunnel
  services.tailscale.enable = true;
  systemd.services.tailscaled.restartIfChanged = false;

  # Prevent cloudflared tunnel from restarting during rebuilds
  systemd.services.cloudflared-tunnel-raven.restartIfChanged = false;

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
    AllowUsers droid
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

  # Security
  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults lecture = never
    '';
  };
}
