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
    # Installs nvidia-suspend/nvidia-hibernate/nvidia-resume systemd units and
    # sets NVreg_PreserveVideoMemoryAllocations=1, so the driver actually saves
    # and restores VRAM/GPU state across suspend. Without this, the proprietary
    # driver has no suspend/resume hooks at all (confirmed on this host: no
    # nvidia-suspend/resume/hibernate units exist, `systemctl cat` finds none) —
    # a well-documented cause of black-screen/hang-on-resume with NVIDIA +
    # Wayland. Requires a reboot to take effect (changes kernel module params).
    powerManagement.enable = true;
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

  # BTRFS automated snapshots
  services.btrbk.instances."default" = {
    onCalendar = "daily";
    settings = {
      snapshot_preserve_min = "2d";
      snapshot_preserve = "7d 4w";
      volume."/" = {
        subvolume."@" = { snapshot_dir = "@snapshots"; };
      };
    };
  };

  # tmpfs for /tmp — reduces SSD writes, faster temp file I/O
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  # Cap journal size to prevent unbounded growth
  services.journald.settings.Journal = {
    SystemMaxUse = "500M";
    MaxRetentionSec = "1month";
  };

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
