{
  config,
  lib,
  pkgs,
  ...
}:
{
  # NVIDIA proprietary drivers
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
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
