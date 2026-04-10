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
    memoryPercent = 50;
  };

  # Desktop-tuned sysctl
  boot.kernel.sysctl = {
    # With zram, higher swappiness is better — compressed RAM swap is faster
    # than keeping cold pages uncompressed. Kernel docs recommend 150-200 with zram.
    "vm.swappiness" = 180;
    # Keep filesystem metadata caches longer (default 100)
    "vm.vfs_cache_pressure" = 50;
    # Flush dirty pages at fixed thresholds instead of % of RAM.
    # Prevents large write stalls on BTRFS with lots of RAM.
    "vm.dirty_bytes" = 268435456; # 256 MB
    "vm.dirty_background_bytes" = 67108864; # 64 MB
  };

  # CPU governor — plugged-in desktop, no reason not to run full speed
  powerManagement.cpuFreqGovernor = "performance";

  # BTRFS periodic scrub — detects silent data corruption (bitrot)
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # tmpfs for /tmp — reduces SSD writes, faster temp file I/O
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  # Cap journal size to prevent unbounded growth
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1month
  '';

  # Kill runaway processes before the system becomes unresponsive
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        MultiProfile = "multiple";
        Experimental = true;
      };
    };
  };
}
