{ config, lib, ... }:

# Memory tiers: interactive/dev work and background jobs get hard ceilings, so
# a runaway is killed inside its own space before the box stalls. Production
# (system.slice) is never an oomd target. Plan: ~/contexts/fleet-resilience.md.
#
#   hostcritical.slice       sshd, tailscale, tunnel  guaranteed RAM, last OOM victim
#   user-<uid>.slice         logins, tmux, agents     last-resort cap (sessionMax)
#     user@<uid>.service     tmux + agents            last-resort cap (agentsMax)
#       tmux-spawn-*.scope   one tmux window/agent    cap (agentWindowMax)
#   background.slice         builds, scrubs, backups  hard cap, lowest CPU/IO
#
# Hard caps only, no MemoryHigh. Above MemoryHigh with no swap left, the kernel
# just sleeps the cgroup's tasks as a penalty: no reclaim happens, so oomd
# (which only kills when reclaim is active) never acts, and the cgroup never
# reaches MemoryMax either. Everything in it freezes indefinitely. Measured on
# harbor 2026-11-01: 55-90% stall, pgscan frozen, no kill. Likely the 2026-10-30
# "ssh connects but no shell" (user-1000.slice sat at its 32G MemoryHigh).
# At MemoryMax the kernel OOM-kills the biggest task in that cgroup instead.
#
# Per-window caps, not one aggregate cap. A window is one agent session plus
# everything it launches. When it hits its cap, the kernel kills the biggest
# process in it (a compiler or build); OOMPolicy=continue keeps the rest of the
# window, including the Claude session, alive. The aggregate caps sit high and
# only matter if the whole box is in danger. (2026-11-02: a 24G aggregate cap
# killed a 3 GB java build with 40 GB free, and systemd's default OOMPolicy=stop
# then tore down the whole tmux window and the Claude session in it.)
# No oomd on user slices: oomd kills whole cgroups, i.e. whole windows.
#
# Kernel memory (ZFS ARC, scrub queues) is charged to no cgroup; these limits
# can't see it. That's bounded separately (modules/zfs-scrub.nix, ARC caps).
let
  cfg = config.services.serverSafety;
  mem = cfg.memory;
  uid = toString mem.uid;
in
{
  options.services.serverSafety.memory = {
    enable = lib.mkEnableOption "memory tiers + oomd policy";
    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "UID of the interactive user whose session gets capped.";
    };
    sessionMax = lib.mkOption {
      type = lib.types.str;
      example = "32G";
      description = "Hard cap for the whole user session (logins, tmux, agents).";
    };
    agentsMax = lib.mkOption {
      type = lib.types.str;
      example = "24G";
      description = ''
        Hard cap for user@<uid>.service (systemd --user services and the tmux
        servers the agents run in); the kernel OOM-kills inside it only. Login
        shells are outside it.
      '';
    };
    backgroundMax = lib.mkOption {
      type = lib.types.str;
      default = "12G";
      description = "Hard cap for background.slice; a build that outgrows it gets OOM-killed, not stalled.";
    };
    agentWindowMax = lib.mkOption {
      type = lib.types.str;
      default = "16G";
      description = ''
        Cap per tmux window (tmux-spawn-*.scope): one agent session plus
        everything it launches. The kernel kills the biggest process in the
        window at the cap; the window itself keeps running.
      '';
    };
    backgroundUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Services moved into background.slice (builds, scrubs, backups,
        snapshots, indexing). Only list units that exist on the host: setting
        Slice= on an undefined service creates an empty unit.
      '';
    };
    hostcriticalUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Services moved into hostcritical.slice: the ways back into the box
        (sshd, rescue sshd, tailscaled, tunnels) and systemd-oomd. Their RAM is
        guaranteed (code pages never evicted) and the kernel OOM killer picks
        them last. Takes effect when each unit restarts; access services are
        restartIfChanged = false, so in practice at the next reboot.
      '';
    };
    hostcriticalMin = lib.mkOption {
      type = lib.types.str;
      default = "1G";
      description = "Memory guaranteed to hostcritical.slice (MemoryMin).";
    };
  };

  config = lib.mkIf (cfg.enable && mem.enable) {
    systemd.slices."user-${uid}" = {
      # Created transiently by logind from user-.slice: must be a drop-in, a
      # full unit file would shadow the template.
      overrideStrategy = "asDropin";
      sliceConfig = {
        MemoryMax = mem.sessionMax;
        MemorySwapMax = "4G"; # don't let the session pin all of zram
      };
    };

    systemd.services = {
      # nixpkgs doesn't restart oomd when oomd.conf changes.
      systemd-oomd.restartTriggers = [ config.environment.etc."systemd/oomd.conf".text ];
      "user@${uid}" = {
        overrideStrategy = "asDropin";
        restartIfChanged = false; # as user@.service: never kill the session on switch
        serviceConfig = {
          MemoryMax = mem.agentsMax;
        };
      };
    }
    // lib.genAttrs mem.backgroundUnits (_: {
      serviceConfig.Slice = "background.slice";
    })
    // lib.genAttrs mem.hostcriticalUnits (_: {
      serviceConfig = {
        Slice = "hostcritical.slice";
        # Children inherit this; uid-1000 shells raise themselves back to 500
        # (hosts/harbor/oom.nix shellInit), so logins don't stay protected.
        OOMScoreAdjust = -900;
      };
    });

    systemd.slices.hostcritical = {
      description = "Remote access and OOM handling: guaranteed memory";
      sliceConfig.MemoryMin = mem.hostcriticalMin;
    };

    systemd.slices.background = {
      description = "Background jobs: builds, scrubs, backups, snapshots";
      sliceConfig = {
        MemoryMax = mem.backgroundMax;
        CPUWeight = 20; # default 100
        IOWeight = 20;
      };
    };

    # An OOM kill takes out one process, never the unit around it. Defaults are
    # "stop": one killed build would stop its whole tmux window or ssh session.
    systemd.user.settings.Manager.DefaultOOMPolicy = "continue";
    systemd.user.units."tmux-spawn-.scope" = {
      overrideStrategy = "asDropin";
      text = ''
        [Scope]
        MemoryMax=${mem.agentWindowMax}
        OOMPolicy=continue
      '';
    };
    systemd.units."session-.scope" = {
      overrideStrategy = "asDropin";
      text = ''
        [Scope]
        OOMPolicy=continue
      '';
    };
  };
}
