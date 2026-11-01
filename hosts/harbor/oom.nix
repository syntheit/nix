{ ... }:

# Memory-exhaustion hardening. Goal: a runaway interactive/agent workload in
# matv's session gets throttled or killed long before prod containers, sshd or
# the box as a whole stall. Tiers + oomd policy: modules/server-safety/memory.nix.
{
  services.serverSafety.memory = {
    enable = true;
    sessionMax = "32G"; # ssh logins + tmux + agents
    # tmux + agents. The 2026-10-30 runaway nix eval reached 27 GB.
    agentsMax = "24G";
    # Big local builds (vista's T2 kernel) fit; a runaway build gets OOM-killed.
    backgroundMax = "16G";
    # Off until zram grows to 50% (phase 1C): swap sits at ~83% of today's
    # 15.6 GB, mostly cold production pages, so the 90% rule would kill agents
    # for swap they don't hold.
    swapKill = false;
    backgroundUnits = [
      "nix-daemon"
      "nix-gc"
      "nix-optimise"
      "zfs-scrub@"
      "zpool-trim"
      "btrfs-scrub@"
      "fstrim"
      "restic-backups-offsite"
      "restic-check-offsite"
      "sanoid"
      "syncoid-platapool-seafile"
      "btrbk-default"
      "update-locatedb"
      "docker-prune"
    ];
  };

  systemd = {

    # Protect prod: system.slice holds the oci-containers scopes (docker,
    # systemd cgroup driver) and native services. Builtin unit → drop-in.
    slices.system = {
      overrideStrategy = "asDropin";
      sliceConfig = {
        MemoryLow = "12G"; # best-effort reclaim protection
        # memory_recursiveprot caps a child's MemoryMin by its ancestors', so
        # sshd's 128M below only holds if system.slice guarantees at least that.
        MemoryMin = "256M";
      };
    };

    # Make systemd --user services (and tmux servers spawned through it) the
    # preferred victim for the kernel global OOM killer. Login
    # shells live in session-*.scope instead; see environment.shellInit below.
    # Takes effect next time user@1000 starts (all sessions closed, or reboot).
    services."user@1000" = {
      overrideStrategy = "asDropin";
      restartIfChanged = false; # as user@.service: never kill the session on switch
      serviceConfig.OOMScoreAdjust = 500;
    };

    # Always keep enough RAM for sshd to let us in during a squeeze.
    services.sshd.serviceConfig.MemoryMin = "128M";

    # Throttle dockerd itself if it balloons. Baseline is ~5G unreclaimable
    # (anon + slab across dockerd/containerd/~56 shims), so 12G leaves headroom
    # before throttling stalls container plumbing. NO MemoryMax: killing
    # dockerd restarts every prod container.
    services.docker.serviceConfig.MemoryHigh = "12G";
  };

  # earlyoom removed 2026-11-01: it needs MemAvailable AND free swap low, and
  # MemAvailable stays "healthy" during file-page thrash. It never fired in
  # either stall. systemd-oomd (pressure-based) replaces it.

  # Login shells (sshd/mosh → zsh, tmux panes) sit in session-*.scope and start
  # at oom_score_adj 0, so user@1000's 500 never reaches them. Raise it for
  # matv's shells; children inherit it. Unprivileged processes may raise their
  # own score; the guard avoids lowering one that's already higher.
  # environment.shellInit lands once in /etc/zshenv (every zsh: interactive,
  # `ssh host cmd`, mosh-server) and once in /etc/profile (bash/sh logins;
  # /etc/bashrc sources /etc/profile when no parent shell did).
  environment.shellInit = ''
    if [ "$(id -u)" = 1000 ] && read -r __oom_adj < /proc/self/oom_score_adj 2>/dev/null \
      && [ "$__oom_adj" -lt 500 ]; then
      { echo 500 > /proc/self/oom_score_adj; } 2>/dev/null || true
    fi
    unset __oom_adj
  '';

  # Compressed in-memory swap — OOM protection without disk swap
  zramSwap = {
    enable = true;
    memoryPercent = 25; # ~16GB compressed swap
  };
}
