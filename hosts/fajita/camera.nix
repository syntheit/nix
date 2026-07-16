# Camera bring-up (Tier 0/1) — the plan lives in CAMERA_PLAN.md.
#
# Phase 0 (this file, current state): diagnostics only. CLI tools, device-node
# access, and a survey script that dumps the whole camera stack's ground truth
# (media graph, sensor controls, VCM range, LED flash nodes) for the evidence
# trail in ~/fajita-notes/camera-tests/.
#
# Later phases extend this module: libcamera tuning + AF patches (scoped via
# services.pipewire.package override, NOT a global overlay — avoids a world
# rebuild), Megapixels + oneplus,fajita.conf, LED/screen flash, and the phone
# side of the harbor darkroom pipeline.
{ pkgs, ... }:
let
  # Ground-truth dump of the camera stack. Read-only — safe to run any time.
  # Usage (from harbor): ssh fajita fajita-cam-survey > survey.log
  fajita-cam-survey = pkgs.writeShellApplication {
    name = "fajita-cam-survey";
    runtimeInputs = with pkgs; [
      v4l-utils
      libcamera
      coreutils
      gnugrep
    ];
    text = ''
      shopt -s nullglob

      say() { printf '\n===== %s =====\n' "$1"; }
      try() {
        printf -- '\n--- $ %s\n' "$*"
        "$@" || printf -- '[exit %s]\n' "$?"
      }

      say "fajita camera survey — $(date -Is)"
      try uname -r

      say "device-tree compatible"
      tr '\0' '\n' < /proc/device-tree/compatible || true

      say "kernel log (camera subsystem)"
      try sudo sh -c 'dmesg | grep -iE "imx37|imx519|camss|lc898|cci|csiphy|vfe|venus" | tail -n 80'

      say "media topology"
      try media-ctl -d /dev/media0 -p

      say "media topology (dot — for graphviz rendering)"
      try media-ctl -d /dev/media0 --print-dot

      say "libcamera enumeration"
      try cam --list

      for idx in 1 2 3; do
        say "libcamera camera $idx"
        try cam --camera "$idx" --list-controls
        try cam --camera "$idx" --list-properties
        try cam --camera "$idx" -I
      done

      # Per-subdev: controls (the VCM's focus_absolute lives here), pad
      # formats, mbus codes, crop rectangles (Phase 7 FoV evidence).
      for sd in /dev/v4l-subdev*; do
        name=$(cat "/sys/class/video4linux/$(basename "$sd")/name" 2>/dev/null || echo '?')
        say "subdev $sd ($name)"
        try v4l2-ctl -d "$sd" --list-ctrls
        try v4l2-ctl -d "$sd" --get-subdev-fmt pad=0
        try v4l2-ctl -d "$sd" --list-subdev-mbus-codes pad=0
        try v4l2-ctl -d "$sd" --get-subdev-selection pad=0,target=crop
      done

      for v in /dev/video*; do
        name=$(cat "/sys/class/video4linux/$(basename "$v")/name" 2>/dev/null || echo '?')
        say "video node $v ($name)"
        try v4l2-ctl -d "$v" --list-formats-ext
      done

      say "LED flash hardware (Phase 5b FlashPath target)"
      try command ls -l /sys/class/leds/
      for led in /sys/class/leds/*flash* /sys/class/leds/*torch*; do
        say "led $led"
        try command ls "$led"
        try cat "$led/max_brightness"
      done

      say "i2c camera/VCM devices"
      grep -H . /sys/bus/i2c/devices/*/name 2>/dev/null | grep -iE 'imx|lc898' || true

      say "identity"
      try id
    '';
  };
in
{
  environment.systemPackages = [
    pkgs.v4l-utils # v4l2-ctl + media-ctl — subdev controls / media-graph poking
    pkgs.libcamera # `cam` CLI — enumeration + capture through the soft ISP
    fajita-cam-survey
  ];

  # Camera device nodes. systemd's default 70-uaccess rules already tag
  # video4linux devices for the active seat; make it explicit and cover the
  # /dev/media* controller nodes too, so both the seat user (Snapshot via
  # pipewire) and ssh sessions (video group) can open the full media graph.
  services.udev.extraRules = ''
    SUBSYSTEM=="video4linux", GROUP="video", MODE="0660", TAG+="uaccess"
    SUBSYSTEM=="media", GROUP="video", MODE="0660", TAG+="uaccess"
  '';
}
