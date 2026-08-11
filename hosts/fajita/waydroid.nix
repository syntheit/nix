# Waydroid on-demand app layer (WhatsApp / Slack / Discord).
# Spec: ~/fajita-notes/waydroid-apps.md
#
# Battery framing NOTE: suspend is masked on fajita (s2idle broken on SDM845
# mainline; see default.nix). The spec's "restore suspend" rationale is moot;
# the on-demand model + close-to-quit extension (checkpoint 6) instead stop a
# *permanent* idle drain — Waydroid's wakelock holds the SoC out of deep idle
# and keeps Android userspace ticking whenever the session is up. Stopping the
# session returns the phone to its baseline idle-mA. The §8 A/B is an idle-draw
# delta, not a suspend-ability test.
{ config, lib, pkgs, ... }:

let
  # REQUIRED pkg: waydroid-nftables (not waydroid). The kernel is 6.16.7 and
  # iptables modules are gone on newer kernels; waydroid-nftables uses nft
  # explicitly and is safe on older kernels too. The nixpkgs module only
  # auto-selects it when networking.nftables.enable=true, which fajita does
  # not set, so we pin it explicitly here.
  waydroid = pkgs.waydroid-nftables;
  waydroidProvisionStart = pkgs.writeShellScriptBin "waydroid-provision-start" ''
    exec /run/current-system/sw/bin/systemctl start waydroid-apk-provision.service
  '';
