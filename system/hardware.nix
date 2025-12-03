{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    # Include the results of the hardware scan.
    ../hardware-configuration.nix
  ];

  # Hardware firmware
  hardware.enableAllFirmware = true;

  # Enable wireless regulatory database and set regulatory domain to Argentina
  # This enables all 5GHz channels available in Argentina
  hardware.wirelessRegulatoryDatabase = true;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom="AR"
  '';

  # Enable NVIDIA proprietary drivers
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true; # Enables Kernel Mode Setting
    open = false; # Use proprietary kernel modules
    nvidiaSettings = true; # Enable the NVIDIA settings application
    package = config.boot.kernelPackages.nvidiaPackages.stable; # Use stable driver package
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        MultiProfile = "multiple";
      };
    };
  };
}

