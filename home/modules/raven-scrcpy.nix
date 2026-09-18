{ pkgs, lib, hostName, ... }:

let
  # raven is a Pixel 6 Pro (LineageOS, rooted via Magisk) running the NixOS
  # VM (`raven`) inside the AVF Terminal app — see hosts/raven/start-vm.sh.
  # The phone normally sits with its screen off (start-vm.sh turns it back
  # off after boot to save battery), which puts it under Android's Doze /
  # App Standby network throttling — the same reason `ssh raven` is flaky
  # from mantle (verified: ping to it runs 1-2s, SSH to raven-phone often
  # times out outright). adbd is a system daemon rather than a Doze-limited
  # app process, so once ADB-over-TCP is actually listening it tends to be
  # noticeably more reliable than the Termux sshd raven-phone depends on.
  #
  # ADB-over-TCP is NOT persisted across phone reboots (`service.adb.tcp.port`
  # resets), so this wakes it on demand each run via the one reliable-enough
  # path available: SSH into the phone itself (raven-phone, Termux sshd) and
  # flip it on as root. If that SSH hop is itself down, there's currently no
  # fallback — see the note at the bottom about making this boot-persistent.
  ip = "192.168.1.197";
  port = "5555";

  ravenScrcpy = pkgs.writeShellScriptBin "raven-scrcpy" ''
    set -euo pipefail
    notify=${pkgs.libnotify}/bin/notify-send
    adb=${pkgs.android-tools}/bin/adb
    target="${ip}:${port}"

    # `adb connect` reports "connected to" at the TCP level regardless of
    # authorization — it says that just as happily for an unauthorized device.
    # The real state lives in `adb devices`: absent, "unauthorized", or "device".
    state() {
      $adb connect "$target" >/dev/null 2>&1 || true
      $adb devices | awk -v t="$target" '$1==t {print $2; found=1} END{if(!found) print "absent"}'
    }

    wake_and_enable() {
      $notify "raven" "$1"
      ${pkgs.openssh}/bin/ssh -o ConnectTimeout=8 -o BatchMode=yes raven-phone \
        "su -c 'setprop service.adb.tcp.port ${port}; stop adbd; start adbd; input keyevent KEYCODE_WAKEUP'"
    }

    st="$(state)"

    if [ "$st" != "device" ]; then
      if ! wake_and_enable "Waking phone + enabling ADB over SSH…"; then
        $notify -u critical "raven" "Couldn't reach raven-phone over SSH — is it awake/on the LAN?"
        exit 1
      fi
      sleep 2
      st="$(state)"
    fi

    # First-ever connection from this computer's ADB key: the phone needs a
    # physical tap on its "Allow debugging?" popup, which only shows with the
    # screen on. Poll for a bit instead of failing immediately — once tapped
    # (and "always allow" checked), every future run skips straight past this.
    if [ "$st" = "unauthorized" ]; then
      $notify "raven" "Check the phone — tap Allow on the ADB debugging prompt"
      for _ in $(seq 1 30); do
        sleep 2
        st="$(state)"
        [ "$st" = "device" ] && break
      done
    fi

    if [ "$st" != "device" ]; then
      $notify -u critical "raven" "raven still not reachable (state: $st)"
      exit 1
    fi

    # -S: turn the physical screen off once mirroring starts (it's normally
    # off anyway — this just skips the brief wake flash). -K: turn it back
    # off on exit too, in case something (a notification, the wake itself)
    # lit it up during the session.
    exec ${pkgs.scrcpy}/bin/scrcpy -s "$target" -S -K
  '';
in
lib.mkIf (hostName == "mantle") {
  home.packages = [ ravenScrcpy ];

  # xdg.desktopEntries is a no-op in this config (xdg.enable = false disables
  # the xdg.dataFile wiring it depends on) — write the .desktop directly, same
  # as the power-menu entries in rofi.nix.
  home.file.".local/share/applications/raven-scrcpy.desktop".text = ''
    [Desktop Entry]
    Name=Raven (scrcpy)
    GenericName=Mirror Pixel 6 Pro
    Exec=${ravenScrcpy}/bin/raven-scrcpy
    Icon=phone
    Type=Application
    Categories=Utility;
  '';
}
