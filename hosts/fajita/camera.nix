# Camera bring-up (Tier 0/1) — the plan lives in CAMERA_PLAN.md.
#
# Phase 0: diagnostics — CLI tools, device-node access, and a survey script
# that dumps the camera stack's ground truth (media graph, sensor controls,
# VCM range, LED flash nodes) for the evidence trail in
# ~/fajita-notes/camera-tests/.
#
# Phase 1: soft-ISP tuning files. pmOS's black-level YAMLs for IMX371/IMX376
# (vendored from pmaports temp/libcamera, see camera/tuning/) fix the known
# libcamera bug where untuned sensors render all-black with purple/red
# flashes, and give the rear sensor an interim CCM (borrowed from s5kjn1 —
# replaced by a fajita-derived matrix in Phase 4). The patched libcamera is
# injected via SCOPED overrides (pipewire + wireplumber only), NOT a global
# overlay — a global overlay would rebuild gnome-shell and most of the
# desktop under emulation for no benefit.
#
# Later phases extend this module: AF patches into the same libcamera-fajita
# derivation (Phase 3), Megapixels + oneplus,fajita.conf + flash (Phase 5),
# and the phone side of the harbor darkroom pipeline (Phase 6).
{ pkgs, ... }:
let
  # libcamera + per-sensor tuning for the simple/soft IPA. The soft IPA looks
  # up <sensor-name>.yaml in <prefix>/share/libcamera/ipa/simple/ — without a
  # file it falls back to uncalibrated.yaml (no black level → the all-black
  # bug on these sensors).
  libcamera-fajita = pkgs.libcamera.overrideAttrs (old: {
    # Phase 3: soft-ISP autofocus + manual controls. Vendored from
    # gitlab.com/tui/libcamera branch millicam_af_6 (Vasiliy Doylov + Pavel
    # Machek; manual-focus patch is patchwork #26241, tested upstream on
    # OnePlus 6) — rebased onto the branch's pristine base so they apply to
    # vanilla 0.7.0, mcam-app hunks dropped. AF activates per-sensor via the
    # tuning YAMLs: imx376 lists `Af:` (has the lc898217xc VCM), imx371 must
    # not (fixed-focus). The CDAF auto-starts through its focus-loss
    # detector, so Snapshot needs no AfTrigger plumbing.
    patches = (old.patches or [ ]) ++ [
      ./camera/patches/01-libcamera-software_isp-Add-focus-control.patch
      ./camera/patches/02-libcamera-software_isp-Add-brightness-control.patch
      ./camera/patches/03-libcamera-software_isp-Add-AGC-disable-control.patch
      ./camera/patches/04-libcamera-software_isp-Add-manual-exposure-control.patch
      ./camera/patches/05-libcamera-software_isp-Add-autofocus.patch
      ./camera/patches/06-AF-detect-focus-loss.patch
      ./camera/patches/07-af-Less-phases-only-take-center-of-picture-for-sha.patch
      ./camera/patches/08-af-slower-focus-but-seems-to-work.patch
      ./camera/patches/09-af-reindent-to-match-rest-of-code.patch
      # OURS (candidate for upstream feedback on the AF series): the branch's
      # focus-loss check restarts the sweep on ANY single-frame ±30% sharpness
      # deviation → continuous hunting on static scenes (observed in Snapshot).
      # Debounced: drop-only, 10-frame persistence, adopts improvements.
      ./camera/patches/10-af-debounce-focus-loss-detection.patch
    ];
    postInstall = (old.postInstall or "") + ''
      install -Dm644 ${./camera/tuning/imx371.yaml} $out/share/libcamera/ipa/simple/imx371.yaml
      install -Dm644 ${./camera/tuning/imx376.yaml} $out/share/libcamera/ipa/simple/imx376.yaml
    '';
  });

  # The libcamera SPA plugin ships inside pipewire's package, and WirePlumber
  # (which hosts the camera monitor) resolves SPA plugins via ITS pipewire
  # input — both must see libcamera-fajita or the session keeps loading the
  # untuned stack.
  pipewire-fajita = pkgs.pipewire.override { libcamera = libcamera-fajita; };
  wireplumber-fajita = pkgs.wireplumber.override { pipewire = pipewire-fajita; };

  # Phase 5: Megapixels raw-capture stack. Two fajita-specific fixes:
  # 1. VFE stride: the CAMSS VFE pads raw lines to 16 bytes; libmegapixels
  #    assumed 8 → capture-buffer assert crash (verified: 2592px→3248 B/line,
  #    4656px→5824). Patch scoped here; proper upstream fix = use the
  #    driver-reported mode->stride that pipeline.c already records.
  # 2. Config discovery: nix meson defaults sysconfdir into the store, so
  #    findconfig.c never searched the real /etc — point it back.
  libmegapixels-fajita = pkgs.libmegapixels.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./camera/patches/libmegapixels-16-byte-line-padding.patch ];
    mesonFlags = (old.mesonFlags or [ ]) ++ [ "--sysconfdir=/etc" ];
  });
  megapixels-fajita =
    (pkgs.megapixels.override { libmegapixels = libmegapixels-fajita; }).overrideAttrs
      (old: {
        # Megapixels' AE assumes digital-gain min == 1x baseline; Sony
        # sensors here are min=0/default=1024(=1x), so its "too bright"
        # branch walks dgain to ~0 → black viewfinder, and the value
        # persists in the driver after exit (poisons Snapshot too).
        # Patch: never drive digital gain (analogue 0-480 + exposure is
        # plenty) + guard a /0 in the ISO display math.
        patches = (old.patches or [ ]) ++ [ ./camera/patches/megapixels-no-digital-gain.patch ];
      });

  # Megapixels rewires the media graph via raw V4L2; WirePlumber's libcamera
  # monitor gives up permanently if it re-probes into that state → Snapshot
  # reports "No camera found" until the graph is reset and the monitor
  # bounced. Wrap the launcher so every Megapixels exit restores the world.
  megapixels-wrapped = pkgs.symlinkJoin {
    name = "megapixels-fajita";
    paths = [
      (pkgs.writeShellScriptBin "megapixels" ''
        ${megapixels-fajita}/bin/megapixels "$@"
        rc=$?
        ${pkgs.v4l-utils}/bin/media-ctl -d /dev/media0 -r 2>/dev/null || true
        systemctl --user restart wireplumber 2>/dev/null || true
        exit $rc
      '')
      megapixels-fajita # .desktop file, icons, schemas — bin/ shadowed by wrapper
    ];
  };
  # Ground-truth dump of the camera stack. Read-only — safe to run any time.
  # Usage (from harbor): ssh fajita fajita-cam-survey > survey.log
  fajita-cam-survey = pkgs.writeShellApplication {
    name = "fajita-cam-survey";
    runtimeInputs = [
      pkgs.v4l-utils
      libcamera-fajita
      pkgs.coreutils
      pkgs.gnugrep
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
    libcamera-fajita # `cam` CLI — enumeration + capture through the (tuned) soft ISP
    fajita-cam-survey
    # Phase 2: fajita-focus — manual/auto focus via the lc898217xc VCM
    # (contrast hill-climb over `cam` captures; see packages/fajita-camera-tools)
    (pkgs.callPackage ../../packages/fajita-camera-tools { })
    # Phase 5: Megapixels — raw-DNG capture + LED/screen flash. Uses the
    # device config from /etc/megapixels/config/ (below). No AF (direct
    # V4L2); pair with fajita-focus --hold when focus matters.
    megapixels-wrapped
  ];

  # Camera path only — audio/BT config for pipewire lives in default.nix and
  # is unaffected (same pipewire source, just built with our libcamera).
  services.pipewire.package = pipewire-fajita;
  services.pipewire.wireplumber.package = wireplumber-fajita;

  # Phase 5a: Megapixels device config — raw-DNG capture + flash tool
  # (Snapshot stays the AF daily shooter; Megapixels bypasses libcamera and
  # has no focus support). /etc/megapixels/config/ is a libmegapixels search
  # path, so config iteration needs no rebuild, just a switch.
  # Repo file is comma-free (store path names forbid ','); the /etc target
  # keeps the comma libmegapixels expects (DT-compatible-based lookup).
  environment.etc."megapixels/config/oneplus,fajita.conf".source =
    ./camera/megapixels/oneplus-fajita.conf;

  # Camera device nodes. systemd's default 70-uaccess rules already tag
  # video4linux devices for the active seat; make it explicit and cover the
  # /dev/media* controller nodes too, so both the seat user (Snapshot via
  # pipewire) and ssh sessions (video group) can open the full media graph.
  services.udev.extraRules = ''
    SUBSYSTEM=="video4linux", GROUP="video", MODE="0660", TAG+="uaccess"
    SUBSYSTEM=="media", GROUP="video", MODE="0660", TAG+="uaccess"

    # Phase 5b: pmi8998 flash LED — Megapixels strobes it by writing 1 to
    # flash_strobe, which is root-only sysfs by default. Group-write for
    # video. (The torch QS toggle uses logind SetBrightness — unaffected.)
    ACTION=="add", SUBSYSTEM=="leds", KERNEL=="white:flash", \
      RUN+="${pkgs.runtimeShell} -c 'chgrp video /sys%p/flash_strobe /sys%p/flash_brightness /sys%p/brightness; chmod 664 /sys%p/flash_strobe /sys%p/flash_brightness /sys%p/brightness'"
  '';
}
