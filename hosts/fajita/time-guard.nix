{ pkgs, ... }:
{
  # The PMIC RTC has no real backup time.  PID 1 correctly restores the last
  # NTP timestamp from /var, but the late-probing RTC driver then overwrites it
  # with 1970.  GDM starts in that interval and is not safe across the later
  # 55-year NTP clock step: its session bookkeeping corrupts and the lock
  # screen can no longer open an authentication channel.
  #
  # Run after the RTC has appeared (local-fs is already in the display
  # manager's boot chain) and before GDM.  The timestamp is only restored when
  # it is plausibly modern.  Crucially, GDM does not start until timesyncd has
  # confirmed that time: even a small subsequent clock step can make GDM's
  # session bookkeeping crash.
  systemd.services.fajita-restore-clock = {
    description = "Restore persisted NTP time before GDM starts";
    before = [ "display-manager.service" ];
    requiredBy = [ "display-manager.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils pkgs.systemd ];
    script = ''
      clock=/var/lib/systemd/timesync/clock
      earliest=1735689600 # 2025-01-01T00:00:00Z
      now="$(date +%s)"

      if [ "$now" -lt "$earliest" ] && [ -f "$clock" ]; then
        saved="$(stat -c %Y "$clock")"
        if [ "$saved" -ge "$earliest" ]; then
          echo "fajita-restore-clock: restoring $saved after invalid RTC time $now"
          date -u -s "@$saved"
        fi
      fi

      echo "fajita-restore-clock: waiting up to 90s for confirmed NTP synchronization"
      for _ in $(seq 1 90); do
        if [ "$(timedatectl show --property=NTPSynchronized --value 2>/dev/null)" = yes ]; then
          echo "fajita-restore-clock: NTP synchronized"
          exit 0
        fi
        sleep 1
      done
      echo "fajita-restore-clock: NTP unavailable; continuing after timeout"
    '';
  };
}
