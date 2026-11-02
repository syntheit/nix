{
  config,
  lib,
  pkgs,
  ...
}:

# Disk hygiene: regenerable data (dependencies, build output, caches, the Nix
# store) is never snapshotted, indexed or backed up, and garbage is collected
# often. Plan: ~/contexts/fleet-resilience.md ("Disk hygiene").
#
# Snapshots (btrbk) work per subvolume, so regenerable directories become their
# own btrfs subvolumes: a snapshot of `@` leaves nested subvolumes out, so
# deletions there free space immediately instead of being pinned for weeks.
# New hosts get them from tmpfiles `v` rules; existing directories are
# converted once with `make-subvolume <dir>` (reflink copy, then swap).
let
  cfg = config.diskHygiene;

  # Names skipped by indexing (and by backups, where a host has them).
  regenerableNames = [
    "node_modules"
    ".direnv"
    ".venv"
    "venv"
    "__pycache__"
    "target"
    ".next"
    ".nuxt"
    ".turbo"
    ".gradle"
    ".pnpm-store"
    ".cache"
    ".npm"
    ".cargo"
  ];

  makeSubvolume = pkgs.writeShellApplication {
    name = "make-subvolume";
    runtimeInputs = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      # make-subvolume DIR: turn an existing directory on btrfs into its own
      # subvolume (left out of snapshots of the parent). Reflink copy, so it
      # costs no extra space. The old directory stays as DIR.pre-subvolume
      # until you delete it. Close anything writing to DIR first.
      d=$(realpath "$1")
      [ -d "$d" ] || { echo "not a directory: $d" >&2; exit 1; }
      [ "$(stat -f -c %T "$d")" = btrfs ] || { echo "not on btrfs: $d" >&2; exit 1; }
      if [ "$(stat -c %i "$d")" = 256 ]; then echo "already a subvolume: $d"; exit 0; fi
      new="$d.subvolume-new"; old="$d.pre-subvolume"
      [ ! -e "$new" ] && [ ! -e "$old" ] || { echo "leftover $new or $old, clean up first" >&2; exit 1; }
      btrfs subvolume create "$new" >/dev/null
      chown --reference="$d" "$new"; chmod --reference="$d" "$new"
      cp -a --reflink=always "$d/." "$new/"
      mv "$d" "$old"; mv "$new" "$d"
      echo "subvolume: $d  (old copy: $old; delete it once things work)"
    '';
  };

  stale = cfg.staleBuildOutput;
  pruneEnabled = stale.roots != [ ] || stale.goCaches != [ ];
  pruneBuildOutput = pkgs.writeShellApplication {
    name = "prune-build-output";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
    ];
    text = ''
      # prune-build-output [--dry-run]: delete build output from projects whose
      # own files (outside build output and .git) are all older than the cutoff.
      # A project is the git worktree holding the build dir, else its parent.
      dry=0; [ "''${1:-}" = --dry-run ] && dry=1
      days=${toString stale.days}
      declare -A active=()
      for root in ${lib.escapeShellArgs stale.roots}; do
        [ -d "$root" ] || continue
        while IFS= read -r -d "" d; do
          name=$(basename "$d")
          # Only Cargo's target dirs (they carry CACHEDIR.TAG).
          if [ "$name" = target ] && [ ! -e "$d/CACHEDIR.TAG" ]; then continue; fi
          parent=$(dirname "$d")
          top=$(git -C "$parent" rev-parse --show-toplevel 2>/dev/null || echo "$parent")
          if [ -z "''${active[$top]+x}" ]; then
            if [ -n "$(find "$top" -xdev \( -name node_modules -o -name .next -o -name .turbo -o -name target -o -name .git \) -prune -o -type f -mtime "-$days" -print -quit 2>/dev/null)" ]; then
              active[$top]=1
            else
              active[$top]=0
            fi
          fi
          [ "''${active[$top]}" = 0 ] || continue
          echo "$(du -sh "$d" 2>/dev/null | cut -f1)	$d"
          [ "$dry" = 1 ] || rm -rf --one-file-system "$d" || echo "failed: $d" >&2
        done < <(find "$root" -xdev -type d \( -name node_modules -o -name .next -o -name .turbo -o -name target \) -prune -print0 2>/dev/null)
      done
      for c in ${lib.escapeShellArgs stale.goCaches}; do
        [ -d "$c" ] || continue
        echo "go cache $c: $(find "$c" -type f -mtime "+$days" | wc -l) entries older than $days days"
        [ "$dry" = 1 ] || find "$c" -type f -mtime "+$days" -delete || true
      done
    '';
  };
in
{
  options.diskHygiene = {
    enable = lib.mkEnableOption "disk hygiene (GC, index exclusions, cache subvolumes)";
    subvolumes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption { type = lib.types.str; };
            user = lib.mkOption {
              type = lib.types.str;
              default = "root";
            };
            # Explicit: for an existing directory a `v` rule also applies
            # owner, group and mode, and an omitted group would mean root.
            group = lib.mkOption {
              type = lib.types.str;
              default = "root";
            };
            mode = lib.mkOption {
              type = lib.types.str;
              default = "0755";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Regenerable directories kept as their own btrfs subvolumes so snapshots
        of the parent skip them. Created if missing; convert existing ones once
        with `make-subvolume`.
      '';
    };
    staleBuildOutput = {
      roots = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Directories holding projects/worktrees. Weekly, build output
          (node_modules, .next, .turbo, Cargo target) is deleted from projects
          whose own files haven't changed in `days` days. Sources and git
          state are left alone.
        '';
      };
      goCaches = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "GOCACHE dirs: entries unused for `days` days are deleted (Go touches entries on use).";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
      };
      days = lib.mkOption {
        type = lib.types.int;
        default = 14;
      };
    };
    gcDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Delete Nix generations and store paths older than this many days (daily GC).";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than ${toString cfg.gcDays}d";
    };

    services.locate = lib.mkIf config.services.locate.enable {
      # nixpkgs defaults plus the btrfs top level, snapshot dirs, container
      # storage and ZFS/mergerfs data pools are host-specific (extend per host).
      prunePaths = [
        "/tmp"
        "/var/tmp"
        "/var/cache"
        "/var/lock"
        "/var/run"
        "/var/spool"
        "/nix/store"
        "/nix/var/log/nix"
        "/mnt/btrfs-root"
        "/.snapshots"
        "/var/lib/docker"
        "/var/lib/containers"
      ];
      pruneNames = [
        ".bzr"
        ".git"
        ".hg"
        ".svn"
      ]
      ++ regenerableNames;
    };

    systemd.tmpfiles.rules = map (s: "v ${s.path} ${s.mode} ${s.user} ${s.group} -") cfg.subvolumes;

    environment.systemPackages = [ makeSubvolume ] ++ lib.optional pruneEnabled pruneBuildOutput;

    systemd.services.prune-build-output = lib.mkIf pruneEnabled {
      description = "Delete build output from projects untouched for ${toString stale.days} days";
      serviceConfig = {
        Type = "oneshot";
        User = stale.user;
        ExecStart = "${lib.getExe pruneBuildOutput}";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };
    systemd.timers.prune-build-output = lib.mkIf pruneEnabled {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
