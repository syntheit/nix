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

    # Broadcom WiFi/BT firmware extractor: OFF. It builds via an in-guest QEMU
    # VM that kernel-panics deterministically on this host (post the 2026-07
    # nixpkgs bump), and its only job is WiFi + Bluetooth — both moot now that
    # vista is a headless, ethernet-only server with Bluetooth disabled. Generic
    # redistributable firmware still loads (hardware.enableRedistributableFirmware
    # below). If WiFi is ever needed again, the real firmware captured from this
    # Mac's macOS is archived at harbor:/home/matv/vista-firmware — wire it in via
    # hardware.firmware rather than re-enabling the broken extractor.
    firmware.enable = false;
  };

  # ── T2 bridge NIC: keep NetworkManager off it (prevents a kernel lockup) ───
  # The T2 exposes an internal USB "bridge" network interface (MAC
  # ac:de:48:00:11:22, enp4s0f1u1) that has nothing on the other end — our real
  # LAN is the USB-ethernet dongle (enp127s0u1c2). NetworkManager doesn't know
  # that and auto-creates a DHCP "Wired connection" for it, retrying activation
  # forever. Each retry pushes TX onto the bridge; when a transmit stalls, the
  # netdev TX watchdog fires in softirq context and calls apple-bce's URB-cancel
  # path, which *sleeps* there ("bad: scheduling from the idle thread!") and hard-
  # locks the kernel. That froze vista for hours on 2026-07-13 until it was
  # power-cycled. Marking the bridge unmanaged (by its stable Apple MAC) stops the
  # DHCP retry storm — the iface stays down, nothing transmits, the bug can't fire.
  # apple-bce's keyboard/audio functions are unaffected; this only drops IP mgmt
  # of that one netdev. See the panic-on-lockup sysctls below for the safety net.
  networking.networkmanager.unmanaged = [ "mac:ac:de:48:00:11:22" ];

  # t2linux binary cache — serves prebuilt linux-t2 kernels (and the apple-bce
  # closure) so kernel bumps download instead of compiling from source. Uses
  # extra-* so cache.nixos.org is kept, not replaced.
  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [ "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=" ];
  };

  # ── GPU: AMD Radeon Pro 5500M ─────────────────────────────────────────────
  hardware.graphics.enable = true;
  # Early KMS so amdgpu is up from boot.
  boot.initrd.kernelModules = [ "amdgpu" ];

  # ── Internal panel: OFF, permanently ──────────────────────────────────────
  # Headless server, lid shut → the built-in Retina panel must never light
  # (burn-in / image-persistence risk, esp. the OLED Touch Bar). Two layers:
  #
  # 1) Disable the eDP connector at the DRM level. `video=eDP-1:d` tells amdgpu
  #    to bring the internal panel up disabled, so no compositor or console
  #    framebuffer can ever scan out to it. (External HDMI/DP connectors are
  #    untouched — plug a monitor in for recovery if ever needed.)
  # reboot=pci: make `reboot` actually restart instead of powering off. This
  # Mac's default reset method is ACPI ("Apple Mac detected, using EFI v1.10
  # runtime services only" + /sys/kernel/reboot/type=acpi), and on Apple firmware
  # both the ACPI and EFI resets are handled as a *power-off*, not a restart — so
  # `systemctl reboot` cleanly shut vista down and left it dead until physically
  # powered on (bad for a headless, remote-managed box). The 0xcf9 PCI-reset
  # method restarts correctly; older MacBooks get it via the kernel's DMI quirk
  # table, but MacBookPro16,1 is too new to be listed, so we set it explicitly.
  boot.kernelParams = [ "video=eDP-1:d" "reboot=pci" ];

  # 2) Belt-and-suspenders: force both backlights (main gmux panel + the OLED
  #    Touch Bar) to zero at boot, in case the PWM rail stays powered even with
  #    the connector disabled. Writes defensively — the sysfs nodes may not
  #    exist once the panel is off, so failures are ignored.
  systemd.services.backlight-off = {
    description = "Force internal panel + Touch Bar backlight off (headless)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-backlight@backlight:gmux_backlight.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "backlight-off" ''
        for bl in gmux_backlight appletb_backlight; do
          echo 0 > "/sys/class/backlight/$bl/brightness" 2>/dev/null || true
        done
      '';
    };
  };

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

  # ── Headless server behaviour ─────────────────────────────────────────────
  # Lid stays shut permanently; never suspend on lid close (or at all — this is
  # an always-on server that must stay reachable).
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

  # Bluetooth off — its only purpose here was casting to a BT speaker under the
  # old HTPC role, which is gone. Headless server has no use for it.
  hardware.bluetooth.enable = false;

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

    # ── Auto-recover from a kernel lockup (safety net) ──────────────────────
    # The Intel TCO hardware watchdog is disabled by this Mac's firmware
    # ("iTCO_wdt: unable to reset NO_REBOOT flag, device disabled by
    # hardware/BIOS"), so a wedged kernel has nothing to reset it — that's why
    # the 2026-07-13 apple-bce lockup left the box dead for hours. These make a
    # future lockup panic-and-reboot in ~30s instead of hanging indefinitely.
    # Deliberately NOT enabling hung_task_panic / panic_on_warn: on a btrfs
    # media box with scrub/btrbk/transcoding those risk spurious reboots.
    "kernel.softlockup_panic" = 1; # CPU stuck spinning in kernel → panic
    "kernel.panic_on_oops" = 1; # don't limp along in a broken state
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
