{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  networking.hostName = "fajita";

  # Upstream libinput 1.31.3 gates lua-plugin support on luaSupport (defaults
  # true in nixpkgs). Mobile NixOS's lvgui pulls a libinput build where the lua
  # dependency lookup fails — and we don't need libinput plugins on a phone
  # anyway. Disable luaSupport entirely (removes lua5_4 from buildInputs AND
  # passes -Dlua-plugins=disabled to meson). Scoped to fajita.
  nixpkgs.overlays = [
    (final: prev: {
      libinput = prev.libinput.override { luaSupport = false; };
    })
  ];

  # Phosh dies on every `nixos-rebuild switch`. Root cause: NixOS's activation
  # script does `stop → start` on units whose dependencies changed, even if the
  # unit itself didn't change. With `restartIfChanged=false` alone it still does
  # the stop because `stopIfChanged` defaults to true. Need BOTH false to keep
  # the running phosh session alive across rebuilds — new config's phosh takes
  # over on next reboot.
  systemd.services.phosh = {
    restartIfChanged = false;
    stopIfChanged = false;
  };

  # Phosh shell — upstream NixOS module; mobile-nixos's example imports this verbatim.
  # phocConfig.outputs sets per-output scale and modeline in /etc/phosh/phoc.ini.
  # scale 2.5 (vs default 2.0) is load-bearing: Phosh's top bar is hardcoded 32
  # *logical* pixels in src/top-panel.h. At scale 2 that's 64 physical = shorter
  # than the OnePlus 6T notch (~80 physical), so notch pokes through. At 2.5 the
  # bar is 80 physical — fully covers the cutout. Bonus: quick-settings buttons +
  # general UI become correctly sized for the screen, matching pmOS's default.
  services.xserver.desktopManager.phosh = {
    enable = true;
    user = "daniel";
    group = "users";
    phocConfig.outputs.DSI-1 = {
      scale = 2.5;
    };
  };
  programs.calls.enable = true;
  hardware.sensor.iio.enable = true;

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
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # SDM845 mainline display-wake-from-DPMS-off bug workaround.
  # Symptom: power button puts display to sleep via Phosh's screen-saver. KEY_POWER
  # event then doesn't reach phoc to undo DPMS. Phone is stuck on with no display.
  # Until task #15 lands a proper fix (likely kernel-side), this service watches
  # /dev/input/event0 (pm8941_pwrkey) and, on each KEY_POWER press while DPMS=Off,
  # asks phoc to re-enable the output via the wlr-output-power-manager-v1 protocol.
  #
  # We avoid `chvt` here — switching VTs makes systemd's TTYVHangup=yes on
  # phosh.service send SIGHUP to the wayland session, killing Phosh. wlr-randr
  # talks directly to phoc as a wayland client; no VT churn, no session kill.
  systemd.services.pwrkey-wake-watcher = {
    description = "Force display wake on power button press (SDM845 DPMS-off bug workaround)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" "phosh.service" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 2;
      ExecStart = pkgs.writeShellScript "pwrkey-wake-watcher" ''
        set -eu
        DPMS_FILE=$(${pkgs.coreutils}/bin/ls /sys/class/drm/card*-DSI-1/dpms 2>/dev/null | head -1)
        [ -n "$DPMS_FILE" ] || { echo "no DSI-1 found, exiting"; exit 0; }
        # libinput debug-events opens but doesn't grab — phoc still sees events.
        ${pkgs.libinput}/bin/libinput debug-events --device /dev/input/event0 2>/dev/null | \
          while read -r line; do
            case "$line" in
              *KEY_POWER*pressed*)
                if [ "$(${pkgs.coreutils}/bin/cat "$DPMS_FILE")" = "Off" ]; then
                  echo "DPMS off detected after KEY_POWER — asking phoc to re-enable DSI-1"
                  ${pkgs.sudo}/bin/sudo -u daniel \
                    XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
                    ${pkgs.wlr-randr}/bin/wlr-randr --output DSI-1 --on || true
                fi
              ;;
            esac
          done
      '';
    };
  };

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
  # Register hexagonrpc + stevia systemd units. The nixpkgs phosh module
  # registers the `phosh` package's units but NOT stevia's — meaning stevia's
  # `mobi.phosh.Stevia.service` user unit is invisible to systemd. Stevia DOES
  # autostart via Phosh's XDG autostart chain, but the systemd unit is the
  # documented activation path for Phosh ≥0.50 OSK contract. Wiring it makes
  # `systemctl --user status mobi.phosh.Stevia` work and lets stevia restart
  # cleanly across phosh restarts.
  systemd.packages = [
    pkgs.hexagonrpc
    pkgs.stevia
  ];
  systemd.services.hexagonrpcd-sdsp.wantedBy = [ "multi-user.target" ];
  systemd.user.services."mobi.phosh.Stevia".wantedBy = [ "graphical-session.target" ];

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
  };
  # CRITICAL OSK auto-show fix: force GTK to use the wayland input-method
  # module so text-input-v3 events flow from apps → phoc → stevia. The
  # dconf gsetting `org.gnome.desktop.interface.gtk-im-module=""` ALONE
  # does NOT work — many GTK apps (especially DBus-activated ones like
  # gnome-control-center, chatty) don't read the gsetting; they need the
  # env var. Verified by side-by-side test: same Epiphany binary, OSK
  # auto-show worked with GTK_IM_MODULE=wayland set in env, failed without.
  #
  # `mkForce` because NixOS's i18n.inputMethod.ibus module sets this to
  # "ibus" with the same priority — without mkForce we get an eval conflict.
  # The `i18n.inputMethod.enable = false` below disables ibus at the source.
  environment.sessionVariables.GTK_IM_MODULE = lib.mkForce "wayland";
  environment.variables.GTK_IM_MODULE = lib.mkForce "wayland";
  # Some upstream module (likely a gnome default in nixpkgs) enables
  # i18n.inputMethod with ibus type, which forces GTK_IM_MODULE=ibus and
  # silently breaks every text-input-v3 path. We want the wayland IM module
  # for the Phosh OSK to auto-show.
  i18n.inputMethod.enable = lib.mkForce false;

  # seatd lets wlroots-based compositors (phoc) take over the TTY without being
  # PID 1 — the libseat backend talks to seatd over a UNIX socket. Daniel needs
  # to be in the seat group for the connection.
  services.seatd.enable = true;

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
      "seat"
      "input"
      "render"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # Phosh config:
  # - shell-layout=device → use gmobile per-device JSON (oneplus,fajita.json
  #   ships upstream) so the top bar shifts UI around the notch instead of
  #   getting clipped. shell-layout=device is the upstream default since
  #   Phosh 0.29.0; setting it explicitly so we survive any stray reset.
  # - idle-delay=0 + sleep-inactive-*=nothing → never blank the display.
  #   Without this, Phosh blanks at the GNOME default (300s) and the power
  #   button doesn't reliably wake it on SDM845 mainline. Until we figure out
  #   why KEY_POWER doesn't route through libinput to phoc, just never blank.
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [{
    settings = with lib.gvariant; {
      "sm/puri/phosh" = {
        shell-layout = "device";
      };
      "org/gnome/desktop/session" = {
        idle-delay = mkUint32 0;
      };
      # OSK: phosh-osk-stevia (bundled with phosh 0.54) is the real virtual
      # keyboard. Two gates need to flip for it to auto-show on text-field
      # focus:
      # (1) GNOME's a11y screen-keyboard flag — without this, no OSK at all.
      "org/gnome/desktop/a11y/applications" = {
        screen-keyboard-enabled = true;
      };
      # (2) Stevia's `ignore-hw-keyboards` — it defaults to false, meaning the
      # OSK hides whenever a "hardware keyboard" is detected. Phoc's seat
      # exports WL_SEAT_CAPABILITY_KEYBOARD because the phone has volume-keys
      # and power-key as keyboard-class input devices. Result: stevia stays
      # hidden forever. Override to true.
      "mobi/phosh/osk" = {
        ignore-hw-keyboards = true;
      };
      # (3) gtk-im-module MUST be empty string. nixpkgs gnome defaults it to
      # 'toolkit-accessibility' system-wide. With ANY value set, GTK apps
      # route input through that IM module and never speak text-input-v3 to
      # phoc → phoc never calls SetVisible on stevia → no auto-show ever.
      # Per stevia manpage: "for the keyboard to fold and unfold automatically
      # make sure org.gnome.desktop.interface gtk-im-module is set to the
      # empty string". This is the load-bearing OSK fix.
      # gsd-power: never act on idle, never dim, never act on power button.
      # Phosh handles power-button directly (short-press = lock + blank;
      # long-press = power dialog).
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-battery-type = "nothing";
        sleep-inactive-ac-type = "nothing";
        idle-dim = false;
        power-button-action = "nothing";
      };
      # Lock screen behavior + lock screen wallpaper.
      "org/gnome/desktop/screensaver" = {
        lock-enabled = true;
        idle-activation-enabled = false; # idle-delay=0 makes this moot, but explicit
        lock-delay = mkUint32 0;         # lock immediately on screen-off
        picture-uri = "file:///etc/wallpapers/fajita.jpg";
        picture-options = "zoom";
      };
      # UX defaults — dark mode + accent color.
      "org/gnome/desktop/interface" = {
        gtk-im-module = "";       # see GTK_IM_MODULE env var note above
        color-scheme = "prefer-dark";
        gtk-theme = "Adwaita-dark";
        accent-color = "blue";    # Phosh 0.50+ honors GNOME accent
      };
      # Homescreen wallpaper. Image lives at hosts/fajita/wallpaper.jpg in
      # this repo, installed to /etc/wallpapers/ via environment.etc below.
      "org/gnome/desktop/background" = {
        picture-uri = "file:///etc/wallpapers/fajita.jpg";
        picture-uri-dark = "file:///etc/wallpapers/fajita.jpg";
        picture-options = "zoom";
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
    };
    preferencesStatus = "default"; # let user override per-session
  };

  environment.systemPackages = with pkgs; [
    # ─── Browsers ────────────────────────────────────────────────────────────
    epiphany                              # Phosh-native, adaptive — best mobile browser
    brave                                 # Chromium-based, has aarch64 builds
    chromium                              # for sites that explicitly require Chrome (e.g. Preply Classroom)
    # zen-browser dropped — no touchscreen support
    # firefox: enabled separately via programs.firefox; squeeze/cutoff to be
    # fixed by vendoring pmOS's mobile-config-firefox userChrome + prefs.

    # ─── Communication (mobile-adaptive picks) ───────────────────────────────
    chatty                                # SMS + Matrix; lightweight, Phosh-native
    fractal                               # Matrix; GTK4/libadwaita, designed mobile-first
    signal-desktop                        # link to the Pixel as primary
    vesktop                               # Discord with proper wayland + screen-share
    # telegram-desktop dropped — desktop-only, painful on touch. Use the PWA at
    # https://web.telegram.org via Epiphany ("Install Site as Web Application"
    # in the Phosh menu) until paper-plane is revived upstream.
    thunderbird                           # Email; not adaptive but the option you use elsewhere

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
    gnome-clocks
    resources                             # System monitor, GNOME Circle, libadwaita
    mission-center                        # alt system monitor, also libadwaita

    # ─── Media ───────────────────────────────────────────────────────────────
    clapper                               # libadwaita video player; works as a youtube client too
    totem                                 # GNOME Videos; libadwaita
    vlc                                   # fallback for anything clapper/totem can't handle
    delfin                                # Jellyfin client, GTK4/libadwaita
    mousai                                # song recognition (Shazam-style)
    riff                                  # Spotify Premium client, libadwaita (succeeds `spot`)
    # spotify proper is x86_64-only (proprietary); riff via librespot is the
    # native answer on aarch64. Free tier needs Widevine which doesn't exist
    # on aarch64 Firefox/Chromium — Premium-only effectively.

    # ─── Camera ──────────────────────────────────────────────────────────────
    megapixels                            # raw V4L2 camera, fajita-tuned (UCM-style)

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
