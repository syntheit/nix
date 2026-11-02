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

    environment.systemPackages = [ makeSubvolume ];
  };
}
