{
  pkgs,
  lib,
  hostName,
  ...
}:

# "Mac mini" in the launcher: the mini's desktop as a window on mantle, via
# Moonlight → Sunshine (hosts/mini/remote-desktop.nix). Measured on the LAN:
# ~1 ms network, <0.1 ms decode (NVDEC via VA-API), ~3 ms render.
#
# - 2560x1440 matches both the mini's display and mantle's monitors 1:1;
#   the window rule below makes it fill the monitor.
# - 120 fps: the mini's libx264 does ~160 fps at 1440p superfast, so 120
#   halves the frame interval of 60 with headroom left for the mini's own work.
# - H.264, no 4:4:4: Sunshine's macOS capture can't feed 4:4:4 yet.
# - Keyboard is captured, so Super reaches the mac as Cmd (Super+C copies,
#   Super+Space opens the mac's launcher). Binds that must stay with mantle
#   (workspaces, lock) are `bindp` in hyprland.nix.
# - Audio stays on the mini's speakers; Moonlight addresses the host by name
#   and prefers its LAN address over the tailnet one.
let
  macMini = pkgs.writeShellScriptBin "mac-mini" ''
    # Wake the mini's display first. Sunshine 2026.516 probes the encoder at
    # the start of every session, and against a sleeping display (a locked
    # Mac turns it off after ~30 s) that probe hangs for good, leaving
    # Moonlight at "Establishing connection". A lock screen is fine: log in
    # through the window. Best effort; connect anyway if ssh fails.
    ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=2 mini \
      'caffeinate -u -t 5 >/dev/null 2>&1 &' || true
    exec ${pkgs.moonlight-qt}/bin/moonlight stream mini Desktop \
      --resolution 2560x1440 --fps 120 --bitrate 200000 \
      --video-codec H.264 --no-yuv444 --video-decoder auto \
      --display-mode borderless --absolute-mouse --capture-system-keys always \
      --audio-on-host --no-vsync --no-frame-pacing --keep-awake \
      --no-performance-overlay
  '';
  moonlightClass = "^(com\\.moonlight_stream\\.Moonlight|moonlight)$";
in
lib.mkIf (hostName == "mantle") {
  home.packages = [
    pkgs.moonlight-qt
    macMini
  ];

  # Written directly: xdg.desktopEntries is a no-op here (see raven-scrcpy.nix).
  # Icon: macOS's own 2024 Mac mini icon (CoreTypes com.apple.macmini-2024.icns
  # via sips), as a PNG because the telmo launcher skips SVG.
  home.file.".local/share/applications/mac-mini.desktop".text = ''
    [Desktop Entry]
    Name=Mac mini
    GenericName=Remote desktop
    Exec=${macMini}/bin/mac-mini
    Icon=${./mac-mini-icon.png}
    StartupWMClass=com.moonlight_stream.Moonlight
    Type=Application
    Categories=Network;RemoteAccess;
  '';

  wayland.windowManager.hyprland.settings.windowrule = [
    "fullscreen 1, match:class ${moonlightClass}"
    "idle_inhibit focus, match:class ${moonlightClass}"
  ];
}
