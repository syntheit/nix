{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # linux-t2's HID trackpad patch group no longer applies to Linux 6.18.52.
  # Vista is headless and does not use its internal trackpad (see the note
  # below), so retain the rest of the T2 patch series while omitting only that
  # stale trackpad-support patches.  4001 targets Asahi (Apple silicon) and
  # 4003–4005 target T2/Magic trackpads; none are needed by this headless Intel
  # T2 host.
  t2Patchset = builtins.fromJSON (
    builtins.readFile "${inputs.nixos-hardware}/apple/t2/pkgs/linux-t2/stable.json"
  );
  t2Kernel = (pkgs.callPackage "${inputs.nixos-hardware}/apple/t2/pkgs/linux-t2/generic.nix" { }) {
    kernel = pkgs.linux_6_18;
    patchesFile = builtins.toFile "vista-linux-t2-stable.json" (
      builtins.toJSON (
        t2Patchset
        // {
          patches = lib.filter (
            patch:
            !(builtins.elem patch.name [
              "4001-asahi-trackpad.patch"
              "4003-HID-apple-ignore-the-trackpad-on-T2-Macs.patch"
              "4004-HID-magicmouse-Add-support-for-trackpads-found-on-T2.patch"
              "4005-HID-magicmouse-fix-regression-breaking-support-for-M.patch"
            ])
          ) t2Patchset.patches;
        }
      )
    );
  };
