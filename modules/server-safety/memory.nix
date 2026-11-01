{ config, lib, ... }:

# Memory tiers: interactive/dev work and background jobs get hard ceilings, so
# a runaway is killed inside its own space before the box stalls. Production
# (system.slice) is never an oomd target. Plan: ~/contexts/fleet-resilience.md.
#
#   user-<uid>.slice         logins, tmux, agents     hard cap (sessionMax)
#     user@<uid>.service     tmux + agents            hard cap (agentsMax)
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
    swapKill = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Kill the user cgroup holding the most swap once system swap passes
        oomd's SwapUsedLimit (90%). Turn off while swap sits near that limit
        for reasons outside the user session (e.g. cold production pages in an
        undersized zram), or it kills agents for someone else's swap.
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
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "50%";
        };
      };
    }
    // lib.genAttrs mem.backgroundUnits (_: {
      serviceConfig.Slice = "background.slice";
    });

    systemd.slices.background = {
      description = "Background jobs: builds, scrubs, backups, snapshots";
      sliceConfig = {
        MemoryMax = mem.backgroundMax;
        CPUWeight = 20; # default 100
        IOWeight = 20;
      };
    };

    # oomd acts in user slices only; system.slice (prod) is never a target.
    systemd.oomd = {
      enableUserSlices = true;
      settings.OOM.DefaultMemoryPressureDurationSec = "20s";
    };
    # enableUserSlices defaults to 80% pressure, which never fired on harbor.
    # Upstream suggests ~40-50% for user sessions.
    systemd.slices.user.sliceConfig = {
      ManagedOOMMemoryPressureLimit = "50%";
    }
    // lib.optionalAttrs mem.swapKill {
      # zram nearly full = no headroom left. Kill the user cgroup holding the
      # most swap (system-wide SwapUsedLimit, default 90%).
      ManagedOOMSwap = "kill";
    };
    systemd.user.units."slice".text = lib.mkForce ''
      [Slice]
      ManagedOOMMemoryPressure=kill
      ManagedOOMMemoryPressureLimit=50%
    '';
  };
}
