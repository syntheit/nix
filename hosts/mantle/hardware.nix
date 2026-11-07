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
    # NVIDIA's open kernel module: same driver and userspace (GL/Vulkan/CUDA),
    # only the kernel part is open. NVIDIA's default for Turing+ since 560;
    # the proprietary module is being dropped upstream. GSP firmware was
    # already running here under the proprietary module, so little changes.
    # Rollback: set false, or pick the previous generation at boot.
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Saves and restores VRAM/GPU state across suspend
    # (NVreg_PreserveVideoMemoryAllocations=1); without it, black screen or
    # hang on resume with NVIDIA + Wayland. With the open module on 595+,
    # nixpkgs drives this through the kernel's suspend notifiers
    # (NVreg_UseKernelSuspendNotifiers=1) instead of the old
    # nvidia-suspend/resume/hibernate systemd units, which are no longer
    # installed. VRAM is saved to /tmp (tmpfs) by default; mantle doesn't
    # hibernate, so RAM is fine.
    powerManagement.enable = true;
  };

  # NVIDIA container support for Docker
  hardware.nvidia-container-toolkit.enable = true;

  # GPU usage per process (compute and graphics), VRAM, clocks, power.
  environment.systemPackages = [ pkgs.nvtopPackages.nvidia ];

  # NVIDIA's shader cache caps at ~1 GB and cleans itself, so DXVK/vkd3d games
  # recompile shaders (stutter on launch). Per-game Steam launch options
  # reportedly don't help; it has to be in the session env. Cache lives in
  # ~/.cache/nvidia (its own subvolume, outside snapshots).
  environment.sessionVariables = {
    __GL_SHADER_DISK_CACHE_SIZE = "10737418240"; # 10 GiB
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
  };

  # The NVIDIA module turns acpid on by default; with no handlers it only
  # logs input events (lid/power keys are logind's).
  services.acpid.enable = false;

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

  # CPU power (modules/cpu-epp.nix): powersave governor + EPP
  # balance_performance, the kernel default. Measured here: 46 W -> 39 W
  # package at light desktop load (~$4/yr); benchmarks show ~0-1% throughput.
  powerManagement.energyPerformancePreference = "balance_performance";

  # Root SSD (CT1000MX500, ata13): the SATA link drops and hard-resets under
  # link power management (PHYRdyChg/DevExch, failed WRITE FPDMA QUEUED, one
  # read I/O error), across several boots. SMART is clean, so keep the link
  # at full power. If resets continue: reseat/replace the cable or move ports,
  # and update firmware (M3CR023 -> M3CR046).
  boot.kernelParams = [
    "libata.force=13:nolpm"
    # Don't auto-activate GPT swap partitions: sda3 would come up as plain,
    # unencrypted swap next to the LUKS root. swapDevices below encrypts it.
    "systemd.gpt_auto=0"
  ];

  # Motherboard sensor chip (Nuvoton, B450-A PRO MAX): fan RPMs and board
  # temperatures. Not autoloaded, so no fan readings existed at all. Read-only
  # use; the BIOS fan curve still controls the fans.
  boot.kernelModules = [ "nct6775" ];

  # TRIM through LUKS: without this fstrim ran weekly but discards never
  # reached the SSD (higher write amplification, slower writes). Leaks which
  # blocks are free, the accepted trade-off for SSDs.
  boot.initrd.luks.devices."luks-3e72a884-3bf1-43ba-815c-b04b5efb3e26".allowDiscards = true;

  # Overflow swap behind zram, encrypted with a fresh random key every boot
  # (no hibernation here, so nothing needs to survive a reboot).
  swapDevices = [
    {
      device = "/dev/disk/by-partuuid/07120c24-716e-4a93-b292-fdae11ced08c"; # sda3
      randomEncryption = {
        enable = true;
        allowDiscards = true;
      };
    }
  ];

  # BTRFS periodic scrub — detects silent data corruption (bitrot)
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Regenerable directories as their own subvolumes, so the daily snapshots
  # of `@` (7d 4w) don't pin their churn (modules/disk-hygiene.nix).
  diskHygiene.subvolumes =
    map
      (p: {
        path = "/home/daniel/${p}";
        user = "daniel";
        group = "users";
      })
      [
        ".cache"
        "Downloads"
        ".cargo"
        ".npm"
        ".local/share/pnpm"
        "go"
        ".ollama"
      ]
    ++ [
      {
        path = "/home/daniel/.local/share/Steam";
        user = "daniel";
        group = "users";
        mode = "0700";
      }
      {
        path = "/var/lib/docker";
        mode = "0710";
      }
    ];

  # BTRFS automated snapshots
  services.btrbk.instances."default" = {
    onCalendar = "daily";
    settings = {
      snapshot_preserve_min = "2d";
      snapshot_preserve = "7d 4w";
      volume."/mnt/btrfs-root" = {
        subvolume."@" = {
          snapshot_dir = "@snapshots";
        };
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

  # Kill runaway processes before the system becomes unresponsive. earlyoom,
  # not systemd-oomd: Hyprland launches every app into session-N.scope with
  # Hyprland itself, and oomd kills whole cgroups, so it would end the desktop
  # session instead of killing one app.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };
  # oomd is on by default but monitors no cgroup here (earlyoom does the job).
  # Mask the daemon rather than `systemd.oomd.enable = false`: that also drops
  # the generated -.slice/system.slice units, and a live switch then stops
  # system.slice (every system service).
  systemd.services.systemd-oomd.enable = false;
  systemd.sockets.systemd-oomd.enable = false;

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
