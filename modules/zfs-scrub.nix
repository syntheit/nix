{
  config,
  lib,
  pkgs,
  ...
}:

# Staggered ZFS scrubs: one pool at a time, spread over the month.
#
# Replaces services.zfs.autoScrub, which runs a single `zpool scrub` over every
# pool at once. Each running scrub may queue up to RAM/zfs_scan_mem_lim_fact of
# unreclaimable kernel memory (slab sio_cache, charged to no cgroup), so N
# pools at once = N times that. On 2026-11-01 seven parallel scrubs held
# 21.5 GB and stalled harbor. Pausing a scrub keeps that memory; only stopping
# (`zpool scrub -s`) or finishing frees it.
let
  cfg = config.services.zfsScrub;
  zfs = config.boot.zfs.package;
  # Spread pools evenly over days 1..28 (every month has them).
  step = lib.max 1 (builtins.div 28 (lib.length cfg.pools));
in
{
  options.services.zfsScrub = {
    enable = lib.mkEnableOption "staggered per-pool ZFS scrubs";
    pools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Pools to scrub, in order. Each gets its own day of the month, spaced evenly over days 1-28.";
    };
    time = lib.mkOption {
      type = lib.types.str;
      default = "02:00";
      description = "Time of day each scrub starts.";
    };
    scanMemLimitFactor = lib.mkOption {
      type = lib.types.ints.positive;
      default = 40;
      description = ''
        zfs_scan_mem_lim_fact: a scrub may queue up to RAM/this of kernel
        memory. ZFS default 20 (5% of RAM); 40 halves it at the cost of a
        slightly less sequential scrub.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.zfs.autoScrub.enable;
        message = "services.zfsScrub replaces services.zfs.autoScrub; disable the latter.";
      }
    ];

    boot.kernelParams = [ "zfs.zfs_scan_mem_lim_fact=${toString cfg.scanMemLimitFactor}" ];
    # kernelParams only apply at module load; also set it on the running module.
    systemd.tmpfiles.rules = [
      "w- /sys/module/zfs/parameters/zfs_scan_mem_lim_fact - - - - ${toString cfg.scanMemLimitFactor}"
    ];

    systemd.services."zfs-scrub@" = {
      description = "ZFS scrub of pool %i";
      after = [ "zfs-import.target" ];
      serviceConfig = {
        Type = "oneshot";
        # The lock keeps scrubs strictly one at a time, also when Persistent=
        # fires several missed timers together after downtime.
        ExecStart = "${pkgs.util-linux}/bin/flock /run/lock/zfs-scrub.lock ${zfs}/bin/zpool scrub -w %i";
        TimeoutStartSec = "infinity";
      };
    };

    systemd.timers = lib.listToAttrs (
      lib.imap0 (
        i: pool:
        lib.nameValuePair "zfs-scrub@${pool}" {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-${toString (1 + i * step)} ${cfg.time}";
            Persistent = true;
          };
        }
      ) cfg.pools
    );
  };
}
