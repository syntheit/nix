{
  config,
  lib,
  pkgs,
  ...
}:
{
  # ── Apple T2 (MacBookPro16,1) ────────────────────────────────────────────
  # The nixos-hardware apple-t2 module does the heavy lifting: it pins a
  # T2-patched kernel, loads apple-bce (keyboard/trackpad/audio bridge) in
  # initrd, and sets the required kernel params (pcie_ports=compat,
  # intel_iommu=on, iommu=pt).
    # NOTE (trackpad): the internal trackpad needs the newer linux-t2 patches
    # (6.18+ branch) to bind its multitouch HID interface correctly — on 6.12 it
    # comes up as a relative mouse with no working click. But this nixos-hardware
    # module only offers kernelChannel "stable" (linux_6_12) or "latest"
    # (linux_6_19), and 6.19 was removed from our nixpkgs (EOL), so the bump
    # can't build. Revisit when the module exposes a 6.18-based t2 kernel (then
    # this becomes a one-line flip). Until then: USB mouse for laptop use.
  hardware.apple-t2 = {
    kernelChannel = "stable";

    # External display + HDMI run off the AMD dGPU on this model, so leave the
    # iGPU-force off and use amdgpu (see graphics block below).
    enableIGPU = false;

    # Pull in the Broadcom WiFi + Bluetooth firmware (this also provides the
    # BCM4364 Bluetooth .hcd that the Asahi extractor can't generate).
    # "sonoma" is the newest set the module ships and is forward-compatible with
    # this machine. The exact firmware captured from this Mac's own macOS is
    # archived at harbor:/home/matv/vista-firmware as a fallback if the generic
    # set ever proves flaky.
    firmware.enable = true;
    firmware.version = "sonoma";
  };

  # t2linux binary cache — serves prebuilt linux-t2 kernels (and the apple-bce
  # closure) so kernel bumps download instead of compiling from source. Uses
  # extra-* so cache.nixos.org is kept, not replaced.
  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [ "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=" ];
  };

  # ── GPU: AMD Radeon Pro 5500M (drives the HDMI/TV output) ─────────────────
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Steam / 32-bit games
  };
  # Early KMS so the HDMI console comes up at boot.
  boot.initrd.kernelModules = [ "amdgpu" ];

  # ── Disk / boot plumbing (disko provides the filesystems) ─────────────────
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "thunderbolt"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ── Headless-by-the-TV behaviour ──────────────────────────────────────────
  # Lid stays shut permanently; never suspend on lid close (or at all — this is
  # a server/media box that must stay reachable).
  # mkForce overrides services/default.nix, which defaults lid actions to
  # "suspend" (correct for the portable laptops, wrong for an always-on HTPC).
  services.logind.settings.Login = {
    HandleLidSwitch = lib.mkForce "ignore";
    HandleLidSwitchExternalPower = lib.mkForce "ignore";
    HandleLidSwitchDocked = lib.mkForce "ignore";
    HandlePowerKey = lib.mkForce "ignore";
    IdleAction = "ignore";
  };
  # The i9-9880H runs hot in a closed chassis; schedutil keeps it cool/quiet
  # when idle and still ramps for transcoding/playback.
  powerManagement.cpuFreqGovernor = "schedutil";

  # Bluetooth (for casting to a BT speaker later).
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      MultiProfile = "multiple";
      Experimental = true;
    };
  };

  # ── Memory / storage hygiene (mirrors mantle) ─────────────────────────────
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_bytes" = 268435456; # 256 MB
    "vm.dirty_background_bytes" = 67108864; # 64 MB
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

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1month
  '';

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };
}
