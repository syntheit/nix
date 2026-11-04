# vista's Apple SSD (T2, AP2048N) takes 30-45 ms per cache flush, so anything
# that fsyncs (nix's database, Docker layers, Postgres, git) crawled: ~180 kB/s
# of synced 8k writes, ~5.5 MB/s once the kernel stops sending flushes. macOS
# behaves the same way by default (plain fsync doesn't flush there either).
#
# Trade-off: a sudden power cut can lose the drive's cache and, because btrfs
# orders its commits with flushes, can damage the filesystem (recovery:
# `mount -o rescue=usebackuproot`, else reinstall from this repo). vista is a
# laptop, so the battery covers outages, and nothing on it is the only copy of
# anything that matters (owner's call, 2026-11-03). A clean shutdown still
# saves the cache: the NVMe driver tells the drive to on poweroff.
{
  # write_cache only tells the kernel whether to send flushes; the drive keeps
  # caching either way.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]n[0-9]", ATTRS{model}=="APPLE SSD*", ATTR{queue/write_cache}="write through"
  '';

  # The one sudden power cut left to plan for: the battery running flat during
  # a long outage. Power off cleanly first. UPower acts only on battery power;
  # on AC, battery-guard (hardware.nix) already keeps it from running flat.
  services.upower = {
    enable = true;
    usePercentageForPolicy = true;
    percentageLow = 15;
    percentageCritical = 10;
    percentageAction = 8;
    criticalPowerAction = "PowerOff";
  };
}