in
{
  # System packages: adb (for split APK install) + waydroid-launch wrapper +
  # declarative .desktop files for the Waydroid apps (GNOME app grid entries).
  environment.systemPackages = let
    mkWaydroidDesktop = pkg: name: icon: pkgs.writeTextFile {
      name = "waydroid-${pkg}.desktop";
      destination = "/share/applications/waydroid.${pkg}.desktop";
      text = ''
        [Desktop Entry]
        Type=Application
        Name=${name}
        Exec=waydroid-launch ${pkg}
        Icon=${icon}
        Terminal=false
        Categories=Network;InstantMessaging;
        X-Purism-FormFactor=Mobile;
        NoDisplay=false
      '';
    };
  in [
    pkgs.android-tools
    # waydroid-launch: ensures the session is up before launching an app, fixing
    # the session-start race where `waydroid app launch` fires before Android is
    # ready and the app gets killed within ~100ms (spec §6).
    (pkgs.writeShellScriptBin "waydroid-launch" ''
      set -eu
      pkg="$1"
      W=${waydroid}/bin/waydroid

      # Start session if not running. Must inherit the graphical session env
      # so the Wayland connection works (XDG_RUNTIME_DIR + WAYLAND_DISPLAY).
      if ! "$W" status 2>/dev/null | grep -q "Session:.*RUNNING"; then
        "$W" session start >/dev/null 2>&1 &
        for i in $(seq 1 40); do
          "$W" status 2>/dev/null | grep -q "Session:.*RUNNING" && break
          sleep 1
        done
      fi

      # APK provisioning is privileged because split APK installation uses
      # root's Waydroid shell.  This narrowly-scoped sudo wrapper starts only
      # that service; the service waits for a real PackageManager response.
      # Keep existing installed apps launchable if vista is temporarily down.
      if ! sudo -n ${waydroidProvisionStart}/bin/waydroid-provision-start; then
        echo "Waydroid APK provisioning failed; launching $pkg anyway" >&2
      fi

      exec "$W" app launch "$pkg"
    '')
    waydroidProvisionStart
    (mkWaydroidDesktop "com.whatsapp" "WhatsApp" "im-whatsapp")
    (mkWaydroidDesktop "com.Slack" "Slack" "im-slack")
    (mkWaydroidDesktop "com.discord" "Discord" "im-discord")
    (mkWaydroidDesktop "com.google.android.apps.maps" "Google Maps" "maps")
    # ── Checkpoint 6: close-to-quit GNOME Shell extension ─────────────────
    # Force-stops the Android app when its GNOME window is closed (swipe-up
    # in overview), and stops the Waydroid session after a 30s grace period
    # when the last Waydroid window closes — releasing the wakelock and
    # returning the phone to baseline idle draw.
    (pkgs.stdenv.mkDerivation {
      pname = "waydroid-watcher-extension";
      version = "1";
      src = ./waydroid-watcher;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/gnome-shell/extensions/waydroid-watcher@fajita.local
        cp -r $src/* $out/share/gnome-shell/extensions/waydroid-watcher@fajita.local/
        runHook postInstall
      '';
    })
  ];

  virtualisation.waydroid = {
    enable = true;
    package = waydroid;
  };

  # On-demand: D-Bus activated, NOT started at boot. The container service
  # comes up when something calls `waydroid session start` (or our
  # waydroid-launch wrapper, checkpoint 5). Keeps the wakelock + Android
  # userspace off when we're not actively checking an app.
  systemd.services.waydroid-container = {
    wantedBy = lib.mkForce [ ];

    serviceConfig = {
      # cgroup v2 delegation for LXC (the container needs to manage its own
      # cgroup hierarchy under systemd's).
      Delegate = true;
      # Avoid the NixOS stop-loop bug (#334687): the module's ExecStopPost
      # can re-trigger the service on stop, leaving a tight loop. Clear it.
      ExecStopPost = lib.mkForce "";
    };

    # Set props by editing waydroid.cfg BEFORE the container starts (avoids a
    # race where the container reads the cfg before we've written it).
    # DISPLAY SCALE FIX: GNOME Mobile runs at 2.5x on the 1080×2340 panel.
    # Waydroid auto-detected that and set waydroid.display_scale=2.5, which
    # CRASHES SurfaceFlinger (init.svc.surfaceflinger=stopping, no surface
    # ever maps on Mutter — see waydroid#862 territory). The fix is to make
    # Android render at 1x natively (1080×2340) and let GNOME scale the
    # composited window at 2.5x as it does for every other app. This is
    # CHECKPOINT 2's hard-won fix — do NOT remove.
    # MULTI-WINDOW (checkpoint 5): each app gets its own Wayland xdg_toplevel
    # with app_id = "waydroid.<package>" → shows as its own overview card +
    # app-grid icon. Required for the close-to-quit extension (checkpoint 6)
    # which filters on the "waydroid." wm_class prefix.
    # SUSPEND ACTION: set to "none" (not "freeze") so the container doesn't
    # auto-freeze when no surface is visible — auto-freeze breaks pm install
    # and makes the session unresponsive during APK provisioning.
    preStart = ''
      cfg=/var/lib/waydroid/waydroid.cfg
      if [ -f "$cfg" ]; then
        ${pkgs.gnused}/bin/sed -i '/^waydroid.display_scale/d' "$cfg"
        ${pkgs.gnused}/bin/sed -i '/^persist.waydroid.display_scale/d' "$cfg"
        ${pkgs.gnused}/bin/sed -i '/^persist.waydroid.multi_windows/d' "$cfg"
        # Replace suspend_action (don't delete — the container re-adds the
        # default "freeze" if the line is missing).
        ${pkgs.gnused}/bin/sed -i 's/^suspend_action =.*/suspend_action = none/' "$cfg"
        grep -q '^\[properties\]' "$cfg" || echo '[properties]' >> "$cfg"
        ${pkgs.gnused}/bin/sed -i '/^\[properties\]/a waydroid.display_scale = 1\npersist.waydroid.display_scale = 1\npersist.waydroid.multi_windows = true' "$cfg"
      fi
    '';
  };

  # Idempotent one-time image init. `waydroid init -s GAPPS` pulls the GAPPS
  # image (lineage-20.0-GAPPS-waydroid_arm64, Android 13) from the Waydroid
  # OTA + SourceForge on first activation; skips on subsequent runs once
  # /var/lib/waydroid/waydroid.cfg and rootfs exist. Host is arm64, container
  # is arm64 → no libhoudini/libndk translation layer needed.
  # Network-online is required for the OTA pull on first init only, but
  # harmless on subsequent no-op runs.
  systemd.services.waydroid-init = {
    description = "Initialize Waydroid GAPPS image (idempotent)";
    # Pulled in when the container starts (D-Bus activated), so init runs on
    # first `waydroid session start`, not at boot. `Before=` orders it ahead
    # of the container: first launch blocks here for the OTA pull (~minutes),
    # subsequent launches are a no-op (idempotency check exits 0 immediately)
    # and the container starts right away.
    before = [ "waydroid-container.service" ];
    wantedBy = [ "waydroid-container.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "waydroid-init" ''
        set -eu
        # Already initialized → no-op. This is what makes it safe to run on
        # every boot: it only ever does work the first time.
        if [ -f /var/lib/waydroid/waydroid.cfg ] && [ -d /var/lib/waydroid/rootfs ]; then
          exit 0
        fi
        exec ${waydroid}/bin/waydroid init -s GAPPS
      '';
    };
  };

  # Checkpoint 7: fetch Daniel-managed APKs from vista and provision only the
  # packages that are absent from the running Android image.  This is pulled in
  # when the D-Bus-activated container starts, rather than at boot.  It must
  # run *after* the container: `pm` and Waydroid's /data bind mount are not
  # available until then.
  #
  # The service deliberately relies on root's normal SSH configuration for
  # daniel@vista.  Set up that key separately on fajita before enabling this
  # in production; no private key belongs in the Nix store.
  systemd.services.waydroid-apk-provision = {
    description = "Provision missing Waydroid APKs from vista";
    # Provisioning needs a running user session and PackageManager, so it is
    # started by waydroid-launch after session startup—not by the container
    # activation transaction.
    wantedBy = [ ];
    # Do not pull in network-online.target: on fajita its pre-existing
    # systemd-networkd wait job can remain pending indefinitely.  Tailscale
    # is already ordered ahead when present, and rsync reports a real network
    # failure directly instead of blocking the app launch transaction.
    after = [ "waydroid-container.service" "tailscaled.service" ];

    path = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.lxc
      pkgs.openssh
      pkgs.procps
      pkgs.rsync
      pkgs.unzip
      pkgs.util-linux
    ];

    serviceConfig = {
      Type = "oneshot";
      # Leave the unit inactive after each run, so a later container start can
      # run the idempotency check again.
      RemainAfterExit = false;
    };

    script = ''
      set -euo pipefail

      W=${waydroid}/bin/waydroid
      REMOTE="daniel@vista:/home/daniel/waydroid-apks/"
      CACHE=/var/cache/waydroid-apks
      DATATMP=/home/daniel/.local/share/waydroid/data/local/tmp

      mkdir -p "$CACHE" "$DATATMP"

      # A Waydroid container may still be frozen despite suspend_action=none.
      # Do this before asking Android to service pm commands.
      lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid 2>/dev/null || true

      # `waydroid-container.service` can be active while Waydroid still calls
      # the container stopped: pm only becomes usable after a graphical
      # Waydroid session starts.  Start it with Daniel's GNOME session
      # environment, matching waydroid-launch (the root systemd environment
      # has neither the Wayland socket nor the session D-Bus address).
      gnome_pid=$(pgrep -u daniel -f '[g]nome-shell' | head -n 1 || true)
      if [ -z "$gnome_pid" ]; then
        echo "Could not find Daniel's GNOME Shell session" >&2
        exit 1
      fi
      xdg_runtime_dir=$(tr '\0' '\n' < "/proc/$gnome_pid/environ" | ${pkgs.gnused}/bin/sed -n 's/^XDG_RUNTIME_DIR=//p' | head -n 1)
      dbus_session_bus=$(tr '\0' '\n' < "/proc/$gnome_pid/environ" | ${pkgs.gnused}/bin/sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -n 1)
      wayland_display=$(tr '\0' '\n' < "/proc/$gnome_pid/environ" | ${pkgs.gnused}/bin/sed -n 's/^WAYLAND_DISPLAY=//p' | head -n 1)
      if [ -z "$xdg_runtime_dir" ] || [ -z "$dbus_session_bus" ]; then
        echo "Could not read Daniel's graphical session environment" >&2
        exit 1
      fi
      # Root performs the pm session operations, but the Waydroid CLI still
      # consults the graphical-session environment to find the active session.
      export XDG_RUNTIME_DIR="$xdg_runtime_dir"
      export DBUS_SESSION_BUS_ADDRESS="$dbus_session_bus"
      export WAYLAND_DISPLAY="''${wayland_display:-wayland-0}"
      if ! "$W" status 2>/dev/null | grep -q 'Session:.*RUNNING'; then
        runuser -u daniel -- env \
          XDG_RUNTIME_DIR="$xdg_runtime_dir" \
          DBUS_SESSION_BUS_ADDRESS="$dbus_session_bus" \
          WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
          "$W" session start >/dev/null 2>&1 &
      fi

      session_ready=0
      for i in $(seq 1 40); do
        if "$W" status 2>/dev/null | grep -q 'Session:.*RUNNING'; then
          session_ready=1
          break
        fi
        sleep 3
      done
      if [ "$session_ready" -ne 1 ]; then
        echo "Waydroid session did not become ready" >&2
        exit 1
      fi

      ready=0
      for i in $(seq 1 30); do
        # `waydroid shell` itself exits zero even when Android replies
        # "Can't find service: package" during early boot.  Require actual
        # PackageManager output instead of trusting that wrapper exit status.
        if "$W" shell -- pm list packages 2>/dev/null | grep -q '^package:'; then
          ready=1
          break
        fi
        sleep 3
      done
      if [ "$ready" -ne 1 ]; then
        echo "Waydroid package manager did not become ready" >&2
        exit 1
      fi

      # Mirror only installable artifacts.  --delete prevents an old cached
      # APK from being selected after Daniel replaces it on vista.
      rsync -az --delete \
        --include='*.apk' --include='*.apkm' --exclude='*' \
        -e 'ssh -o BatchMode=yes' "$REMOTE" "$CACHE/"

      package_present() {
        "$W" shell -- pm list packages 2>/dev/null | grep -qFx "package:$1"
      }

      install_split_bundle() {
        local file="$1" pkg="$2" work jobdir session split name failed
        work=$(mktemp -d)
        jobdir="$DATATMP/waydroid-provision-$pkg"
        rm -rf "$jobdir"
        mkdir -p "$jobdir"

        # APKMirror .apkm archives contain many ABI, density, and locale
        # splits.  fajita only needs the base, arm64-v8a, and xxhdpi splits.
        for split in base.apk split_config.arm64_v8a.apk split_config.xxhdpi.apk; do
          if ! unzip -p "$file" "$split" > "$work/$split"; then
            echo "Missing required split $split in $file" >&2
            rm -rf "$work" "$jobdir"
            return 1
          fi
        done
        cp "$work"/*.apk "$jobdir/"

        session=$("$W" shell -- pm install-create 2>&1 | ${pkgs.gnused}/bin/sed -n 's/.*\[\([0-9][0-9]*\)\].*/\1/p')
        if [ -z "$session" ]; then
          echo "pm install-create failed for $pkg" >&2
          rm -rf "$work" "$jobdir"
          return 1
        fi

        failed=0
        for split in base.apk split_config.arm64_v8a.apk split_config.xxhdpi.apk; do
          name="''${split%.apk}"
          if ! "$W" shell -- pm install-write "$session" "$name" "/data/local/tmp/waydroid-provision-$pkg/$split"; then
            failed=1
            break
          fi
        done
        if [ "$failed" -eq 0 ] && ! "$W" shell -- pm install-commit "$session"; then
          failed=1
        fi
        if [ "$failed" -ne 0 ]; then
          "$W" shell -- pm install-abandon "$session" >/dev/null 2>&1 || true
        fi

        rm -rf "$work" "$jobdir"
        [ "$failed" -eq 0 ]
      }

      shopt -s nullglob nocasematch
      for file in "$CACHE"/*.apk "$CACHE"/*.apkm; do
        base=$(basename "$file")
        case "$base" in
          com.whatsapp*.apk) pkg=com.whatsapp; kind=apk ;;
          com.slack*.apkm) pkg=com.Slack; kind=apkm ;;
          com.discord*.apkm) pkg=com.discord; kind=apkm ;;
          com.google.android.apps.maps*.apk) pkg=com.google.android.apps.maps; kind=apk ;;
          *) echo "Skipping unrecognised APK artifact: $base"; continue ;;
        esac

        if package_present "$pkg"; then
          echo "Skipping $pkg: already installed"
          continue
        fi

        echo "Installing missing $pkg from $base"
        if [ "$kind" = apk ]; then
          "$W" app install "$file"
        else
          install_split_bundle "$file" "$pkg"
        fi

        if ! package_present "$pkg"; then
          echo "Package install did not register $pkg" >&2
          exit 1
        fi
      done
    '';
  };

  # Allow Daniel's app launcher to start exactly the provisioning wrapper,
  # without granting passwordless access to systemctl or arbitrary root
  # commands.  The wrapper accepts no arguments.
  security.sudo.extraRules = [
    {
      users = [ "daniel" ];
      commands = [
        {
          command = "${waydroidProvisionStart}/bin/waydroid-provision-start";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
