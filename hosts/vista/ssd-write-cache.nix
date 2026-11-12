# vista's Apple SSD (T2, AP2048N) takes 30-45 ms per cache flush, so anything
# that fsyncs (nix's database, Docker layers, Postgres, git) is slow: ~180 kB/s
# of synced 8k writes. From 2026-11-03 to 11-12 a udev rule set the drive's
# queue/write_cache to "write through" so the kernel stopped sending flushes
# (~5.5 MB/s). Do NOT bring that back.
#
# Why: the rule assumed the only sudden power cut would be the battery running
# flat. In fact this Mac loses power with no warning in several other ways: a
# kernel panic reboot or SysRq-b (the firmware turns any non-kexec reboot into
# a power-off), and plain hard resets. On 2026-11-11 11:06 and 11-12 10:47
# vista dropped mid-activity with no kernel message, no thermals, no shutdown.
# Neither reset gives the NVMe a clean shutdown, so the drive's volatile cache
# is lost. Without flushes, btrfs can't order its commits, and the second reset
# left the fsync log root as zeros on both DUP copies ("bad tree block start
# ... have 0", "Couldn't setup log root tree"): /sysroot would not mount.
# Recovered from a rescue USB with `btrfs rescue zero-log`; check and scrub
# came back clean.
#
# Flushes stay on (kernel default). If fsync speed matters, relax it per
# workload (e.g. a nix/docker/postgres setting) rather than for the whole disk.
{
  # Still worth doing: power off cleanly before the battery runs flat during a
  # long outage. UPower acts only on battery power; on AC, battery-guard
  # (hardware.nix) already keeps it from running flat.
  services.upower = {
    enable = true;
    usePercentageForPolicy = true;
    percentageLow = 15;
    percentageCritical = 10;
    percentageAction = 8;
    criticalPowerAction = "PowerOff";
  };
  # Otherwise it only starts on D-Bus demand; headless, nothing asks.
  systemd.services.upower.wantedBy = [ "multi-user.target" ];
}
