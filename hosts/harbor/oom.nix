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
    swapKill = true; # needs the 50% zram below: at 25% swap sat at ~83%
    # Ways back in + the OOM handler: guaranteed RAM, last OOM victims.
    hostcriticalUnits = [
      "sshd"
      "sshd-rescue"
      "tailscaled"
      "cloudflared-tunnel-harbor"
      "systemd-oomd"
    ];
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

    # No MemoryHigh on dockerd (it was 12G): above MemoryHigh a cgroup can
    # freeze instead of being killed (see modules/server-safety/memory.nix),
    # and a frozen dockerd stalls every container operation. liveRestore keeps
    # containers running even if dockerd itself dies.
  };

  # No core files: a crash-looping tsserver (Claude Code typescript-lsp
  # across many agent worktrees) dumped ~4 GB each time, and writing every
  # dump took 2.5-5 GB of RAM in system.slice plus a 1 GB write. Crashes are
  # still logged with their stack trace in the journal.
  systemd.coredump.settings.Coredump.Storage = "none";

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
    # ~31 GB of swap space. It holds compressed pages (3.6x measured), so a
    # full zram costs ~9 GB of RAM. 25% sat at ~83% full with cold pages.
    memoryPercent = 50;
  };
}