in
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

  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor t2Kernel);

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
  boot.kernelParams = [ "video=eDP-1:d" ];

  # ── Reboots must go through kexec, not firmware ───────────────────────────
  # This Mac's iBridge firmware treats EVERY CPU/chipset reset method — ACPI (the
  # default), EFI, and PCI 0xcf9 — as a *power-off* rather than a restart. We
  # verified all three: `systemctl reboot` cleanly shut vista down and left it
  # dead until physically powered on (confirmed via the boot logs: a firmware
  # reboot = ~4 min off + a cold POST; reboot=pci was tried and still powered
  # off). That's unacceptable for a headless, remote-managed box, and no `reboot=`
  # value fixes it. kexec sidesteps the firmware entirely — it jumps straight into
  # the next kernel and never hands control back — and is the reboot path the
  # t2linux project documents for T2 Macs (verified working here: a kexec reboot
  # comes back in ~2-3 s with no POST).
  #
  # So alias `reboot` to a kexec reboot. `systemctl kexec` auto-stages the
  # current generation's kernel via prepare-kexec.service, so this needs no extra
  # steps and, after a `nixos-rebuild switch`, kexecs into the newly-activated
  # kernel. Caveats:
  #   • Run `nixos-rebuild switch` (not `boot`) before rebooting for a kernel
  #     update — kexec boots /run/current-system/kernel, which `switch` updates
  #     but `boot` does not.
  #   • `poweroff` / `shutdown -h` are unaffected and correct (a clean power-off
  #     is fine). It's only *reboot* that the firmware mishandles.
  #   • Bypasses (`sudo reboot`, `systemctl reboot`, `shutdown -r`) still hit the
  #     firmware and will power off — use the aliased `reboot`.
  environment.shellAliases.reboot = "sudo systemctl kexec";

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

  # ── Battery guard: full power, but never run the battery flat on AC ───────
  # The firmware lets the i9 alone draw 100 W sustained / 125 W burst (RAPL
  # PL1/PL2), more than any brick can feed this Mac, so under heavy load the
  # battery tops up the difference. That boost is welcome — but on 2026-09-22 a
  # six-hour headscale reconnect storm kept every core busy and took the battery
  # from full to 3% while plugged in, and at 0% the next spike browns the Mac out
  # (and a powered-off vista stays off; see the reboot note above).
  #
  # The brick matters as much as the load. The Mac caps its own input at 4.65 A,
  # ~87 W, and only gets that from a 96 W+ brick on a 5 A cable with nothing else
  # sharing it: the storm hit while it sat on a 61 W Apple brick (57 W in), and a
  # multi-port brick splitting power with a phone gave 62 W. The SMC reports the
  # truth — keys PDTR (watts in), ID0R (amps in) and ACIC (input limit, mA),
  # readable via applesmc's key_at_index files under /sys/devices/…/APP0001:00.
  #
  # Three zones by charge, with a gap at the top so it can't flap:
  #   • boost (≥ 35%, until < 30%): firmware limits; the battery covers spikes.
  #   • hold (15–30%): every 15 s, measure the battery's average net power and
  #     keep it gaining ≥ 3 W — the CPU gets everything else the brick supplies.
  #   • refill (< 15%): the same, but keep the battery gaining ≥ 15 W, so a low
  #     battery climbs out of brown-out range in minutes, not hours.
  # A shortfall is cut in one step (never less than 5 W). The limit only rises,
  # 5 W at a time, when there's surplus AND the CPU is actually pressing against
  # it — otherwise an idle stretch would wind it up to 100 W and the next build
  # would drain the battery while it stepped back down. Guard starts at the
  # chip's rated 45 W and never goes below 20 W; with the AC unplugged the
  # battery can't gain at all, so it drops to the floor, which is also right for
  # riding out an outage.
  systemd.services.battery-guard = {
    description = "Cap CPU power only while the battery is low";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 10;
    };
    script = ''
      rapl=/sys/class/powercap/intel-rapl:0
      bat=/sys/class/power_supply/BAT0

      set_limit() { # sustained watts; burst = +25 W, up to the firmware's 125
        pl2=$(( $1 + 25 ))
        if [ $pl2 -gt 125 ]; then pl2=125; fi
        echo $(( $1 * 1000000 )) > $rapl/constraint_0_power_limit_uw
        echo $(( pl2 * 1000000 )) > $rapl/constraint_1_power_limit_uw
      }

      read -r erange < $rapl/max_energy_range_uj

      # Over ~15 s, set net (average battery power in mW, + = charging) and cpu
      # (average CPU package power in W). One uevent read per sample keeps
      # status and current from the same instant; the driver reports current
      # unsigned, so the sign comes from the status.
      measure() {
        read -r e1 < $rapl/energy_uj
        sum=0 n=0
        while [ $n -lt 30 ]; do
          status="" cur=0 volt=0
          while IFS="=" read -r k v; do
            case $k in
              POWER_SUPPLY_STATUS) status=$v ;;
              POWER_SUPPLY_CURRENT_NOW) cur=$v ;;
              POWER_SUPPLY_VOLTAGE_NOW) volt=$v ;;
            esac
          done < $bat/uevent
          p=$(( cur / 1000 * (volt / 1000) / 1000 ))
          case $status in
            Charging) ;;
            Discharging) p=$(( -p )) ;;
            *) p=0 ;;
          esac
          sum=$(( sum + p )) n=$(( n + 1 ))
          sleep 0.5
        done
        read -r e2 < $rapl/energy_uj
        if [ "$e2" -lt "$e1" ]; then e2=$(( e2 + erange )); fi
        net=$(( sum / n ))
        cpu=$(( (e2 - e1) / 15000000 ))
      }

      mode="" limit=100
      while true; do
        read -r pct < $bat/capacity
        if [ "$pct" -lt 30 ] || { [ -z "$mode" ] && [ "$pct" -lt 35 ]; }; then
          new=guard
        elif [ "$pct" -ge 35 ]; then
          new=boost
        else
          new=$mode
        fi
        if [ "$new" != "$mode" ]; then
          mode=$new
          if [ $mode = guard ]; then limit=45; else limit=100; fi
          echo "battery $pct%: $mode mode, CPU limit $limit W"
        fi

        # Re-asserted every pass, in case anything else resets the limits.
        set_limit $limit

        if [ $mode = boost ]; then
          sleep 15
          continue
        fi
        if [ "$pct" -lt 15 ]; then want=15000; else want=3000; fi # mW
        measure
        old=$limit
        if [ $net -lt $want ]; then
          short=$(( (want - net + 999) / 1000 ))
          if [ $short -lt 5 ]; then short=5; fi
          limit=$(( limit - short ))
          if [ $limit -lt 20 ]; then limit=20; fi
        elif [ $net -gt $(( want + 7000 )) ] && [ $cpu -ge $(( limit - 5 )) ]; then
          limit=$(( limit + 5 ))
          if [ $limit -gt 100 ]; then limit=100; fi
        fi
        if [ $limit -ne $old ]; then
          echo "battery $pct%, net $(( net / 1000 )) W, CPU $cpu W: limit $limit W"
        fi
      done
    '';
  };

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

  # Reclaim stray build caches from /tmp.
  #
  # /tmp is tmpfs on purpose — fast, and it spares the NVMe a great deal of
  # write churn. What does not belong there is a BUILD CACHE. Go's own default
  # is ~/.cache/go-build, on disk, deliberately: a cache wiped on every reboot
  # is not a cache, it is a temp directory you pay to refill. Agent sessions
  # working on this box have nonetheless set GOCACHE to /tmp/<session>-go-cache
  # to avoid contending on the shared cache, and on 2026-09-19 six of those
  # took /tmp to 100% of its 15.6G. The visible symptom was misleading: the
  # archive store reserves 2G of headroom, so every Stage refused with a
  # message that reads like a code fault rather than a full disk.
  #
  # The convention is the real fix — per-session caches belong under ~/.cache.
  # This is the safety net for when that is forgotten, which it will be.
  # Deliberately narrow: it matches build-cache names only, never /tmp at
  # large, so nothing else in /tmp is at risk from it.
  systemd.tmpfiles.rules = [
    "e /tmp/*go-cache* - - - 1d"
    "e /tmp/*gocache* - - - 1d"
    "e /tmp/*-go-build* - - - 1d"
  ];

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
