{
  lib,
  pkgs,
  vars,
  inputs,
  ...
}:
{
  imports = [
    inputs.nixos-avf.nixosModules.avf
  ];

  # Override deprecated option set by nixos-avf module
  services.resolved.settings.Resolve.DNSSEC = lib.mkForce "false";

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

  # Gatus — declarative status page monitoring harbor + raven services
  systemd.services.gatus = {
    description = "Gatus status monitor";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.gatus}/bin/gatus";
      DynamicUser = true;
      StateDirectory = "gatus";
      Environment = "GATUS_CONFIG_PATH=/etc/gatus/config.yaml";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  environment.etc."gatus/config.yaml".text = ''
    storage:
      type: sqlite
      path: /var/lib/gatus/data.db

    web:
      address: 127.0.0.1
      port: 3001

    endpoints:
      # ===== HARBOR SERVICES =====
      - name: Nextcloud
        group: harbor
        url: https://cloud.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Jellyfin
        group: harbor
        url: https://watch.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Immich
        group: harbor
        url: https://photos.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Bitwarden
        group: harbor
        url: https://vault.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Retrospend
        group: harbor
        url: https://retrospend.app
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Linkding
        group: harbor
        url: https://links.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Overseerr
        group: harbor
        url: https://request.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Transmission
        group: harbor
        url: https://downloader.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Jackett
        group: harbor
        url: https://jackett.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Sonarr
        group: harbor
        url: https://sonarr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Radarr
        group: harbor
        url: https://radarr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Bazarr
        group: harbor
        url: https://bazarr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Memos
        group: harbor
        url: https://notes.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Scrutiny
        group: harbor
        url: https://drivehealth.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Syncthing
        group: harbor
        url: https://sync.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Trackarr
        group: harbor
        url: https://tracearr.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      # ===== RAVEN SERVICES =====
      - name: Website
        group: raven
        url: https://matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"

      - name: Status Page
        group: raven
        url: https://status.matv.io
        interval: 2m
        conditions:
          - "[STATUS] < 500"
  '';

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
