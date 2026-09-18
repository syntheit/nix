{
  config,
  lib,
  pkgs,
  ...
}:
{
  # ── Generic x86_64 UEFI server profile ────────────────────────────────────
  # No real hardware to `nixos-generate-config` against yet (this is written
  # ahead of the physical NUC arriving at the colo) — this is a best-effort
  # generic modern-PC profile. Intel NUCs are extremely standard hardware
  # (NVMe + i915 + normal USB/ethernet), so this is low-risk, but spot-check
  # against real `lsblk`/`lspci` output once the coworker has the box in hand.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "uas"
    "sd_mod"
    # virtio: needed to boot under QEMU/KVM, where the root disk is /dev/vda.
    # Without these the initrd can't see the root device at all and the boot
    # dies silently before any userspace runs — which is exactly what happened
    # the first time this config was rehearsed in a VM. Harmless on the real
    # NUC (the modules simply never load), and keeps the VM rehearsal a valid
    # test of the same config we ship.
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  # Log the boot to BOTH the display and the serial port. The colo box has no
  # out-of-band console, so the failure mode to avoid at all costs is a boot
  # that dies with no output anywhere. tty0 stays the primary console (that's
  # what a monitor plugged into the NUC shows); ttyS0 costs nothing when no
  # serial port is present and is what makes a VM rehearsal (or a NUC serial
  # header) able to see early boot at all.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ── Headless server behaviour ─────────────────────────────────────────────
  services.logind.settings.Login = {
    HandlePowerKey = lib.mkForce "ignore";
    IdleAction = "ignore";
  };

  # ── Memory / storage hygiene (mirrors vista/mantle) ───────────────────────
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_bytes" = 268435456; # 256 MB
    "vm.dirty_background_bytes" = 67108864; # 64 MB

    # ── Auto-recover from a kernel lockup (safety net) ──────────────────────
    # No physical console at the colo — a wedged kernel needs to reboot itself
    # rather than hang indefinitely waiting for someone to walk over and power
    # -cycle it. Mirrors vista's hardware.nix.
    "kernel.softlockup_panic" = 1;
    "kernel.panic_on_oops" = 1;
    "kernel.panic" = 30; # reboot 30s after any panic
  };

  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  services.btrbk.instances."default" = {
    onCalendar = "daily";
    settings = {
      snapshot_preserve_min = "2d";
      snapshot_preserve = "7d 4w";
      volume."/" = {
        subvolume."@" = {
          snapshot_dir = "@snapshots";
        };
      };
    };
  };

  services.journald.settings.Journal = {
    SystemMaxUse = "500M";
    MaxRetentionSec = "1month";
  };

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };
}
