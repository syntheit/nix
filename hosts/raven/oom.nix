{ ... }:

# Memory-exhaustion hardening for the 6.9 GB AVF guest. Same tiers as harbor
# (modules/server-safety/memory.nix, hosts/harbor/oom.nix), sized down.
#
# 2026-11-20: ~5 Claude sessions + ~9 subagents (nre-finance-dashboard,
# the_construct) ran at once and filled the guest. With no caps (and only the
# 1.7G nixos-avf zram) the kernel thrashed file pages for ~25 min (crosvm 570% CPU, 150+ MB/s re-reads
# of the disk image), never OOM-killed anything, and every sshd/tmux froze.
# No single runaway: the aggregate cap (agentsMax) is the one that matters
# here. At the cap the kernel kills the biggest agent inside user@1000 and the
# services + ways back in keep running.
{
  services.serverSafety.memory = {
    enable = true;
    sessionMax = "5G"; # last resort: ssh logins + tmux + agents
    agentsMax = "4600M"; # all agents together; leaves ~2.3G for services + kernel
    agentWindowMax = "2560M"; # one agent + its builds/tests
    backgroundMax = "1536M"; # nix evals/copies, gc; real builds go to mini
    hostcriticalMin = "384M";
    hostcriticalUnits = [
      "sshd"
      "sshd-rescue"
      "tailscaled"
      "cloudflared-tunnel-raven"
      "systemd-oomd"
    ];
    backgroundUnits = [
      "nix-daemon"
      "nix-gc"
      "nix-optimise"
      "docker-prune"
      "construct-backup"
    ];
  };

  systemd = {
    # Protect construct-life, the website container and dockerd.
    slices.system = {
      overrideStrategy = "asDropin";
      sliceConfig.MemoryLow = "1G";
    };

    # Agents are the preferred global-OOM victims. Takes effect next time
    # user@1000 starts (VM restart).
    services."user@1000" = {
      overrideStrategy = "asDropin";
      restartIfChanged = false;
      serviceConfig.OOMScoreAdjust = 500;
    };
  };

  # A core dump of a crashing tsserver costs GBs of RAM to write (harbor 11-01).
  systemd.coredump.settings.Coredump.Storage = "none";

  # droid's login shells (session-*.scope) start at 0; raise to match user@1000.
  environment.shellInit = ''
    if [ "$(id -u)" = 1000 ] && read -r __oom_adj < /proc/self/oom_score_adj 2>/dev/null \
      && [ "$__oom_adj" -lt 500 ]; then
      { echo 500 > /proc/self/oom_score_adj; } 2>/dev/null || true
    fi
    unset __oom_adj
  '';

  # Swap: nixos-avf already sets up zram0 = ram/4 (~1.7G) via zram-generator.
  # It didn't prevent the 11-20 thrash on its own; the caps above do the work.
}
