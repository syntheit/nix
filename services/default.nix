{
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
    # Enable JACK support for JACK applications
    #jack.enable = true;
  };

  # Docker (socket-activated: starts on first use, not at boot)
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
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
  services.smartd.enable = true;
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

  # Configure Home Manager systemd service to overwrite existing backup files
  # This prevents activation failures when old backup files exist
  systemd.services."home-manager-${vars.user.name}" = {
    environment = {
      HOME_MANAGER_BACKUP_OVERWRITE = "1";
    };
    # Clean up old backup files before activation to prevent conflicts
    serviceConfig = {
      ExecStartPre = lib.mkForce (
        pkgs.writeShellScript "cleanup-hm-backups" ''
          ${pkgs.findutils}/bin/find /home/${vars.user.name} -name "*.bkp" -type f -delete 2>/dev/null || true
        ''
      );
    };
  };
}
