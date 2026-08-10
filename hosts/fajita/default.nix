{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../../modules/gnome-mobile.nix
    ./secrets.nix
    ./audio.nix
    ./clocks-alarm.nix
    ./pwas.nix
    ./sensors.nix
    ./cursor.nix   # hide the phantom mouse pointer on this touch-only device
    ./camera.nix   # camera bring-up (tools/tuning/AF) — see CAMERA_PLAN.md
    ./theme.nix    # Marble GNOME Shell theme (accent + dark/light defined there)
    ./quick-settings.nix # declarative Android-style quick-settings layout/actions
    ./waydroid.nix # Waydroid on-demand app layer — see ~/fajita-notes/waydroid-apps.md
  ];

  # Four logical columns. The first two rows mirror Android's compact phone
  # layout; later rows hold less frequently used actions.
  # Omitted built-ins are not inserted, which intentionally removes Power Mode
  # and Dark Style without disabling their underlying services/settings.
  fajita.quickSettings = {
    enable = true;
    columns = 4;
    rows = 5;
    collapsedRows = 2;
    tiles = [
      {
        id = "wifi";
        span = 1;
      }
      {
        id = "bluetooth";
        span = 1;
      }
      {
        id = "do-not-disturb";
        span = 1;
        longPressDesktopId = "gnome-notifications-panel.desktop";
      }
      {
        id = "flashlight";
        span = 1;
      }
      {
        id = "hotspot";
        span = 1;
        longPressDesktopId = "gnome-wifi-panel.desktop";
      }
      {
        id = "bitwarden";
        type = "application";
        span = 1;
        title = "Bitwarden";
        iconName = "security-high-symbolic";
        desktopId = "io.matv.Warden.desktop";
      }
      {
        id = "calculator";
        type = "application";
        span = 1;
        title = "Calculator";
        iconName = "accessories-calculator-symbolic";
        desktopId = "io.matv.Calculator.desktop";
      }
      {
        id = "auto-rotate";
        span = 1;
        longPressDesktopId = "gnome-display-panel.desktop";
      }
      {
        id = "mobile-data";
        span = 1;
        persistent = true;
      }
      {
        id = "airplane-mode";
        span = 1;
      }
      {
        id = "mousai";
        type = "application";
        span = 1;
        title = "Mousai";
        iconName = "audio-x-generic-symbolic";
        desktopId = "io.github.seadve.Mousai.desktop";
      }
      {
        id = "screen-record";
        type = "shell";
        span = 1;
        title = "Screen Record";
        iconName = "camera-video-symbolic";
        action = "screen-record";
      }
      {
        id = "authenticator";
        type = "application";
        span = 1;
        title = "Authenticator";
        iconName = "dialog-password-symbolic";
        desktopId = "com.belmoussaoui.Authenticator.desktop";
      }
    ];
  };

  networking.hostName = "fajita";

  # GNOME Shell Mobile session lives in ../../modules/gnome-mobile.nix (GDM +
  # desktopManager.gnome + the mobile overlay). Display scale is handled by
  # GNOME/Mutter fractional scaling, not Phosh's phoc.ini. Notch coverage is
  # gmobile's job under GNOME (oneplus,fajita cutout JSON), not a scale hack.
  services.displayManager.autoLogin = {
    enable = true;
    user = "daniel";
  };

  programs.calls.enable = true;       # telephony UI (GNOME Calls)
  hardware.sensor.iio.enable = true;  # iio-sensor-proxy → rotation/ALS

  # KERNEL: sdm845-mainline curated tree (what pmOS ships) instead of the
  # mwlaboratories linux-next snapshot. Fixes mic capture (Q6/SLIMbus TX was
  # digital-silence on 6.19-next) and adds the tfa9894 loudspeaker DT node
  # (upstream /delete-node/s it). See packages/fajita-kernel/default.nix.
  # NOTE: kernel changes need a boot.img REFLASH, not just s-t-c boot.
  # (mkForce: the sdm845-mainline family module pins its kernel at normal priority.)
  mobile.boot.stage-1.kernel.package = lib.mkForce (pkgs.callPackage ../../packages/fajita-kernel { });

  # Pull in linux-firmware so the kernel can load /lib/firmware/qcom/a630_sqe.fw
  # and friends. Without this, GPU init fails (-2 ENOENT) and Phosh can't start
  # because Wayland/DRM has no working renderer.
  hardware.enableRedistributableFirmware = true;

  # CRITICAL FIRMWARE PATH FIX:
  # Codeberg sdm845/linux kernel hardcodes `firmware-name = "qcom/sdm845/OnePlus/
  # enchilada/<svc>.mbn"` in sdm845-oneplus-common.dtsi. BUT firmware-oneplus-sdm845
  # ships at qcom/sdm845/oneplus6/. Path mismatch → DSP firmware ENOENT → pd-mapper
  # exits → MSS never boots → no wlan0. Solution: copy (NOT symlink) the firmware
  # files at the kernel-expected paths. Symlinks across packages get broken by
  # nixpkgs's compress-firmware logic — actual files survive intact.
  hardware.firmware = [
    config.mobile.device.firmware
    (pkgs.runCommand "fajita-firmware-pathremap" { } ''
      # DSP/modem/IPA: copy oneplus6/* → OnePlus/enchilada/*
      mkdir -p $out/lib/firmware/qcom/sdm845/OnePlus/enchilada
      cp -rL ${config.mobile.device.firmware}/lib/firmware/qcom/sdm845/oneplus6/* \
             $out/lib/firmware/qcom/sdm845/OnePlus/enchilada/
      # Bluetooth NV
      mkdir -p $out/lib/firmware/qca/OnePlus/enchilada
      if [ -f ${config.mobile.device.firmware}/lib/firmware/qca/oneplus6/crnv21.bin ]; then
        cp -L ${config.mobile.device.firmware}/lib/firmware/qca/oneplus6/crnv21.bin \
              $out/lib/firmware/qca/OnePlus/enchilada/crnv21.bin
      fi
      # GPU SQE + GMU — copy to every path the kernel might check
      for d in qcom/sdm845/OnePlus6 qcom/sdm845/OnePlus/enchilada qcom/sdm845/oneplus6; do
        mkdir -p $out/lib/firmware/$d
        cp -L ${pkgs.linux-firmware}/lib/firmware/qcom/a630_sqe.fw  $out/lib/firmware/$d/a630_sqe.bin
        cp -L ${pkgs.linux-firmware}/lib/firmware/qcom/a630_sqe.fw  $out/lib/firmware/$d/a630_sqe.fw
        cp -L ${pkgs.linux-firmware}/lib/firmware/qcom/a630_gmu.bin $out/lib/firmware/$d/a630_gmu.bin
      done
    '')
  ];

  # Disable firmware compression. Belt-and-suspenders for the broken-symlink bug,
  # AND lets pd-mapper / tqftpserv / hexagonrpcd read files raw via POSIX open()
  # without depending on the kernel-side decompressor.
  hardware.firmwareCompression = "none";

  # GPU init runs during stage-1 (around boot time 2.5s) — before userspace
  # sets firmware_class.path to the runtime firmware tree. The family module's
  # stage-1 firmware only contains the oneplus6/ paths, so the kernel can't find
  # a630_zap.mbn at the path the DT requests (OnePlus/enchilada/). Result: GPU
  # hw init fails, no DRM rendering, Phosh starts but screen stays black.
  # Add the OnePlus/enchilada paths into stage-1 too.
  mobile.boot.stage-1.firmware = [
    (pkgs.runCommand "fajita-stage1-firmware-pathremap" { } ''
      mkdir -p $out/lib/firmware/qcom/sdm845/OnePlus/enchilada
      cp -L ${config.mobile.device.firmware}/lib/firmware/qcom/sdm845/oneplus6/a630_zap.mbn \
            $out/lib/firmware/qcom/sdm845/OnePlus/enchilada/a630_zap.mbn
      cp -L ${pkgs.linux-firmware}/lib/firmware/qcom/a630_sqe.fw  $out/lib/firmware/qcom/sdm845/OnePlus/enchilada/a630_sqe.bin
      cp -L ${pkgs.linux-firmware}/lib/firmware/qcom/a630_sqe.fw  $out/lib/firmware/qcom/sdm845/OnePlus/enchilada/a630_sqe.fw
      cp -L ${pkgs.linux-firmware}/lib/firmware/qcom/a630_gmu.bin $out/lib/firmware/qcom/sdm845/OnePlus/enchilada/a630_gmu.bin
    '')
  ];

  # Also switch to graphical.target now that we have ssh recovery. If Phosh
  # bootloops we ssh in and `systemctl stop phosh`.
  systemd.defaultUnit = lib.mkForce "graphical.target";

  # Belt-and-suspenders: explicitly enable the SDM845 modem quirk. The family
  # module sets it, but make it explicit so we're not surprised by mkDefault
  # ordering. This wires qrtr-ns + rmtfs + tqftpserv + pd-mapper systemd units
  # AND creates the uncompressed-firmware-share at /run/current-system/sw/share/
  # that pd-mapper reads from (pd-mapper is patched to read there, not /lib/firmware).
  mobile.quirks.qualcomm.sdm845-modem.enable = true;

  # THE CRASHDUMP-ON-REBOOT FIX (pmOS pmaports MR !6956 / issue #3936): on
  # shutdown, if rmtfs dies before NetworkManager has torn down wifi, the
  # WCN3990 firmware crashes when its shared memory vanishes → hypervisor →
  # Qualcomm CrashDump mode → every reboot needs a force-off. Ordering rmtfs
  # Before=NetworkManager.service makes systemd stop it AFTER NetworkManager
  # on the way down. Pure userspace fix; pmOS ships exactly this.
  systemd.services.rmtfs.before = [ "NetworkManager.service" ];

  # SDM845 needs --test-quick-suspend-resume on ModemManager. Without it, MM
  # loses the modem on its first suspend probe and never recovers.
  systemd.services.ModemManager.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${pkgs.modemmanager}/bin/ModemManager --test-quick-suspend-resume"
  ];

  # Don't let NetworkManager grab the USB-OTG gadget interface — Phosh's net
  # check gets confused, and we want gadget for ssh-over-USB anyway.
  networking.networkmanager.unmanaged = [ "rndis0" "usb0" ];

  # Silent boot + splash so the phone looks like a phone, not a server
  mobile.beautification = {
    silentBoot = lib.mkDefault true;
    splash = lib.mkDefault true;
  };

  # …but make the splash actually END. gdm-mobile never does the plymouth
  # handoff, so plymouthd stays alive in --mode=boot forever (2026-07-18
  # battery audit: 2.5% CPU + 2:48 CPU-time six hours after boot, plus the
  # ask-password forwarders). Tell it to quit once the display manager is up.
  systemd.services.fajita-plymouth-quit = {
    description = "Quit the Plymouth boot splash after the session takes over";
    wantedBy = [ "graphical.target" ];
    after = [ "display-manager.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${pkgs.plymouth}/bin/plymouth quit";
    };
  };

  # NetworkManager periodic connectivity probes are useless on a phone that is
  # basically always online via WiFi/LTE — be explicit that they're off so
  # they never wake the modem for a captive-portal check.
  networking.networkmanager.settings.connectivity.enabled = false;

  # Networking — NetworkManager (iwd backend was getting confused; just use wpa_supplicant default)
  networking.networkmanager.enable = true;
  networking.networkmanager.ensureProfiles.profiles = {
    # Claro Argentina cellular data. Modern APN is `igprs.claro.com.ar` with
    # empty user/pass — the older `internet.ctimovil.com.ar` with `clarogprs`
    # credentials is legacy and doesn't authenticate on newer SIMs. ModemManager
    # picks this up via mobile-broadband-provider-info matching MCC/MNC, but
    # giving NM an explicit profile means data activates as soon as the SIM
    # registers, no UI poking required.
    claro-ar = {
      connection = {
        id = "claro-ar";
        type = "gsm";
        autoconnect = true;
        autoconnect-priority = 50;
      };
      gsm = {
        apn = "igprs.claro.com.ar";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };

  # Auto-login on tty1 as daniel. Lets us drop into a shell without typing if
  # we lose network and need to debug via screen + USB-OTG keyboard.
  services.getty.autologinUser = "daniel";

  # SSH — Tailscale-only after enrollment. `trustedInterfaces = [ "tailscale0" ]`
  # below lets Tailscale traffic bypass the firewall; openFirewall=false keeps
  # port 22 closed on every other interface (WiFi/USB/cellular).
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Bluetooth: QCA WCN3990 (UART-attached). Phosh Settings → Bluetooth panel
  # handles pairing UI. PipeWire is enabled upstream by the phosh module; we
  # just need bluez + wireplumber's bluez monitor wired up so headsets show as
  # PipeWire sinks/sources.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      Experimental = true;     # battery reporting, LE audio
      FastConnectable = true;
    };
  };
  services.pipewire.wireplumber.extraConfig.bluez = {
    "monitor.bluez.properties" = {
      "bluez5.enable-sbc-xq" = true;        # higher-bitrate SBC variant
      "bluez5.enable-msbc" = true;          # wideband speech for HFP calls
      "bluez5.enable-hw-volume" = true;     # let the headset handle volume
      "bluez5.roles" = [
        "hsp_hs" "hsp_ag"
        "hfp_hf" "hfp_ag"
        "a2dp_sink" "a2dp_source"
      ];
    };
  };

  # WCN3990 ships a placeholder BD address in firmware → kernel sets
  # HCI_QUIRK_INVALID_BDADDR → BlueZ refuses to bring hci0 up (EOPNOTSUPP on
  # `hciconfig up`). Same problem pmOS solves with `bootmac`. We set a FIXED
  # address via `btmgmt --index 0 public-addr` before bluetooth.service
  # registers the controller. It must be CONSTANT: BlueZ keys the pairing
  # store (/var/lib/bluetooth/<controller-mac>/) by it, so a changing address
  # "forgets" all paired devices on reboot. The old wlan0-derived scheme did
  # exactly that (wlan0's MAC is itself a placeholder and often not up yet →
  # random fallback; 21 stale controller dirs accumulated by 2026-07-14).
  # The constant below = the controller address of the 2026-07-14 boot, so
  # pairings made that day carry forward.
  systemd.services.bluetooth-mac-fajita = {
    description = "Set BT public address (WCN3990 ships placeholder BDADDR)";
    wantedBy = [ "bluetooth.service" ];
    before = [ "bluetooth.service" ];
    after = [ "sys-subsystem-bluetooth-devices-hci0.device" ];
    bindsTo = [ "sys-subsystem-bluetooth-devices-hci0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "set-bt-mac" ''
        set -eu
        for i in $(seq 1 20); do
          ${pkgs.bluez}/bin/btmgmt extinfo 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'hci0' && break
          ${pkgs.coreutils}/bin/sleep 0.5
        done
        echo "Setting hci0 public address to 4A:F2:A2:D6:D8:8D (fixed; see comment)"
        ${pkgs.bluez}/bin/btmgmt --index 0 public-addr "4A:F2:A2:D6:D8:8D"
      '';
    };
  };

  # Alert slider (3-state side switch) → feedbackd Profile.
  # Mainline kernel exposes /dev/input/event1 ("Alert slider") emitting
  # EV_ABS / ABS_SND_PROFILE (code 0x22) with values:
  #   0 = silent (top)
  #   1 = vibrate (middle)
  #   2 = ring (bottom)
  # We read the event stream and set org.sigxcpu.Feedback.Profile via gdbus
  # on the session bus. User-scoped because feedbackd is session-scoped.
  systemd.user.services.alert-slider-handler = {
    description = "OnePlus 6T alert slider → feedbackd profile";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "phosh.service" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 2;
      ExecStart = pkgs.writeShellScript "alert-slider-handler" ''
        set -eu
        DEV=/dev/input/event1
        # input_event on aarch64: 16-byte timeval + u16 type + u16 code + s32 value = 24 bytes.
        # od -tu2 -w24 prints one event per line; we want EV_ABS (type=3) + ABS_SND_PROFILE (code=34).
        exec ${pkgs.coreutils}/bin/stdbuf -oL \
          ${pkgs.coreutils}/bin/od -An -tu2 -w24 -v "$DEV" | \
        while read -r _ _ _ _ _ _ _ _ type code vlo vhi _; do
          [ "$type" = 3 ] && [ "$code" = 34 ] || continue
          val=$(( (vhi << 16) | vlo ))
          case "$val" in
            0) prof=silent ;;
            1) prof=quiet  ;;
            2) prof=full   ;;
            *) continue ;;
          esac
          ${pkgs.glib}/bin/gdbus call --session \
            --dest org.sigxcpu.Feedback \
            --object-path /org/sigxcpu/Feedback \
            --method org.freedesktop.DBus.Properties.Set \
            org.sigxcpu.Feedback Profile "<'$prof'>" >/dev/null || true
        done
      '';
    };
  };

  # Sensors phase 1: mount the persist partition so hexagonrpcd-sdsp can serve
  # the SLPI sensor registry to the DSP. Without this mount, SLPI starts but
  # never publishes QMI SNS_CLIENT_SVC → no IIO devices appear → iio-sensor-proxy
  # gives up → no auto-rotation, no proximity-off-during-call.
  # /dev/disk/by-partlabel/persist (= /dev/sda2) is ext4 and holds the factory
  # sensor calibration: BMI160 accel/gyro, AK0991x mag, APDS9251 ALS/prox.
  # Phase 2 (packaging libssc + patched iio-sensor-proxy to consume QMI) is
  # tracked separately — this mount is the prerequisite.
  fileSystems."/mnt/vendor/persist" = {
    device = "/dev/disk/by-partlabel/persist";
    fsType = "ext4";
    options = [ "ro" "nosuid" "nodev" "noexec" "nofail" ];
  };

  # SDM845 mainline has a broken s2idle path — the phone goes to sleep fine
  # but never wakes from it. Disable all sleep/suspend until that's fixed.
  # Effects: no auto-suspend, ignore lid/power-key suspend, ignore idle action.
  services.logind.settings.Login = {
    IdleAction = "ignore";
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    HandleLidSwitch = "ignore";
  };
  # swclock-offset: stash the wall clock at shutdown, restore it at boot before
  # NTP catches up. Without this, the phone's first-boot clock reads 1970
  # (the SDM845 RTC drifts hard between power cycles) — every cert validation,
  # GPG check, and journal timestamp until NTP syncs reads as 56 years ago.
  # Port of pmOS's swclock-offset; tiny shell scripts wrapped in two units.
  systemd.services.swclock-offset-restore = {
    description = "Restore wall clock from last saved timestamp";
    wantedBy = [ "time-sync.target" ];
    before = [ "time-sync.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "swclock-restore" ''
        f=/var/lib/swclock-offset/last
        [ -r "$f" ] || exit 0
        saved=$(${pkgs.coreutils}/bin/cat "$f")
        now=$(${pkgs.coreutils}/bin/date +%s)
        if [ "$saved" -gt "$now" ]; then
          echo "swclock-offset: restoring time $saved (was $now)"
          ${pkgs.coreutils}/bin/date -s "@$saved" >/dev/null
        fi
      '';
    };
  };
  systemd.services.swclock-offset-save = {
    description = "Save wall clock so the next boot has a sane time";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true"; # save happens at stop
      ExecStop = pkgs.writeShellScript "swclock-save" ''
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/swclock-offset
        ${pkgs.coreutils}/bin/date +%s > /var/lib/swclock-offset/last
      '';
    };
  };

  # Avahi/mDNS — discover .local hosts (harbor.local, mantle.local, printers,
  # Chromecasts, etc.) from the phone and let the phone be discoverable too.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    # Publish disabled 2026-07-19 (battery pass): ssh reaches the phone over
    # Tailscale MagicDNS, and nothing discovers the phone by mDNS — announcing
    # ourselves periodically only chatters the WiFi radio. Resolving OTHER
    # hosts (harbor.local, Chromecasts) still works via nssmdns above.
    publish.enable = false;
  };

  # CUPS — disabled 2026-07-19 (battery pass): printing from the phone was
  # never used (print shop + USB instead). Flip enable back on if ever needed;
  # the drivers line is kept for that day.
  services.printing = {
    enable = false;
    drivers = with pkgs; [ gutenprint hplip ];
  };

  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # NOTE: the old `pwrkey-wake-watcher` (phoc/wlr-randr DPMS-off workaround) was
  # removed in the Phosh→GNOME migration — Mutter is not a wlroots compositor and
  # does not implement wlr-output-power-management, so wlr-randr can't drive it.
  # Power-button display wake is now Mutter's responsibility (gsd-power +
  # logind). If the SDM845 DPMS-off-wake bug recurs under GNOME, the fix will be
  # Mutter/gnome-shell-side (a contribution target), not a wlr-randr poke.

  # Tailscale — off-WiFi SSH access. After first boot:
  #   sudo tailscale up --login-server=https://headscale.matv.io --accept-routes
  # to enroll. (sops-nix auth key bootstrap deferred — manual once is fine.)
  services.tailscale = {
    enable = true;
    extraUpFlags = [
      "--accept-routes"
      "--hostname=fajita"
    ];
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  systemd.services.tailscaled.restartIfChanged = false;

  # USB gadget (CDC-NCM) for ssh-over-USB from mantle. mobile-nixos sets up
  # the gadget in stage-1 initramfs but doesn't carry it across switch_root —
  # if no cable is plugged at boot the UDC never binds, and there's no
  # stage-2 service to re-bind on hot-plug. This service owns the gadget at
  # runtime. NCM (modern CDC class) instead of RNDIS for the Linux host.
  boot.kernelModules = [ "libcomposite" "usb_f_ncm" ];

  # Switch msm/drm from legacy MDP5 to modern DPU display driver. SDM845 still
  # defaults to MDP5 in mainline (`msm.prefer_mdp5=Y`) for historical reasons.
  # DPU has bandwidth scaling, proper DSI-cmd vblank handling, and active dev
  # attention; MDP5 is in maintenance mode. This pairs with the GPU min_freq
  # udev pin for the smoothest Phosh animation we can squeeze out of this kernel.
  # Refs: LWN 957064 (migration path), dri-devel discussion of prefer_mdp5.
  boot.kernelParams = [ "msm.prefer_mdp5=0" ];

  systemd.services.usb-gadget = {
    description = "USB gadget (CDC-NCM) for ssh-over-USB";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-kernel-config.mount" "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "usb-gadget-up" ''
        set -eu
        G=/sys/kernel/config/usb_gadget/g1
        # If stage-1 already built g1, tear it down so we own it cleanly.
        if [ -d "$G" ]; then
          echo "" > "$G/UDC" 2>/dev/null || true
          for l in "$G"/configs/*/ncm.usb0 "$G"/configs/*/rndis.usb0; do
            [ -e "$l" ] && rm -f "$l" || true
          done
          rmdir "$G"/configs/*/strings/* 2>/dev/null || true
          rmdir "$G"/configs/* 2>/dev/null || true
          rmdir "$G"/functions/* 2>/dev/null || true
          rmdir "$G"/strings/* 2>/dev/null || true
          rmdir "$G" || true
        fi
        mkdir -p "$G"
        echo 0x18d1 > "$G/idVendor"      # Google (works with cdc_ncm host)
        echo 0xd001 > "$G/idProduct"
        echo 0x0200 > "$G/bcdUSB"
        echo 0x0100 > "$G/bcdDevice"
        mkdir -p "$G/strings/0x409"
        echo "Mobile NixOS"        > "$G/strings/0x409/manufacturer"
        echo "OnePlus 6T (fajita)" > "$G/strings/0x409/product"
        echo "fajita-0001"         > "$G/strings/0x409/serialnumber"
        mkdir -p "$G/configs/c.1/strings/0x409"
        echo "NCM" > "$G/configs/c.1/strings/0x409/configuration"
        echo 250 > "$G/configs/c.1/MaxPower"
        mkdir -p "$G/functions/ncm.usb0"
        # Stable MACs (locally-administered, bit 0x02 set in first octet).
        echo "02:22:82:ff:ff:11" > "$G/functions/ncm.usb0/dev_addr"   # phone-side
        echo "02:22:82:ff:ff:22" > "$G/functions/ncm.usb0/host_addr"  # mantle-side
        ln -s "$G/functions/ncm.usb0" "$G/configs/c.1/ncm.usb0"
        # Bind to the SDM845 UDC. Fails with -ENODEV if no cable; that's fine.
        UDC=$(ls /sys/class/udc | head -n1)
        echo "$UDC" > "$G/UDC" || true
      '';
      ExecStop = pkgs.writeShellScript "usb-gadget-down" ''
        G=/sys/kernel/config/usb_gadget/g1
        [ -d "$G" ] && echo "" > "$G/UDC" || true
      '';
    };
  };

  # Phone-side static IP on usb0. systemd-networkd brings it up regardless
  # of cable state so the IP is ready the instant mantle plugs in.
  systemd.network.enable = true;
  systemd.network.networks."10-usb0" = {
    matchConfig.Name = "usb0";
    networkConfig = {
      Address = "172.16.42.1/24";
      ConfigureWithoutCarrier = true;
      IPv6AcceptRA = false;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Reboot watchdog — systemd defaults to RebootWatchdogSec=10min, which arms
  # the kernel hardware watchdog right before issuing the final reset. The
  # SDM845 qcom_wdt's bark/bite registers cap the timeout far below 10min
  # (typically ~127s), so systemd-shutdown logs:
  #   "Failed to set watchdog hardware timeout to 10min: Invalid argument"
  # leaving the wdog in a half-armed state. The SoC then resets via WDOG_BARK,
  # the OnePlus bootloader sees a watchdog-caused reset on the previous boot,
  # and falls into Qualcomm Crashdump Mode instead of booting the next slot.
  # Disable the reboot-time watchdog entirely; the slot-good mark below already
  # gives us A/B rollback protection without needing the hardware wdog.
  # Refs: pmaports #2440 (SDM845 crashdump on reset), mobile-nixos sdm845 notes.
  systemd.settings.Manager = {
    RebootWatchdogSec = 0;
    ShutdownWatchdogSec = 0; # alias retained by systemd for older configs
  };

  # Slot-confirm — without this, the OnePlus A/B bootloader rolls back to the
  # previous slot after 2 unsuccessful boots. Reaching multi-user.target is
  # our "boot was good" signal; mark it so we don't get reverted.
  systemd.services.qbootctl-mark-slot-good = {
    description = "Mark current A/B slot as successfully booted";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.qbootctl}/bin/qbootctl -m";
      RemainAfterExit = true;
    };
  };

  # q6voiced — opens the QDSP6 voice PCM stream when ModemManager/oFono signals
  # an active call. Without it, calls connect but no audio routes through the DSP.
  # Card 0 device 6 is the VoiceMMode1 DAI link on sdm845-mainline OnePlus 6/6T
  # (verify post-boot with `alsactl info` if the daemon errors out).
  systemd.services.q6voiced = {
    description = "QDSP6 voice call audio bridge";
    wantedBy = [ "multi-user.target" ];
    after = [ "dbus.service" ];
    requires = [ "dbus.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.q6voiced}/bin/q6voiced hw:0,6";
      Restart = "always";
      RestartSec = "2";
    };
  };

  # hexagonrpcd — sensor DSP bridge. SDM845's accel/gyro/proximity/ALS are
  # exposed via SLPI (Sensor Low-Power Island), not i2c. Without this daemon,
  # iio-sensor-proxy gets nothing → no auto-rotate, no proximity-off-during-call,
  # no auto-brightness. The -sdsp unit has ConditionPathExists=/dev/fastrpc-sdsp
  # so it's a no-op on devices without sdsp (safe to enable broadly).
  users.users.fastrpc = {
    isSystemUser = true;
    group = "fastrpc";
    description = "hexagonrpcd FastRPC bridge user";
  };
  users.groups.fastrpc = { };
  # Register hexagonrpc's systemd units (the package ships them but nothing
  # else wires them). stevia (Phosh's OSK) was dropped in the GNOME migration —
  # GNOME Shell has its own built-in OSK.
  systemd.packages = [
    pkgs.hexagonrpc
  ];
  systemd.services.hexagonrpcd-sdsp = {
    wantedBy = [ "multi-user.target" ];
    # Persist mount provides the SLPI sensor registry the daemon serves.
    after = [ "mnt-vendor-persist.mount" ];
    requires = [ "mnt-vendor-persist.mount" ];
  };

  # pmOS-defaults bundle. These are the "just works on pmOS" pieces — udev
  # rules + mimeapps + udiskie autostart — that postmarketos-base-ui /
  # postmarketos-ui-phosh / postmarketos-base-ui-gnome-mobile package up but
  # Mobile NixOS doesn't.
  #
  # 1) Volume keys must NOT wake the device (pmOS 20-volume-keys-input.rules).
  #    Without this, every volume press fires a wakeup and Phosh sees a
  #    hardware-keyboard capability event.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ENV{GM_WAKEUP_KEY_114}="0", ENV{GM_WAKEUP_KEY_115}="0"

    # SDM845 display smoothness fix. Adreno 630 has 7 DCVS bins:
    # 257, 342, 414, 520, 596, 675, 710 MHz. Mainline msm/drm uses
    # `simple_ondemand` devfreq governor (50ms polling). It cannot ramp
    # within Phosh's 16ms frame budget — by the time it decides to step up,
    # the animation is over. Result: GPU stuck at min (257 MHz) during
    # interactions → choppy animations.
    #
    # The downstream `msm-adreno-tz` governor (used in pmOS on KGSL) reads
    # GPU busy% per-frame and ramps within the frame. It does not exist on
    # mainline msm/drm. Until upstream lands a Mesa-driven dynamic clocking
    # RFC, the workaround is to pin min_freq to a high bin (675 MHz = 2nd
    # highest). Live-tested smoothness boost is significant. Battery hit is
    # acceptable for a hacking phone; if it bites in practice, drop to
    # 520 MHz (still much smoother than the default 257).
    SUBSYSTEM=="devfreq", KERNEL=="5000000.gpu", ATTR{min_freq}="675000000", ATTR{polling_interval}="16"

    # FastRPC permissions for hexagonrpcd (sensor DSP bridge). Default
    # /dev/fastrpc-{adsp,sdsp,cdsp,sdsp_secure} are root-only → hexagonrpcd
    # service (user=fastrpc) loops on EACCES → no sensor data → no
    # auto-rotate, no auto-brightness, no proximity-off-during-call.
    KERNEL=="fastrpc-adsp",        GROUP="fastrpc", MODE="0660"
    KERNEL=="fastrpc-sdsp",        GROUP="fastrpc", MODE="0660"
    KERNEL=="fastrpc-cdsp",        GROUP="fastrpc", MODE="0660"
    KERNEL=="fastrpc-sdsp_secure", GROUP="fastrpc", MODE="0660"
  '';
  # 2) System mimeapps — tel: / sms: / http: defaults so Phosh launchers route
  #    to the right apps (Calls, Chatty, Epiphany).
  environment.etc."xdg/mimeapps.list".text = ''
    [Default Applications]
    x-scheme-handler/http=org.gnome.Epiphany.desktop
    x-scheme-handler/https=org.gnome.Epiphany.desktop
    text/html=org.gnome.Epiphany.desktop
    x-scheme-handler/tel=org.gnome.Calls.desktop
    x-scheme-handler/sms=sm.puri.Chatty.desktop
    image/png=org.gnome.Loupe.desktop
    image/jpeg=org.gnome.Loupe.desktop
    image/gif=org.gnome.Loupe.desktop
    image/svg+xml=org.gnome.Loupe.desktop
  '';
  # 3) Mobile-Qt env hints — for any Qt apps installed later, default to
  #    wayland + mobile controls + no decoration (pmOS base-ui /etc/profile.d).
  environment.sessionVariables = {
    QT_QUICK_CONTROLS_MOBILE = "true";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_QPA_PLATFORM = "wayland";
    MOZ_ENABLE_WAYLAND = "1";
    MOZ_GTK_TITLEBAR_DECORATION = "client"; # Phosh swipe-from-top works on CSD
    SDL_VIDEODRIVER = "wayland";
    # OSK keyboard fork switches (read by our patched ibus-typing-booster at
    # startup; ibus-daemon inherits the session env). Set to "0" + ibus
    # restart to fall back to stock engine behavior.
    IBUS_TYPING_BOOSTER_OSK_NO_PREEDIT = "1"; # commit chars directly, no underlined preedit
    IBUS_TYPING_BOOSTER_OSK_AUTOCORRECT = "1"; # auto-fix OOV words on space/punct, learn on re-type
    IBUS_TYPING_BOOSTER_OSK_GESTURE = "1";    # swipe-typing decoder (rev 10 engine half)
    # Spatial autocorrect (rev 11 engine half — tap-coordinate rescoring against the
    # AOSP frequency DBs). Kill switch: set to "0"/unset + restart ibus to fall back
    # to the string-only legacy autocorrect. See packages/aosp-freq-dict.
    IBUS_TYPING_BOOSTER_OSK_SPATIAL = "1";
    # Colon-separated read-only AOSP freq DBs (en_US + es-with-voseo) the spatial
    # rescorer reads as a frequency prior. Unset = spatial-only / legacy fallback.
    IBUS_TYPING_BOOSTER_REFERENCE_DB =
      "${pkgs.callPackage ../../packages/aosp-freq-dict { }}/share/aosp-freq-dict/en_US.db:${pkgs.callPackage ../../packages/aosp-freq-dict { }}/share/aosp-freq-dict/es.db";
  };
  # NB: do NOT set GTK_IM_MODULE here. GNOME Shell speaks to IBus over its own
  # D-Bus API; setting GTK_IM_MODULE/QT_IM_MODULE/XMODIFIERS breaks the built-in
  # OSK auto-show. The gnome-mobile module actively unsets them in
  # environment.extraInit. (This is the exact inverse of the Phosh setup, which
  # needed GTK_IM_MODULE=wayland for stevia.)

  # OSK text prediction + cursor slide + auto-caps (rev 9 — ~/fajita-notes/keyboard-prediction.md).
  # The shell OSK has a 3-slot suggestion strip since GNOME 43 (keyboard.js, ibusCandidatePopup.js)
  # that activates iff the "typing-booster" IBus engine exists; tap commits word+space.
  # Shell patches add spacebar cursor-slide and committed-text auto-caps
  # (packages/gnome-mobile/patches/osk-spacebar-cursor-slide.patch + osk-autocaps-committed-tail.patch).
  # The engine fork (keyboard/patches/) adds no-preedit mode + real autocorrect + bilingual learning.
  # waylandFrontend=true stops the module setting GTK/QT_IM_MODULE (see NB
  # above; apps must keep speaking text-input-v3 to mutter). XMODIFIERS is
  # still set but neutralized by the gnome-mobile extraInit unset.
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.waylandFrontend = true;
    ibus.engines = [
      # en_US + es_AR dictionaries on DICPATH; typing-booster queries ALL
      # configured dicts on every keystroke — true simultaneous bilingual
      # suggestions (iOS-style), no language switching.
      # FORKED (keyboard/patches/): no-preedit mode + Android-style autocorrect.
      # Stock typing-booster holds the current word in IM preedit, but on
      # GNOME Shell Mobile the OSK never routes Backspace/cursor keys through
      # the engine → preedit desyncs, renders underlined, and backspace eats
      # text behind it. The fork commits each char immediately, keeps a shadow
      # buffer for the strip, and replaces words via delete_surrounding_text.
      # Both behaviors are env-gated (see sessionVariables) — unset env =
      # bone-stock engine, which is also the emergency kill switch.
      (pkgs.ibus-engines.typing-booster.override {
        langs = [ "en-us" "es-ar" ];
        typing-booster =
          (pkgs.ibus-engines.typing-booster-unwrapped.override {
            # The engine's spellcheck/suggestion layer needs a Python backend
            # (pyenchant or pyhunspell) and nixpkgs ships NEITHER — stock
            # typing-booster on NixOS cannot produce corrections at all
            # ("teh" never suggests "the"). Inject our pyhunspell
            # (packages/pyhunspell) into the derivation's private
            # python3.withPackages env by piggybacking on dbus-python's
            # propagated deps — the withPackages list is hardcoded upstream,
            # this is the least-invasive way in.
            python3 = pkgs.python3.override {
              packageOverrides = pyself: pysuper: {
                dbus-python = pysuper.dbus-python.overridePythonAttrs (o: {
                  propagatedBuildInputs = (o.propagatedBuildInputs or [ ]) ++ [
                    (pyself.callPackage ../../packages/pyhunspell { })
                  ];
                });
              };
            };
          }).overrideAttrs
            (old: {
              patches = (old.patches or [ ]) ++ [
                ./keyboard/patches/typing-booster-osk-no-preedit-autocorrect.patch
              ];
            });
      })
    ];
  };

  users.users.daniel = {
    isNormalUser = true;
    description = "Daniel";
    initialPassword = "1234";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "dialout"
      "feedbackd"
      "input"
      "render"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # GNOME / GNOME Shell Mobile dconf defaults.
  # Display-wake from DPMS-off is confirmed working under Mutter on SDM845, so
  # auto-dim + screen-off are enabled. Suspend stays disabled (broken s2idle) —
  # we only blank the display, never suspend the system.
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [{
    settings = with lib.gvariant; {
      "org/gnome/desktop/session" = {
        idle-delay = mkUint32 120;   # blank the display after 2 min idle
      };
      # Force GNOME Shell's built-in OSK on (touch device, no physical keyboard).
      "org/gnome/desktop/a11y/applications" = {
        screen-keyboard-enabled = true;
      };
      # ibus-typing-booster — the OSK suggestion-strip engine (see
      # i18n.inputMethod below). Learning data stays on-device in
      # ~/.local/share/ibus-typing-booster/user.db.
      "org/freedesktop/ibus/engine/typing-booster" = {
        dictionary = "en_US,es_AR"; # BOTH live at once; names = .dic files on DICPATH
        wordpredictions = true;
        emojipredictions = false; # the OSK has its own emoji panel
        mincharcomplete = mkInt32 1;
        tabenable = false;
        inlinecompletion = mkInt32 0; # strip-only; inline gray preedit is desktop UX
        lookuptableorientation = mkInt32 0; # horizontal, matches the 3-slot strip
        pagesize = mkInt32 3; # the strip shows at most 3 anyway
        autoselectcandidate = mkInt32 0; # suppress stock autocorrect; the engine fork's
                                         # smarter autocorrect is live via IBUS_TYPING_BOOSTER_OSK_AUTOCORRECT
        addspaceoncommit = true; # tap suggestion -> word + trailing space
        # Learn only correctly-spelled or previously-recorded words: keeps typos
        # AND password-field garbage out of the learning DB (gnome-shell #6693).
        # Tradeoff: unknown slang needs a manual first tap before it's learned —
        # revisit (recordmode=0) if that annoys in practice.
        recordmode = mkInt32 1;
        offtherecord = false;
        candidatesdelaymilliseconds = mkUint32 0; # no anti-flicker delay on a phone
        # Never forward synthetic arrow-key events for "cursor correction" after
        # commits: GTK4-on-Wayland drops them silently and the step count is
        # miscomputed for accented chars (NFD) — net effect was the cursor landing
        # mid-word after typing past an ignored suggestion (engine lines 5176/10854;
        # their own docs admit forward_key_event is broken on gtk4-im + gnome-wayland).
        avoidforwardkeyevent = true;
      };
      # Flashlight: enable the torch Quick Settings toggle (packages/gnome-mobile-torch).
      # It drives /sys/class/leds/{white,yellow}:flash via logind SetBrightness —
      # no udev rule needed (the LED's :seat: tag is sufficient).
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = [
          "torch@vixalien.com"
          # User Themes — loads the Marble shell theme selected in theme.nix.
          "user-theme@gnome-shell-extensions.gcampax.github.com"
          # Waydroid Watcher — force-stop apps on close, stop session on last
          # window close (checkpoint 6, waydroid.nix).
          "waydroid-watcher@fajita.local"
        ];
      };
      # gsd-power: dim before blanking, but NEVER suspend (broken s2idle on
      # SDM845). Power button isn't wired to an action — input wakes the display.
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-battery-type = "nothing";
        sleep-inactive-ac-type = "nothing";
        idle-dim = true;
        power-button-action = "nothing";
      };
      # Lock screen behavior + lock screen wallpaper.
      "org/gnome/desktop/screensaver" = {
        lock-enabled = true;
        idle-activation-enabled = true;  # lock when the display blanks on idle
        lock-delay = mkUint32 0;         # lock immediately on screen-off
        picture-uri = "file:///etc/wallpapers/fajita.jpg";
        picture-options = "zoom";
      };
      # UX defaults — dark mode + accent color.
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "Adwaita-dark";
        accent-color = "blue";          # Phosh 0.50+ honors GNOME accent
        show-battery-percentage = true; # numeric % next to the battery icon
        clock-format = "12h";           # 12-hour clock; flip to "24h" if preferred
        clock-show-weekday = true;      # weekday in the top bar
      };
      # Homescreen wallpaper. Image lives at hosts/fajita/wallpaper.jpg in
      # this repo, installed to /etc/wallpapers/ via environment.etc below.
      "org/gnome/desktop/background" = {
        picture-uri = "file:///etc/wallpapers/fajita.jpg";
        picture-uri-dark = "file:///etc/wallpapers/fajita.jpg";
        picture-options = "zoom";
      };
      # Ptyxis — touch-scroll fix.
      #
      # Root cause: GtkScrolledWindow only activates its CAPTURE-phase pan gesture
      # (the mechanism behind kinetic/touch-drag scrolling) when may_vscroll=true,
      # which requires vscrollbar_visible=true. With GTK_POLICY_AUTOMATIC (the default
      # when scrollbar-policy='system' + overlay-scrolling=true), vscrollbar_visible
      # is only true when the VTE adjustment.upper > page_size — i.e., only when
      # there is already scrollback content. At a fresh prompt it is false, so a
      # finger drag is never intercepted by GtkScrolledWindow's pan gesture; instead
      # it falls through to VTE's BUBBLE-phase click gesture, which starts text
      # selection rather than scrolling.
      #
      # 'always' → GTK_POLICY_ALWAYS → vscrollbar_visible=TRUE unconditionally →
      # CAPTURE-phase pan gesture active from the first touch-down, regardless of
      # how much (or how little) scrollback is present. Kinetic scroll works even
      # at an empty prompt. The scrollbar is also permanently visible, which is
      # helpful on a phone where you can't see scroll position otherwise.
      #
      # Ref: GtkScrolledWindow source (check_attach_pan_gesture, may_vscroll),
      # Ptyxis issue #567 ("Scrolling with touch screen no longer works"),
      # GNOME Console issue #451 ("No longer working on touch devices").
      "org/gnome/Ptyxis" = {
        scrollbar-policy = "always";
      };
      # Set Ptyxis as the default terminal (xdg-terminal-exec is not installed
      # on fajita, so the previous exec value silently failed for any app that
      # tries to open a terminal via the GNOME default-applications key).
      "org/gnome/desktop/default-applications/terminal" = {
        exec = "foot";
        exec-arg = "-e";
      };
    };
  }];

  # Install the wallpaper at /etc/wallpapers/fajita.jpg so dconf URIs above
  # resolve at boot. The file is checked into the nix repo at
  # hosts/fajita/wallpaper.jpg.
  environment.etc."wallpapers/fajita.jpg".source = ./wallpaper.jpg;

  # ALSA UCM overlay for the fajita audio routing — without this, modem dials
  # but voice calls have no audio. Files land at /etc/alsa/ucm2/OnePlus/fajita/
  # which alsa-lib checks before the stock alsa-ucm-conf tree.
  environment.etc = {
    "alsa/ucm2/OnePlus/fajita/fajita.conf".source = "${pkgs.alsa-ucm-fajita}/share/alsa/ucm2/OnePlus/fajita/fajita.conf";
    "alsa/ucm2/OnePlus/fajita/HiFi.conf".source = "${pkgs.alsa-ucm-fajita}/share/alsa/ucm2/OnePlus/fajita/HiFi.conf";
    "alsa/ucm2/OnePlus/fajita/VoiceCall.conf".source = "${pkgs.alsa-ucm-fajita}/share/alsa/ucm2/OnePlus/fajita/VoiceCall.conf";
  };

  # libcmatrix (chatty's Matrix backend) pulls olm — flagged insecure for
  # CVE-2024-45191/2/3. Allowlist explicitly; the upstream replacement is
  # vodozemac, but chatty hasn't switched yet.
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16" # chatty's libcmatrix
  ];

  # Firefox via the NixOS module (proper integration: schemas, gtk, etc.).
  # Fractional-scale fix: at Phosh's scale=2.5 Firefox would snap to nearest
  # integer scale and render chrome at wrong dev-px → URL bar + menus get
  # squeezed off the right edge. The wayland fractional-scale pref makes FF
  # honour the real scale (FF 114+, still behind the pref).
  # See: Mozilla bug 1614167, 1672591, 1881086.
  programs.firefox = {
    enable = true;
    # fx-autoconfig program tier — the content of program/config.js is placed
    # into the firefox wrapper's mozilla.cfg (via NixOS wrapFirefox extraPrefsFiles).
    # The wrapper writes "// First line must be a comment" as mozilla.cfg line 1
    # (which Firefox skips), so config.js's own "// skip 1st line" comment lands
    # safely on a subsequent line and is NOT the skipped line.  The JS in
    # config.js registers chrome.manifest from the current profile's chrome/utils/
    # and then imports boot.sys.mjs — both are placed by home.file entries in
    # home.nix.
    autoConfig = builtins.readFile "${pkgs.fx-autoconfig}/program/config.js";
    preferences = {
      "widget.wayland.fractional-scale.enabled" = true;
      # Required for userChrome.css to take effect on the mobile chrome tweaks
      # we'd ship via home-manager.
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      # Mobile-friendly defaults (subset of pmOS's mobile-config-firefox prefs)
      "browser.toolbars.bookmarks.visibility" = "never";
      "browser.uidensity" = 2;            # touch density (pmOS value)
      "dom.w3c.touch_events.enabled" = 1; # let pages know about touch
      "apz.allow_zooming" = true;         # pinch-zoom
      # Mobile browser behavior: reopening Firefox after a normal full quit
      # resumes the previous non-private window and its tabs.  Firefox keeps
      # private windows out of sessionstore, and crash recovery remains under
      # Firefox's own resume_from_crash policy (so do not override it here).
      "browser.startup.page" = 3;
      # urlbar: mobile suggestions — kill desktop-only sections, compact tray
      "browser.urlbar.trending.featureGate" = false;
      "browser.urlbar.suggest.trending" = false;
      "browser.urlbar.recentsearches.featureGate" = false;
      "browser.urlbar.suggest.recentsearches" = false;
      "browser.urlbar.suggest.topsites" = false;
      "browser.urlbar.weather.featureGate" = false;
      "browser.urlbar.suggest.weather" = false;
      "browser.urlbar.quicksuggest.enabled" = false;
      "browser.urlbar.suggest.quicksuggest.sponsored" = false;
      "browser.urlbar.sponsoredTopSites" = false;
      "browser.urlbar.groupLabels.enabled" = false;
      "browser.urlbar.suggest.mdn" = false;
      "browser.urlbar.suggest.addons" = false;
      "browser.urlbar.suggest.pocket" = false;
      "browser.urlbar.suggest.clipboard" = false;
      "browser.urlbar.maxRichResults" = 5;
      "browser.urlbar.showSearchSuggestionsFirst" = false;
      # C1b Orion pill — SHORT url display. Trim scheme + www; show the search
      # query instead of the SERP URL on a results page. Host-only-when-blurred
      # is done in urlbar-pill.uc.mjs (no built-in pref for it in FF150).
      "browser.urlbar.trimURLs" = true;        # trim http:// + trailing /
      "browser.urlbar.trimHttps" = true;       # also trim https:// (default off)
      "browser.urlbar.showSearchTerms.featureGate" = true;  # master gate (default off)
      "browser.urlbar.showSearchTerms.enabled" = true;      # replace SERP url w/ query
      # tab-count badge on the All Tabs button (mobile-config-firefox feature)
      "mcf.tabcounter.enabled" = true;
      # dev: don't cache chrome so userChrome/fx-autoconfig changes apply on restart
      "nglayout.debug.disable_xul_cache" = true;
    };
    preferencesStatus = "default"; # let user override per-session
  };

  environment.systemPackages = with pkgs; [
    # ─── Browsers ────────────────────────────────────────────────────────────
    ptyxis                                # libadwaita terminal; scrollbar-policy='always' (see dconf above) enables touch-drag scroll
    epiphany                              # Phosh-native, adaptive — best mobile browser
    brave                                 # Chromium-based, has aarch64 builds
    chromium                              # for sites that explicitly require Chrome (e.g. Preply Classroom)
    # zen-browser dropped — no touchscreen support
    # firefox: enabled separately via programs.firefox; squeeze/cutoff to be
    # fixed by vendoring pmOS's mobile-config-firefox userChrome + prefs.

    # ─── Communication (mobile-adaptive picks) ───────────────────────────────
    chatty                                # SMS + Matrix; lightweight, Phosh-native
    fractal                               # Matrix; GTK4/libadwaita, designed mobile-first
    # telegram-desktop dropped — desktop-only, painful on touch. Use the PWA at
    # https://web.telegram.org via Epiphany ("Install Site as Web Application"
    # in the Phosh menu) until paper-plane is revived upstream.
    geary                                 # Email — folds to single-pane at phone width (GTK3/libhandy),
                                          # full IMAP. Replaces Thunderbird, which is unusable on mobile.

    # ─── Diagnostics ─────────────────────────────────────────────────────────
    (pkgs.callPackage ./phone-check { }) # sensor readouts + keyring re-key button

    # ─── Phone-to-desktop integration ────────────────────────────────────────
    valent                                # KDE Connect protocol, GTK4/libadwaita (better mobile UX than kdeconnect-kde)

    # ─── Mobile-friendly GNOME core (libadwaita, adaptive) ───────────────────
    nautilus                              # Files
    loupe                                 # Image viewer
    papers                                # PDF reader (replaces evince; libadwaita)
    snapshot                              # GNOME Camera (libadwaita, GTK4)
    gnome-text-editor                     # libadwaita text editor
    gnome-calculator
    gnome-calendar
    gnome-contacts
    gnome-maps                            # libadwaita, online (GMaps tiles)
    organicmaps                           # offline OSM nav — AllTrails / hiking replacement
    # gnome-disk-utility dropped — GTK3, no GTK4/libadwaita port upstream.
    # Nautilus handles mount/unmount of external media; for anything heavier
    # ssh in and use parted/fdisk/wipefs.
    gnome-weather
    # gnome-clocks is replaced by the overrideAttrs build in clocks-alarm.nix (Oxygen alarm tone)
    gnome-sound-recorder                  # Voice Notes — simple libadwaita recorder (World/vocalis)
    resources                             # System monitor, GNOME Circle, libadwaita
    mission-center                        # alt system monitor, also libadwaita

    # ─── Media ───────────────────────────────────────────────────────────────
    clapper                               # libadwaita video player; works as a youtube client too
    totem                                 # GNOME Videos; libadwaita
    vlc                                   # fallback for anything clapper/totem can't handle
    delfin                                # Jellyfin client, GTK4/libadwaita
    # mimick — Immich client. Its ARM build (vendored image-codec C + LTO link)
    # is too heavy for harbor's qemu, so it builds natively on the mini's aarch64
    # builder — harbor offloads aarch64 (hosts/harbor/nix-builder.nix). Built from
    # the default nixpkgs (gtk4 4.22) via overlays/default.nix, since
    # nixpkgs-gnome49's 4.20.3 is too old for gdk4-sys.
    mimick
    gnome-mobile-torch                    # flashlight/torch Quick Settings toggle (packages/gnome-mobile-torch)
    anchorage                             # Linkding bookmark client (GTK4/libadwaita) — inputs.anchorage (github)
    jotter                                # Memos notes client (GTK4/libadwaita) — inputs.jotter (github)
    warden                                # Bitwarden/Vaultwarden client (GTK4/libadwaita, over rbw) — inputs.warden (github)
    courier                               # Email client (GTK4/libadwaita, IMAP/SMTP, privacy-first) — inputs.courier (local ~/Projects/courier)
    calculator                            # Calculator (GTK4/libadwaita, Google-Calculator-style, mobile-first) — inputs.calculator (local ~/Projects/calculator)
    # paloma-wrapped                      # Telegram client (GTK4/libadwaita, TDLib); api creds injected at runtime from sops — inputs.paloma (local ~/Projects/paloma). Secret is DECLARED (secrets.nix); uncomment to install once validated on mantle (heavy aarch64 build).
    # YouTube → self-hosted Invidious as a PWA (see pwas.nix). Dropped `pipeline`
    # because it speaks Piped, not Invidious. Clapper below still handles
    # paste-a-link one-off playback.
    mousai                                # song recognition (Shazam-style)
    # Spotify: spotify proper is x86_64-only and the web player needs Widevine
    # (absent on aarch64) — a librespot client is the native answer (Premium
    # required). History: pkgs.riff = riff.sh (wrong program) → used spot →
    # spot is UNMAINTAINED and its librespot 0.6 was broken by Spotify's 2025
    # API changes ("no alternatives found") → vendored the real Riff (spot's
    # maintained fork, librespot 0.8, works) in packages/riff.
    (pkgs.callPackage ../../packages/riff { })

    # ─── Camera ──────────────────────────────────────────────────────────────
    # megapixels dropped — using snapshot (libcamera/pipewire-camera, libadwaita)

    # ─── Office ──────────────────────────────────────────────────────────────
    # libreoffice dropped — multi-hour aarch64 build, ~1 GB install, rarely
    # used on phone. Re-add if you actually need offline document editing.

    # ─── Auth / 2FA ──────────────────────────────────────────────────────────
    authenticator                         # GNOME Circle, libadwaita TOTP
    # bitwarden-desktop dropped — building electron 39 under qemu-aarch64
    # took forever and there's no aarch64 substitute. Use vault.bitwarden.com
    # as a PWA via Epiphany ("Install Site as Web Application"); identical UX,
    # zero build cost. Switch back to the desktop client once Bitwarden ships
    # aarch64 binaries.

    # ─── GNOME Circle — small libadwaita apps ────────────────────────────────
    amberol                               # minimalist music player
    blanket                               # ambient sounds
    chess-clock                           # chess timer (gnome-chess-clock alias missing)
    clairvoyant                           # 8-ball
    decoder                               # QR scanner
    curtail                               # image compressor
    dialect                               # translator
    exercise-timer                        # tabata / interval timer
    fragments                             # BitTorrent client (libadwaita; transmission_4-gtk is GTK3)
    gradia                                # gradient / screenshot beautifier
    impression                            # USB image writer (will work once OTG is fixed)
    newsflash                             # RSS reader
    share-preview                         # social card preview
    solanum                               # pomodoro
    gnome-sudoku                          # sudoku
    gnome-2048                            # 2048
    valuta                                # currency converter

    # ─── Utilities ───────────────────────────────────────────────────────────
    mobile-broadband-provider-info        # APN auto-detection in Phosh Settings → Cellular
    callaudiod                            # routes call audio between earpiece / speaker / BT; DBus-activated by gnome-calls
    brightnessctl                         # CLI backlight control
    vim
    htop
    git
    curl
    bat
    ripgrep
    fd
    jq

    # ─── Diagnostic tools (for SDM845 / Phosh debug) ─────────────────────────
    evtest                                # input event tracing
    wlr-randr                             # wayland display control
    wayland-utils                         # wayland-info etc.
    libinput                              # libinput debug-events
  ];

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];
    auto-optimise-store = true;
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Argentina/Buenos_Aires";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "26.05";
}
