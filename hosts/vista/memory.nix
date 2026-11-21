{ ... }:

# Hard memory ceilings, so a runaway lands in its own cgroup instead of stalling the box.
# Tiers, and why caps rather than earlyoom/oomd: modules/server-safety/memory.nix, hosts/harbor/oom.nix.
#
# 2026-11-19: vista froze at ~09:07 (power-cycled) with agent windows running nix builds. Swap had been 100% full
# since 2026-11-18 ~15:00 (earlyoom's hourly log), so the kernel could only evict file pages, and earlyoom never fired
# (it needs MemAvailable under 5%, which file-page thrash does not cause). Nothing was capped, so nothing was killed.
#
# 32 GB box; zram plus kernel take ~5 GB, system.slice ~5 GB. Caps leave that room:
#   window 12G (largest window seen: 10.9G peak incl. file cache), all windows 14G, whole login session 16G,
#   background 12G (nix-daemon peaked at 8.2G incl. build scratch in tmpfs /tmp; hunt apartments run at 6.4G and,
#   at OOMScoreAdjust 500, die first if the two overlap). A build that needs more belongs on harbor.
# The caps sum above RAM on purpose: they bound each space, they do not reserve it.
# Not used: hostcriticalUnits. It sets oom_score_adj -900 on sshd/tailscaled, which every login shell inherits
# (harbor needs a shellInit shim to undo that); with these caps the login path keeps its RAM without it.
{
  imports = [ ../../modules/server-safety ];

  services.serverSafety.memory = {
    enable = true;
    sessionMax = "16G";
    agentsMax = "14G";
    agentWindowMax = "12G";
    backgroundMax = "12G";
    backgroundUnits = [ "nix-daemon" ]; # hunt-daily/-details join in hunt.nix
  };

  # MemoryMax only bounds resident pages: without this a runaway build swaps out to zram until it is full,
  # which is the state the box was in on 2026-11-19. Same budget as the login session's.
  systemd.slices.background.sliceConfig.MemorySwapMax = "4G";
}
