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

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    # Enable JACK support for JACK applications
    #jack.enable = true;
  };

  # Docker
  virtualisation.docker = {
    enable = true;
    # Note: Using default storage driver (not ZFS since user has Btrfs)
  };

  # NVIDIA container support is enabled per-host (see hosts/caspian/hardware.nix)

  virtualisation.oci-containers.backend = "docker";

  # Virtualization
  programs.virt-manager.enable = true;
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # Services
  services.gvfs.enable = true;
  # Enable tumbler for file thumbnail generation (used by Nemo)
  services.tumbler.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.smartd.enable = true;
  services.systembus-notify.enable = lib.mkForce true;
  services.gnome.gcr-ssh-agent.enable = false;

  # GNOME Calendar and Contacts support
  # Evolution Data Server provides calendar and contacts backend
  services.gnome.evolution-data-server.enable = true;
  # GNOME Online Accounts for Google/Nextcloud integration
  services.gnome.gnome-online-accounts.enable = true;

  # Security
  security.sudo.extraConfig = ''
    Defaults lecture = never
    Defaults timestamp_timeout=120
  '';

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
