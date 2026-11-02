{
  config,
  pkgs,
  lib,
  vars,
  inputs,
  extraLibs,
  ...
}:
{
  imports = extraLibs.scanPaths ./.;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;
      extraConfig."51-disable-webcam-mic" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "device.vendor.id" = "0x328f";
                "device.product.id" = "0x2013";
              }
            ];
            actions = {
              update-props = {
                "device.disabled" = true;
              };
            };
          }
        ];
      };
      # Disable Bluetooth microphone input so the Blue Snowball is the only mic source.
      # Bluetooth headsets still work for audio output (A2DP/sink).
      extraConfig."52-disable-bluetooth-mic" = {
        "monitor.bluez.rules" = [
          {
            matches = [
              {
                "node.name" = "~bluez_input.*";
              }
            ];
            actions = {
              update-props = {
                "node.disabled" = true;
              };
            };
          }
        ];
      };
      # Disable ALSA input devices (line-in, etc.) except the Blue Snowball
      # Split into two rules because device.vendor.id isn't available on nodes
      extraConfig."53-disable-alsa-inputs" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "node.name" = "~alsa_input.*";
              }
            ];
            actions = {
              update-props = {
                "node.disabled" = true;
              };
            };
          }
        ];
      };
      extraConfig."54-enable-snowball" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "node.name" = "~alsa_input.*BLUE_MICROPHONE.*";
              }
            ];
            actions = {
              update-props = {
                "node.disabled" = false;
              };
            };
          }
        ];
      };
    };
  };

  # Docker (socket-activated: starts on first use, not at boot)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };

  # dockerd never exits once something wakes it. Put it back to sleep after
  # 30 min with no running containers and no docker client (a build in
  # progress); the socket stays, so the next docker command starts it again.
  systemd.services.docker-idle-stop = {
    description = "Stop dockerd when idle";
    path = [
      config.virtualisation.docker.package
      pkgs.procps
      pkgs.systemd
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      systemctl is-active -q docker.service || exit 0
      since=$(systemctl show docker.service -p ActiveEnterTimestampMonotonic --value)
      now=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
      [ $((now - since / 1000000)) -ge 1800 ] || exit 0
      [ -z "$(docker ps -q)" ] || exit 0
      pgrep -x 'docker|docker-buildx|docker-compose' >/dev/null && exit 0
      systemctl stop docker.service
    '';
  };
  systemd.timers.docker-idle-stop = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*:0/30";
  };

  # NVIDIA container support is enabled per-host (see hosts/mantle/hardware.nix)

  virtualisation.oci-containers.backend = "docker";

  # Virtualization (socket-activated: libvirtd starts on first use, not at boot)
  programs.virt-manager.enable = true;
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  systemd.services.libvirtd.wantedBy = lib.mkForce [ ];
  systemd.sockets.libvirtd.wantedBy = [ "sockets.target" ];
  systemd.sockets.libvirtd-admin.wantedBy = [ "sockets.target" ];

  # Services
  services.gvfs.enable = true;
  # gvfs volume monitors for GNOME Online Accounts, iPhones and cameras: none
  # used. MTP (Android) and udisks2 (USB drives) stay.
  systemd.user.services = lib.genAttrs [
    "gvfs-goa-volume-monitor"
    "gvfs-afc-volume-monitor"
    "gvfs-gphoto2-volume-monitor"
  ] (_: { enable = false; });
  services.smartd = {
    enable = true;
    # -I 194: don't report every temperature change (185 log lines a boot on mantle).
    defaults.monitored = "-a -I 194";
  };
  services.systembus-notify.enable = lib.mkForce true;
  services.gnome.gcr-ssh-agent.enable = false;

  # Security
  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults lecture = never
      Defaults timestamp_timeout=30
    '';
  };

  security.pam.services = {
    "greetd".enableGnomeKeyring = true;
    "login".enableGnomeKeyring = true;
  };

  # Power management
  services.logind = {
    settings = {
      Login = {
        HandlePowerKey = "suspend";
        HandlePowerKeyLongPress = "poweroff";
        HandleRebootKey = "reboot";
        HandleRebootKeyLongPress = "reboot";
        HandleSuspendKey = "suspend";
        HandleSuspendKeyLongPress = "suspend";
        HandleHibernateKey = "hibernate";
        HandleHibernateKeyLongPress = "hibernate";
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "suspend";
        HandleLidSwitchDocked = "suspend";
      };
    };
  };

  # Overwrite existing *.bkp files instead of failing activation. (A
  # `find ~ -name '*.bkp' -delete` pre-start used to walk the whole home dir on
  # every boot: 53 s on mantle, with login held until it finished.)
  systemd.services."home-manager-${vars.user.name}".environment.HOME_MANAGER_BACKUP_OVERWRITE = "1";
}
