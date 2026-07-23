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
in
{
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
    # multi_windows (checkpoint 5) is added here too when we get there.
    preStart = ''
      cfg=/var/lib/waydroid/waydroid.cfg
      if [ -f "$cfg" ]; then
        ${pkgs.gnused}/bin/sed -i '/^waydroid.display_scale/d' "$cfg"
        ${pkgs.gnused}/bin/sed -i '/^persist.waydroid.display_scale/d' "$cfg"
        ${pkgs.gnused}/bin/sed -i '/^persist.waydroid.multi_windows/d' "$cfg"
        grep -q '^\[properties\]' "$cfg" || echo '[properties]' >> "$cfg"
        ${pkgs.gnused}/bin/sed -i '/^\[properties\]/a waydroid.display_scale = 1\npersist.waydroid.display_scale = 1' "$cfg"
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
}
