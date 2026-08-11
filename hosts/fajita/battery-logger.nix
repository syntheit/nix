{ pkgs, ... }:
{
  # Always-on battery/power logger (battery project, added 2026-08-11).
  # One sample every 2 min to /var/lib/battery-log/samples-YYYYMMDD.log:
  #   ts current_uA voltage_uV cap% charge_uAh temp_deciC status bl_power
  #   brightness load1 top_process,cpu%
  # current_uA sign: negative = discharging. bl_power: 0 = screen on, 4 = off.
  # ~30 KB/day; tmpfiles prunes files older than 60 days. Negligible overhead
  # (a handful of sysfs reads + one ps per sample). This replaces the ad-hoc
  # nohup profilers used during the July 2026 battery work — see
  # ~/fajita-notes/battery-power.md for how to analyze (segment by status +
  # bl_power, integrate charge_uAh deltas; gauge noise means >10 min windows).
  systemd.services.battery-logger = {
    description = "Battery/power sampler (2-min cadence, /var/lib/battery-log)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 30;
      StateDirectory = "battery-log";
      ExecStart = pkgs.writeShellScript "battery-logger" ''
        BQ=/sys/class/power_supply/bq27411-0
        while true; do
          d=$(${pkgs.coreutils}/bin/date +%Y%m%d)
          top1=$(${pkgs.procps}/bin/ps -eo comm,%cpu --sort=-%cpu \
                   | ${pkgs.gnused}/bin/sed -n 2p \
                   | ${pkgs.coreutils}/bin/tr -s " " ",")
          echo "$(${pkgs.coreutils}/bin/date +%s) \
$(cat $BQ/current_now) $(cat $BQ/voltage_now) $(cat $BQ/capacity) \
$(cat $BQ/charge_now) $(cat $BQ/temp) $(cat $BQ/status) \
$(cat /sys/class/backlight/*/bl_power 2>/dev/null | ${pkgs.coreutils}/bin/head -1) \
$(cat /sys/class/backlight/*/brightness 2>/dev/null | ${pkgs.coreutils}/bin/head -1) \
$(${pkgs.coreutils}/bin/cut -d" " -f1 /proc/loadavg) $top1" \
            >> /var/lib/battery-log/samples-$d.log
          sleep 120
        done
      '';
    };
  };
  systemd.tmpfiles.rules = [ "e /var/lib/battery-log - - - 60d" ];
}
