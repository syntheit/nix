{ ... }:

# Memory-exhaustion hardening. Goal: a runaway interactive/agent workload in
# matv's session gets throttled or killed long before prod containers, sshd or
# the box as a whole stall.
{
  systemd = {
    # Cap everything matv runs (ssh/tmux/Claude agents, builds). user-1000.slice
    # is created transiently by logind from user-.slice, so this must be a
    # drop-in — a full unit file would shadow the template.
    slices."user-1000" = {
      overrideStrategy = "asDropin";
      sliceConfig = {
        MemoryHigh = "32G"; # throttle + reclaim hard above this
        MemoryMax = "36G"; # cgroup OOM-kill inside the slice only
        MemorySwapMax = "4G"; # don't let the session pin zram
      };
    };

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
    # preferred victim for earlyoom and the kernel global OOM killer. Login
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

    # systemd-oomd (enabled by default) kills under sustained memory pressure in
    # user slices only; root/system slices stay off so it never touches prod.
    oomd.enableUserSlices = true;
  };

  # Kill runaway processes before the system becomes unresponsive
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    # Never pick infra/prod daemons. Matched against comm (≤15 chars), so the
    # wildcard entries are prefixes. No --prefer: prod runs node/next-server too.
    # [.] instead of an escaped dot: systemd's $EARLYOOM_ARGS unquoting would eat the backslash.
    extraArgs = [
      "--avoid"
      "^(sshd|systemd|systemd-.*|dockerd|containerd|containerd-shim.*|postgres|mysqld|mariadbd|jellyfin|[.]qemu-system-x8.*|qemu-system-x86.*|tailscaled|cloudflared|zed|sops)$"
    ];
  };

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
