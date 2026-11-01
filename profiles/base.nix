{ lib, ... }:

# Baseline every NixOS host gets: memory-pressure behaviour, core dumps, nix
# daemon priority, kernel attack surface. Values are mkDefault so a host can
# override any of them. Plan + rationale: ~/contexts/fleet-resilience.md.
{
  boot.kernel.sysctl = {
    # Swap here is zram (RAM-backed). Swapping cold anon pages to it is cheaper
    # than evicting file pages, which are often program code (sshd, tailscaled):
    # evicting those is what turns memory pressure into a box-wide stall.
    # Swappiness does not affect the ZFS ARC; ARC shrinks via its own shrinker.
    "vm.swappiness" = lib.mkDefault 100;
    # No swap readahead: zram is random-access, readahead only wastes RAM.
    "vm.page-cluster" = lib.mkDefault 0;
    # Wider watermark gap (1.25% of RAM) so kswapd starts reclaiming before
    # allocations fall into direct reclaim and stall.
    "vm.watermark_scale_factor" = lib.mkDefault 125;
    # Nothing in the fleet uses MPTCP, but Go >= 1.24 services open MPTCP
    # listeners by default. Fewer exposed kernel paths.
    "net.mptcp.enabled" = lib.mkDefault 0;
  };

  # MGLRU thrash protection: never evict pages used in the last second. When
  # the working set can't be kept, the kernel OOM-kills early instead of
  # thrashing for minutes. "w-": skip quietly on kernels without lru_gen.
  systemd.tmpfiles.rules = [ "w- /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000" ];

  # Don't dump huge processes: writing a multi-GB core means reading and
  # compressing all of its memory, mid-crisis (harbor: tsserver ~500 MB dumps,
  # 46 in a week, ~300 MB/s write bursts on the root SSD).
  systemd.coredump.settings.Coredump = {
    ProcessSizeMax = lib.mkDefault "1G";
    ExternalSizeMax = lib.mkDefault "1G";
    MaxUse = lib.mkDefault "4G";
  };

  # Builds yield to everything interactive or serving.
  nix.daemonCPUSchedPolicy = lib.mkDefault "batch";
  nix.daemonIOSchedClass = lib.mkDefault "idle";
  # Deduplicate the store on a timer instead of during every build
  # (replaces nix.settings.auto-optimise-store).
  nix.optimise.automatic = lib.mkDefault true;
}
