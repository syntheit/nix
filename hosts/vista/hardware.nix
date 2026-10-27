{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # linux-t2's HID trackpad patch group no longer applies to Linux 6.18.52.
  # Vista is headless and does not use its internal trackpad (it sits behind
  # apple-bce, which vista no longer loads; see the BCE note below), so retain
  # the rest of the T2 patch series while omitting those
  # stale trackpad-support patches.  4001 targets Asahi (Apple silicon) and
  # 4003–4005 target T2/Magic trackpads; none are needed by this headless Intel
  # T2 host.
  # 2008 (i915 4-lane quirk) stopped applying on 6.18.58.  It targets the
  # MacBookPro15,1's Intel iGPU; vista is a MacBookPro16,1 running with the
  # iGPU off (enableIGPU = false below), so it is omitted too.
  t2Patchset = builtins.fromJSON (
    builtins.readFile "${inputs.nixos-hardware}/apple/t2/pkgs/linux-t2/stable.json"
  );
  t2Base = (pkgs.callPackage "${inputs.nixos-hardware}/apple/t2/pkgs/linux-t2/generic.nix" { }) {
    kernel = pkgs.linux_6_18;
    patchesFile = builtins.toFile "vista-linux-t2-stable.json" (
      builtins.toJSON (
        t2Patchset
        // {
          patches = lib.filter (
            patch:
            !(builtins.elem patch.name [
              "2008-i915-4-lane-quirk-for-mbp15-1.patch"
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
  # 3001 (applesmc static structures → drvdata) is carried as a local port.
  # 6.18.53 backported upstream 5a0aacaa2d59 ("hwmon: (applesmc) fix key
  # backlight workqueue leak on register failure"), which adds the same
  # led_classdev_register() error path that 3001 adds, so one hunk stopped
  # applying. The port only rebases that hunk; the patched code is unchanged.
  # It replaces the original in place, since 3002–3009 build on it. Drop the
  # local copy once nixos-hardware's linux-t2 patches catch up.
  ported3001 = {
    name = "3001-applesmc-convert-static-structures-to-drvdata.patch";
    patch = ./kernel-patches/3001-applesmc-convert-static-structures-to-drvdata.patch;
  };
  t2Kernel = t2Base.override (prev: {
    kernelPatches = map (p: if p.name == ported3001.name then ported3001 else p) prev.kernelPatches;
  });

  # systemd-shutdown hook for the reboot note below. systemd-shutdown runs each
  # executable in /etc/systemd/system-shutdown with its verb as $1, after the
  # final unmount pass and right before it either enters the shutdown ramfs or
  # calls reboot(2) (src/shutdown/shutdown.c, run()). On "reboot" with a kexec
  # image loaded, kexec instead. -x skips kexec-tools' interface teardown,
  # which systemd's own kexec() doesn't do either; kexec -e syncs first.
  # inRealRoot: hand off to
  # the shutdown ramfs copy when one is staged (the same check systemd uses for
  # can_exitrd), so the kexec happens after the ramfs unmounts the old root.
  kexecOnReboot =
    inRealRoot:
    pkgs.writeShellScript "kexec-on-reboot" ''
      [ "$1" = reboot ] || exit 0
      ${lib.optionalString inRealRoot "[ -x /run/initramfs/shutdown ] && exit 0"}
      [ "$(< /sys/kernel/kexec_loaded)" = 1 ] || exit 0
      echo "kexec-on-reboot: firmware reboots power this Mac off; kexec instead"
      exec ${pkgs.kexec-tools}/bin/kexec -e -x
    '';

  # Loads the boot default for the two kexec units in the reboot note below:
  # the same kexec --load as nixpkgs' prepare-kexec. --load replaces an image
  # that's already loaded in one syscall, so there's never a moment with
  # nothing loaded. On success, GC-root what's now loaded: an image left behind
  # by a failed reload must not point at a generation nix.gc has deleted.
  kexecLoadBootDefault = pkgs.writeShellScript "kexec-load-boot-default" ''
    set -e
    p=$(${pkgs.coreutils}/bin/readlink -f /nix/var/nix/profiles/system)
    if ! [[ -d $p ]]; then
      echo "no system profile at /nix/var/nix/profiles/system"
      exit 1
    fi
    ${pkgs.kexec-tools}/bin/kexec --load "$p/kernel" --initrd="$p/initrd" \
      --append="$(< "$p/kernel-params") init=$p/init"
    ${pkgs.coreutils}/bin/ln -sfn "$p" /nix/var/nix/gcroots/kexec-loaded
    echo "kexec image loaded: $p"
  '';
in
{
  # ── Apple T2 (MacBookPro16,1) ────────────────────────────────────────────
  # The nixos-hardware apple-t2 module supplies the T2 patch set (built above
  # against our own 6.18 kernel), the T2 audio profiles, and the kernel params
  # (intel_iommu=on, iommu=pt, pm_async=off). It also loads apple-bce
  # (keyboard/trackpad/Touch Bar/audio bridge) in initrd, which vista undoes:
  # see the BCE note below.
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

  # ── T2 BCE bridge: never load apple-bce ───────────────────────────────────
  # This is what reset vista every 5 days. 432000 s after the host boots, the
  # T2 removes its internal keyboard/trackpad (bce-vhci port 5). apple-bce
  # mishandles the removal ("bce-vhci: Possible desync, cmd cancel timed out")
  # and ~30 s later the T2 power-cycles the Mac. With apple-bce never loaded a
  # T2 Mac ran 10.7+ days: https://github.com/t2linux/kernel/issues/38
  #
  # Headless vista needs nothing behind the BCE: internal keyboard/trackpad,
  # Touch Bar, camera, T2 audio and the T2 bridge NIC all go with it. applesmc
  # (charge limit, battery guard) stays: it talks to the SMC over MMIO and
  # depends only on led-class, and apple-bce exports nothing for it to need.
  #
  # The first boot without the module must be a COLD power-on, not a kexec:
  # the T2's BCE state can carry across a kexec. The next 5-day reset
  # (2026-10-31 ~15:21 -03) is a cold boot, so it does the job.
  #
  # nixos-hardware still lists apple-bce in boot.initrd.kernelModules (a plain
  # list; dropping one entry would mean restating the rest in a mkForce), so
  # the .ko ships in the initrd and systemd-modules-load asks for it. The two
  # blacklists refuse it everywhere: the modprobe.d entry (also copied into the
  # initrd) covers udev's PCI-alias load and modules-load, which skips it as
  # "deny-listed (by kmod)"; module_blacklist= makes the kernel itself refuse
  # it, which modules-load also logs as deny-listed rather than failing
  # (src/shared/module-util.c). (A module of its own only because
  # boot.kernelParams is also set in the panel block below.)
  imports = [
    {
      boot.blacklistedKernelModules = [ "apple_bce" ];
      boot.kernelParams = [ "module_blacklist=apple_bce" ];
    }
  ];

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
  # See the panic-on-lockup sysctls below for the safety net.
  # The bridge is a USB device behind apple-bce, so with apple-bce gone (see
  # above) it no longer appears, and the July lockup was very likely the same
  # 5-day T2 event anyway. The rule is inert now; it stays in case apple-bce is
  # ever loaded again.
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
  # So keep a kexec image of the boot-default generation loaded at all times;
  # with one loaded, systemd turns a reboot into a kexec by itself. `reboot`,
  # `sudo reboot now`, `systemctl reboot` and `shutdown -r` all reach logind
  # asking for kexec (systemctl-logind.c logind_reboot(); shutdown -r picks
  # kexec at parse time, systemctl-compat-shutdown.c), and logind starts
  # kexec.target when an image is loaded (logind-dbus.c). That choice is made
  # at request time, so kexec-preload loads /nix/var/nix/profiles/system (the
  # boot default, as prepare-kexec would) at boot, retrying if it fails.
  # kexec-refresh then reloads it inside every kexec.target and reboot.target
  # transaction, so the image is current at reboot time: `nixos-rebuild boot`
  # + reboot comes up in the new generation just like `switch` + reboot. If
  # the refresh fails, whatever is loaded stays (GC-rooted, see
  # kexecLoadBootDefault): an older generation beats a firmware reboot. If
  # instead the boot-time load never succeeded, logind falls back to
  # reboot.target, which also runs kexec-refresh, and the hook below kexecs.
  #
  # Reboots that don't ask logind for kexec (`systemctl reboot -f`, starting
  # reboot.target, Ctrl-Alt-Del, a bare logind Reboot() D-Bus call) still end
  # in systemd-shutdown with verb "reboot"; the kexec-on-reboot hook (top of
  # file) kexecs there instead. It runs from NixOS's shutdown ramfs, after that
  # stage's unmount pass over the old root, and from the real root only when
  # no ramfs was staged (`-f` skips the unit that builds it).
  #
  # Caveats:
  #   • `reboot -f`, `reboot -ff` and `systemctl reboot -ff` call reboot(2)
  #     directly (systemctl-util.c halt_now()), skipping systemd-shutdown, so
  #     nothing can catch them: they power vista off. So do SysRq-b and the
  #     panic reboot (kernel.panic below).
  #   • `poweroff` / `shutdown -h` are unaffected and correct (a clean power-off
  #     is fine). It's only *reboot* that the firmware mishandles.
  #   • `nixos-rebuild test` doesn't touch the boot default, so a reboot after
  #     it boots the default, same as a firmware boot would.
  #   • A kexec image loaded by hand (`kexec -l`) is replaced by kexec-refresh
  #     on the way down; boot it with `systemctl kexec -f` or `kexec -e`.
  systemd.services.kexec-preload = {
    description = "Load the boot-default generation for kexec reboots";
    wantedBy = [ "multi-user.target" ];
    # Bounded retries: 5 starts in 10 min, 30 s apart.
    startLimitIntervalSec = 600;
    startLimitBurst = 5;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = kexecLoadBootDefault;
      Restart = "on-failure";
      RestartSec = 30;
      # A hung load mustn't stall multi-user.target or nixos-rebuild switch.
      TimeoutStartSec = "2min";
    };
  };
  # Runs ahead of prepare-kexec (which then sees an image and skips) and of the
  # final systemd-kexec/systemd-reboot step. "-" ignores a failed load, so the
  # reboot goes on with whatever was loaded.
  systemd.services.kexec-refresh = {
    description = "Reload the boot-default generation for kexec before rebooting";
    wantedBy = [
      "kexec.target"
      "reboot.target"
    ];
    before = [
      "prepare-kexec.service"
      "systemd-kexec.service"
      "systemd-reboot.service"
    ];
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = [
        "/nix/store"
        "/nix/var/nix"
      ];
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${kexecLoadBootDefault}";
      TimeoutStartSec = "1min";
    };
  };
  systemd.shutdown.kexec-on-reboot = kexecOnReboot true;
  systemd.shutdownRamfs.contents."/etc/systemd/system-shutdown/kexec-on-reboot".source =
    kexecOnReboot false;
  systemd.shutdownRamfs.storePaths = [ "${pkgs.kexec-tools}/bin/kexec" ];

  # 2) Belt-and-suspenders: force both backlights (main gmux panel + the OLED
  #    Touch Bar) to zero at boot, in case the PWM rail stays powered even with
  #    the connector disabled. Writes defensively — the sysfs nodes may not
  #    exist once the panel is off, so failures are ignored. appletb_backlight
  #    only exists with apple-bce loaded, so it's always skipped now; the
  #    Touch Bar is left with no host driver at all.
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

      set_limit() { # sustained watts, burst watts
        echo $(( $1 * 1000000 )) > $rapl/constraint_0_power_limit_uw
        echo $(( $2 * 1000000 )) > $rapl/constraint_1_power_limit_uw
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
        # In guard the burst limit equals the sustained one. PL1 is a ~28 s
        # average, so after a lull any PL2 above it lets a new build run well
        # past the limit for most of a 15 s window (seen: 82 W against a 55 W
        # limit); that read as a deficit, got cut to 22 W, and left the CPU
        # underfed for a minute and a half while the limit climbed back.
        if [ $mode = boost ]; then set_limit 100 125; else set_limit $limit $limit; fi

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

  # ── Charge limit: stop at 80% ─────────────────────────────────────────────
  # vista never leaves AC, so the battery would otherwise sit at 100% around
  # the clock — the state that wears lithium cells fastest. BCLM is the SMC's
  # own charge ceiling, which linux-t2's applesmc exposes as
  # battery_charge_limit; set it whenever the driver binds so neither a reboot
  # nor an SMC reset can quietly put it back to 100. 80% is still far above
  # the battery guard's 35% boost threshold.
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="acpi", DRIVER=="applesmc", ATTR{battery_charge_limit}="80"
  '';

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
      volume."/mnt/btrfs-root" = {
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
