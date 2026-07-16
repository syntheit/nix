{ pkgs, ... }:
let
  # SLPI sensor serve tree (pmOS's firmware-oneplus-sdm845 "sensors" payload).
  # SDM845's accel/gyro/mag/ALS/proximity live on the SLPI DSP, invisible to
  # kernel i2c. The SLPI's sensor core requests its DSP libs + sensor configs
  # from userspace over FastRPC (hexagonrpcd's HexagonFS reverse tunnel):
  #   <root>/dsp             → /vendor/dsp
  #   <root>/sensors/config  → /vendor/etc/sensors/config   (per-IC JSON configs)
  #   <root>/sensors/registry→ /mnt/vendor/persist/sensors/registry/registry
  #   <root>/sensors/sns_reg.conf → /vendor/etc/sensors/sns_reg_config
  # Without this tree the sensor core publishes QRTR svc 400 with ZERO sensors
  # and iio-sensor-proxy exits with "No sensors". Blobs extracted from stock
  # OxygenOS by the sdm845-mainline project (same repo the tfa98xx.cnt and
  # audio UCM come from).
  sensorTree =
    pkgs.runCommand "fajita-slpi-sensor-tree"
      {
        src = pkgs.fetchFromGitLab {
          owner = "sdm845-mainline";
          repo = "firmware-oneplus-sdm845";
          rev = "176ca713448c5237a983fb1f158cf3a5c251d775";
          sha256 = "0gif318f9b2cr3l5bn1zj2m3bhha47f82rv2d9jlnqwcxxh6zc36";
        };
      }
      ''
        mkdir -p "$out/share/qcom/sdm845/OnePlus"
        cp -r $src/usr/share/qcom/sdm845/OnePlus/oneplus6 \
              "$out/share/qcom/sdm845/OnePlus/oneplus6"
        ln -s oneplus6 "$out/share/qcom/sdm845/OnePlus/fajita"
      '';
in
{
  # libssc 0.2.2 (nixpkgs) is too old to enumerate the accelerometer through
  # SSC — with it, iio-sensor-proxy finds only ambient_light + rotv (compass);
  # HasAccelerometer stays false, no auto-rotate. pmOS ships 0.4.4 and has
  # status_accel=Y on this device. Bump via overlay; iio-sensor-proxy rebuilds
  # against it automatically.
  nixpkgs.overlays = [
    (final: prev: {
      libssc = prev.libssc.overrideAttrs (old: {
        version = "0.4.4";
        src = prev.fetchFromCodeberg {
          owner = "DylanVanAssche";
          repo = "libssc";
          tag = "v0.4.4";
          sha256 = "0wpj9ckdp7w86p8wqll890qmky00hvcf2bw9824x9kh6v4v39l0b";
        };
      });
    })
  ];

  # Point the (package-shipped) hexagonrpcd-sdsp unit at the serve tree, and
  # give it clean shutdown ordering. The upstream unit has NONE, so it's killed
  # early at multi-user.target teardown — while the SLPI DSP may still be
  # mid-FastRPC transaction. Leaving the SLPI in a bad state on shutdown makes
  # the hypervisor flag a subsystem crash → Qualcomm CrashDump mode on the NEXT
  # boot (same failure shape as the rmtfs/wifi bug we already fixed). Fix is
  # ORDERING-ONLY: stop it before the shutdown targets and give the FastRPC
  # channel time to close. Do NOT echo-stop the remoteproc — that path caused a
  # kernel panic on this device before. See ~/fajita-notes.
  systemd.services.hexagonrpcd-sdsp = {
    serviceConfig.ExecStart = [
      ""
      "${pkgs.hexagonrpc}/bin/hexagonrpcd -f /dev/fastrpc-sdsp -d sdsp -s -R ${sensorTree}/share/qcom/sdm845/OnePlus/fajita"
    ];
    serviceConfig.TimeoutStopSec = 10;
    unitConfig = {
      Before = "shutdown.target reboot.target halt.target poweroff.target";
      Conflicts = "shutdown.target reboot.target halt.target poweroff.target";
    };
  };

  # iio-sensor-proxy probes SSC (QRTR svc 400) at startup and EXITS if the
  # sensor core hasn't enumerated its sensors yet — which takes a few seconds
  # after hexagonrpcd starts serving. Order it after the bridge and let it
  # retry instead of staying dead until D-Bus pokes it.
  systemd.services.iio-sensor-proxy = {
    after = [ "hexagonrpcd-sdsp.service" ];
    wants = [ "hexagonrpcd-sdsp.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Two udev pieces:
  # 1) upstream iio-sensor-proxy's 80- rule only tags fastrpc devices with
  #    "ssc-light ssc-compass" — accel/proximity are opt-in (accel is wrong
  #    without a per-device mount matrix, so upstream stays conservative).
  #    Tag them in; this was the final gate to HasAccelerometer=true.
  # 2) fajita's accelerometer mount matrix (pmOS 81-libssc-oneplus-fajita.rules):
  #    the IMU is mounted rotated; without it auto-rotate picks wrong quadrants.
  services.udev.extraRules = ''
    SUBSYSTEM=="misc", KERNEL=="fastrpc-*", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel ssc-proximity"
    SUBSYSTEM=="misc", KERNEL=="fastrpc-*", ENV{ACCEL_MOUNT_MATRIX}+="-1, 0, 0; 0, 1, 0; 0, 0, -1"
  '';
}
