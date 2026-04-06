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

  # NVIDIA container support for Docker
  hardware.nvidia-container-toolkit.enable = true;

  # Compressed in-memory swap (reduces disk swap thrashing)
  zramSwap = {
    enable = true;
    memoryPercent = 50; # use up to 50% of RAM for compressed swap
  };

  # Kill runaway processes before the system becomes unresponsive
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;  # act when <5% memory free
    freeSwapThreshold = 10; # and <10% swap free
    enableNotifications = true;
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
