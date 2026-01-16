{
  pkgs,
  ...
}:
{
  # Power Management
  services.thermald.enable = true;
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 50;

      # Optional: ThinkPad battery charge thresholds
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  # Intel Graphics
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libvdpau-va-gl
    ];
  };

  # Force modesetting driver for integrated graphics; no NVIDIA drivers
  services.xserver.videoDrivers = [ "modesetting" ];

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false; # Save power on boot
    settings = {
      General = {
        MultiProfile = "multiple";
      };
    };
  };

  # Firmware updates
  services.fwupd.enable = true;

  # Fingerprint reader
  services.fprintd.enable = true;

  zramSwap.enable = true;
}
