{
  config,
  lib,
  pkgs,
  vars,
  inputs,
  ...
}:
{
  imports = [
    ../../modules/numtide-cache.nix
    inputs.nixos-avf.nixosModules.avf
    ../../modules/server-safety
    ../../modules/foyer.nix
    ../../modules/construct-life.nix
    ./secrets.nix
    # Builds run on the mini's aarch64 VM, not on the phone (sets max-jobs = 0).
    ./nix-builder.nix
  ];

  services.serverSafety = {
    enable = true;
    user = "droid";
  };

  # Foyer — server dashboard
  services.foyer = {
    enable = true;
    domain = "raven.matv.io";
    jwtSecretFile = config.sops.secrets.foyer_jwt_secret.path;
    apiKeyFiles = [ config.sops.secrets.foyer_api_key.path ];
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
    services = {
      "Website" = { url = "https://matv.io"; };
      "Status" = { url = "https://status.matv.io"; };
    };
    # Read CPU temperature from Android host via SSH
    temperatureCommand = "ssh -p 8022 -i /var/lib/foyer/android-ssh-key -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(ip route | awk '/default/ {print $3}') 'for z in /sys/class/thermal/thermal_zone*/; do t=$(cat \"$z/type\" 2>/dev/null); case \"$t\" in BIG|MID|LITTLE) echo $(( $(cat \"$z/temp\") / 1000 ));; esac; done' | sort -rn | head -1";
  };

  # construct — Daniel's life portal (moved from harbor 2026-11-02). Public at construct.matv.io via this tunnel;
  # Cloudflare Access guards only /auth/login. Jellyfin and Seerr stay on harbor, reached over the tailnet.
  # Android releases build on harbor and rsync the F-Droid repo here (modules/construct-android.nix).
  services.constructLife = {
    enable = true;
    user = "droid";
    seerrUrl = "http://harbor:5055";
    jellyfinUrl = "http://harbor:8096";
    environment = {
      CF_ACCESS_TEAM = "matv";
      CF_ACCESS_AUD = "5f8d308e0bcf4b314007375751df1e617056afb132d05690e1d5a2416a43d245";
    };
  };

  # Copy SSH key so the foyer user can read it (SSH rejects keys not owned by the caller)
  systemd.services.foyer.serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/install -m 0600 -o foyer -g foyer /home/droid/.ssh/mainkey /var/lib/foyer/android-ssh-key"
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
      PrintLastLog = false;
    };
  };

  users.users."droid".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
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
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers = {
    website = {
      image = "synzeit/website:arm64";
      ports = [ "127.0.0.1:3000:3000" ];
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
      cores = 0;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Journal — cap size to reduce journald memory footprint
  services.journald.settings.Journal = {
    SystemMaxUse = "200M";
    MaxRetentionSec = "1month";
  };

  # /boot is a tiny 249M EFI partition (fixed by the nixos-avf VM image), and
  # each generation's kernel + initrd is ~86M. The avf module leaves
  # configurationLimit unset (= keep every generation forever), which fills
  # /boot after a couple of kernel bumps. Cap retention so systemd-boot prunes.
  boot.loader.systemd-boot.configurationLimit = 2;

  # The AVF balloon patch bundles six commits. Its last hunk no longer matches
  # Linux 6.1.188 because virtballoon_validate gained an indirect-descriptor
  # check. Keep the first five commits and rebase only the last hunk.
  boot.kernelPatches =
    let
      avfBase = pkgs.fetchgit {
        url = "https://android.googlesource.com/platform/packages/modules/Virtualization/";
        rev = "android-16.0.0_r3";
        hash = "sha256-boWayfOI88ejnXZ5yQzYdSuMANJLB5/Wd30ZWtsXuHw=";
      };
      originalBalloonPatch = "${avfBase}/build/debian/kernel/patches/avf/arm64-balloon.patch";
      tab = "\t";
      balloonFirstFive = pkgs.runCommand "avf-arm64-balloon-first-five.patch" { } ''
        ${pkgs.gnugrep}/bin/grep -q '^From 49de3a1d0bb478858eb66a5b853f0d0a5b1909dc ' ${originalBalloonPatch}
        ${pkgs.gnused}/bin/sed '/^From 49de3a1d0bb478858eb66a5b853f0d0a5b1909dc /,$d' ${originalBalloonPatch} > "$out"
      '';
      balloonAccessPlatform = pkgs.writeText "avf-balloon-access-platform-6.1.188.patch" ''
        diff --git a/drivers/virtio/virtio_balloon.c b/drivers/virtio/virtio_balloon.c
        --- a/drivers/virtio/virtio_balloon.c
        +++ b/drivers/virtio/virtio_balloon.c
        @@ -1103,4 +1103,3 @@ static int virtballoon_validate(struct virtio_device *vdev)
         ${tab} */
         ${tab}__virtio_clear_bit(vdev, VIRTIO_RING_F_INDIRECT_DESC);
        -${tab}__virtio_clear_bit(vdev, VIRTIO_F_ACCESS_PLATFORM);
         ${tab}return 0;
      '';
    in
    lib.mkForce [
      {
        name = "avf-balloon-first-five";
        patch = balloonFirstFive;
        structuredExtraConfig = with lib.kernel; {
          SND_VIRTIO = module;
          SND = yes;
          SOUND = yes;
        };
      }
      {
        name = "avf-balloon-access-platform";
        patch = balloonAccessPlatform;
      }
      {
        name = "avf-cpufreq";
        patch = "${avfBase}/build/debian/kernel/patches/avf/virtual-cpufreq.patch";
        structuredExtraConfig = with lib.kernel; {
          CPU_FREQ = yes;
          IKCONFIG = yes;
          IKCONFIG_PROC = yes;
          ANDROID_V_CPUFREQ_VIRT = yes;
        };
      }
    ];

  # Network tunables — BBR congestion control + larger buffers for tunnel traffic
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.core.rmem_default" = 1048576;
    "net.core.wmem_default" = 1048576;
    "net.ipv4.tcp_fastopen" = 3;
  };

  # Cloudflared tunnel
  services.cloudflared = {
    enable = true;
    tunnels = {
      "raven" = {
        ingress = {
          "matv.io" = "http://localhost:3000";
          "raven.matv.io" = "http://localhost:8420";
          "raven-ssh.matv.io" = "ssh://localhost:22";
          "construct.matv.io" = "http://localhost:4322";
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
    sqlite
    rsync # harbor's construct-android-release pushes the F-Droid repo here
  ];

  # Shell
  programs.mosh.enable = true;
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

  # Security
  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults lecture = never
    '';
  };
}
