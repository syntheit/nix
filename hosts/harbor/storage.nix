{ config, pkgs, ... }:

{
  services = {
    # SMART drive monitoring
    smartd = {
      enable = true;
      autodetect = true;
      notifications.wall.enable = true;
    };
    # ZFS scrubs — detect silent data corruption. One pool at a time, spread
    # over the month (modules/zfs-scrub.nix); autoScrub scrubbed all 8 at once
    # and stalled the box on 2026-11-01.
    zfs.autoScrub.enable = false;
    zfsScrub = {
      enable = true;
      pools = [
        "arespool"
        "deltapool"
        "epsilpool"
        "iotapool"
        "lambdapool"
        "platapool"
        "rhopool"
        "thetapool"
      ];
    };
    # BTRFS periodic scrub on root filesystem (~3 min). Off the 1st, where it
    # used to pile onto the ZFS scrubs.
    btrfs.autoScrub = {
      enable = true;
      interval = "*-*-26 03:00";
      fileSystems = [ "/" ];
    };
    # Dataset properties, enforced at boot and on switch (modules/zfs-properties.nix).
    # atime=off: Jellyfin/*arr scans read every file; atime turns that into
    # metadata writes on the HDDs and snapshot churn.
    # recordsize=1M: media is large sequential files — less metadata, faster
    # streaming, smaller scrub queues. Affects new writes only.
    zfsProperties =
      let
        base = {
          atime = "off";
          dnodesize = "auto";
        };
        media = base // {
          recordsize = "1M";
          compression = "zstd";
        };
      in
      {
        arespool = base;
        deltapool = media;
        epsilpool = media;
        iotapool = media;
        lambdapool = media;
        platapool = media;
        thetapool = media;
        # rhopool takes every torrent download: 16 KiB pieces landing in 1M
        # records means read-modify-write against an uncached HDD
        # (primarycache=metadata). Gets `media` once downloads move off it.
        rhopool = base // {
          compression = "zstd";
        };
      };
    # BTRFS automated snapshots on root
    btrbk.instances."default" = {
      onCalendar = "daily";
      settings = {
        snapshot_preserve_min = "2d";
        # 3 dailies only: each snapshot pins everything deleted after it, and
        # "7d 4w" filled the 500 GB root twice in Oct 2026. Data is in restic.
        snapshot_preserve = "3d";
        volume."/mnt/btrfs-root" = {
          subvolume."@" = { snapshot_dir = "@snapshots"; };
        };
      };
    };
    # ZFS automated snapshots
    sanoid = {
      enable = true;
      interval = "hourly";
      datasets = {
        # App data — critical, changes frequently
        "arespool" = {
          autosnap = true;
          autoprune = true;
          hourly = 24;
          daily = 30;
          monthly = 12;
          recursive = true;
        };
        # Media pools — write-once content, fewer snapshots needed
        "deltapool" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
          recursive = true;
        };
        "epsilpool" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
          recursive = true;
        };
        "iotapool" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
          recursive = true;
        };
        "lambdapool" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
          recursive = true;
        };
        "thetapool" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
          recursive = true;
        };
        "rhopool" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
          recursive = true;
        };
        "platapool" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
          recursive = true;
        };
        # syncoid target: sanoid must not snapshot it (breaks incrementals),
        # only prune the snapshots replicated from platapool/seafile
        "iotapool/seafile-replica" = {
          autosnap = false;
          autoprune = true;
          hourly = 0;
          daily = 7;
          monthly = 3;
        };
      };
    };

    # Hourly replica of the Seafile store onto a second disk. -u: the syncoid
    # user can't mount, so receive unmounted.
    syncoid = {
      enable = true;
      commands."platapool/seafile" = {
        target = "iotapool/seafile-replica";
        recvOptions = "u";
        # Defaults + destroy, so syncoid can prune its own old sync snapshots
        # on the target. Without it every run failed to (~936 "permission
        # denied" per hour) and 937 snapshots piled up since 2026-09.
        localTargetAllow = [
          "change-key"
          "compression"
          "create"
          "mount"
          "mountpoint"
          "receive"
          "rollback"
          "destroy"
        ];
      };
    };

    # =====================================================
    # OFFSITE BACKUPS (restic → friend's VM)
    # Encrypted, compressed, deduplicated. Daily at 3 AM.
    # =====================================================
    restic.backups.offsite = {
      repository = "sftp:daniel_backups@beta.mregirouard.com:/home/daniel_backups/harbor-backup";
      passwordFile = config.sops.secrets.restic_backup_password.path;
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "30min";
        Persistent = true; # Run if missed (e.g. server was off)
      };

      paths = [
        # Service configs and databases
        "/arespool/appdata/immich"
        "/arespool/appdata/nextcloud_config"
        "/arespool/appdata/nextcloud-mariadb"
        "/arespool/appdata/vaultwarden"
        "/arespool/appdata/linkding"
        "/arespool/appdata/memos"
        "/arespool/appdata/syncthing"
        "/arespool/appdata/srcutiny"
        "/arespool/appdata/qbittorrent"
        "/arespool/appdata/vpn"
        "/arespool/appdata/jellyseerr_config"
        "/arespool/photos-videos"
        "/arespool/appdata/karakeep"
        "/arespool/appdata/docmost"
        "/arespool/appdata/couchdb"
        "/arespool/appdata/prowlarr"

        # Radarr/Sonarr/Bazarr (DBs only, exclude MediaCover)
        "/arespool/appdata/radarr"
        "/arespool/appdata/sonarr"
        "/arespool/appdata/bazarr"

        # Jellyfin (DB + config only, exclude metadata/cache)
        "/arespool/appdata/jellyfin_config"

        # Radicale (contacts + calendars)
        "/arespool/appdata/radicale"

        # Seerr (native NixOS service)
        "/var/lib/private/jellyseerr"

        # Paperless-ngx (native NixOS service)
        "/arespool/appdata/paperless"

        # Grafana (native NixOS service)
        "/var/lib/grafana"

        # Seafile (file data + config + MariaDB)
        "/arespool/appdata/seafile"
        "/platapool/seafile"

        # Pelican game servers (panel config, MariaDB, Wings config + game data)
        "/arespool/appdata/pelican"

        # DB dumps (created by pre-backup hook)
        "/var/lib/harbor-backups/db-dumps"

        # Docker named volumes
        "/var/lib/docker/volumes/retrospend_postgres_data"
        "/var/lib/docker/volumes/retrospend_uploads"
        "/var/lib/docker/volumes/retrospend_sidecar_data"
        "/var/lib/docker/volumes/retrospend_backup_data"
        "/var/lib/docker/volumes/retrospend_ollama_data"
        "/var/lib/docker/volumes/tracearr_tracearr_postgres"
        "/var/lib/docker/volumes/tracearr_tracearr_data"
        "/var/lib/docker/volumes/tracearr_tracearr_redis"
        "/var/lib/docker/volumes/karakeep_meilisearch_data"
        "/var/lib/docker/volumes/docmost_redis_data"
      ];

      exclude = [
        # Regenerable poster/backdrop caches (~30GB)
        "**/MediaCover"
        "**/metadata"
        # Caches and temp files
        "**/cache"
        "**/Cache"
        # Logs
        "**/logs"
        "**/*.log"
        "**/logs.db"
        # Transcoding temp
        "**/transcodes"
        # Trickplay images (regenerable)
        "**/trickplay"
        # Backup copies we made manually
        "**/*_backup_*"
        # Ben's Seafile video library: local copies only, too big for the offsite box
        "**/storage/*/fba8e833-530e-45c8-bf47-dab245445e79"
      ];

      extraOptions = [
        "sftp.command='ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i /home/matv/.ssh/mainkey daniel_backups@beta.mregirouard.com -s sftp'"
      ];

      extraBackupArgs = [
        "--compression=auto"
        "--verbose"
        "--retry-lock=5m"
      ];

      # Dump databases before backing up. Each dump goes to a temp file and only
      # replaces the previous one if it succeeded and isn't empty: a failed dump
      # used to truncate the last good one (`> file || true`), so a container
      # that was down at 03:00 meant an empty dump in that night's snapshot.
      backupPrepareCommand = ''
        echo "Clearing any stale repo locks..."
        ${pkgs.restic}/bin/restic unlock \
          -o sftp.command='ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i /home/matv/.ssh/mainkey daniel_backups@beta.mregirouard.com -s sftp' || true

        dumps=/var/lib/harbor-backups/db-dumps
        ${pkgs.coreutils}/bin/mkdir -p "$dumps"

        # dump <file> <command...>: keep the previous dump if this one fails.
        dump() {
          local out="$dumps/$1"; shift
          echo "Dumping $(basename "$out")..."
          if "$@" > "$out.tmp" 2> "$out.err" && [ -s "$out.tmp" ]; then
            mv "$out.tmp" "$out"
            rm -f "$out.err"
          else
            echo "WARNING: dump to $out failed; keeping previous dump:" >&2
            cat "$out.err" >&2
            rm -f "$out.tmp" "$out.err"
          fi
        }

        dump immich.sql ${pkgs.docker}/bin/docker exec immich_postgres pg_dump -U postgres immich
        dump retrospend.sql ${pkgs.docker}/bin/docker exec retrospend_postgres pg_dump -U postgres retrospend
        dump docmost.sql ${pkgs.docker}/bin/docker exec docmost_postgres pg_dump -U docmost docmost
        dump pelican.sql ${pkgs.docker}/bin/docker exec pelican_db sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases'
        dump seafile.sql ${pkgs.docker}/bin/docker exec seafile_db sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases'

        # sqlite3 .backup writes the file itself, so it can't go through dump().
        echo "Dumping paperless.sqlite3..."
        if ${pkgs.sqlite}/bin/sqlite3 /arespool/appdata/paperless/db.sqlite3 \
          ".backup '$dumps/paperless.sqlite3.tmp'"; then
          mv "$dumps/paperless.sqlite3.tmp" "$dumps/paperless.sqlite3"
        else
          echo "WARNING: paperless sqlite backup failed; keeping previous" >&2
          rm -f "$dumps/paperless.sqlite3.tmp"
        fi

        # Nextcloud was retired (its container is gone); its last real DB copy
        # is the raw data dir /arespool/appdata/nextcloud-mariadb, still in paths.
        echo "DB dumps complete."
      '';

      # Retention policy: 7 daily, 4 weekly, 6 monthly
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
    };
  };

  # Weekly integrity check: reads 1/10 of stored data and verifies its hashes
  # (full coverage every ~10 weeks). It used to run after every nightly backup
  # with a 30 min cap and overran it (2026-11-01), leaving a stale repo lock.
  # Its own unit now: a slow check no longer fails the backup.
  systemd.services.restic-check-offsite = {
    description = "Verify offsite restic repository integrity";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "6h";
    };
    script =
      let
        sftp = "sftp.command='ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i /home/matv/.ssh/mainkey daniel_backups@beta.mregirouard.com -s sftp'";
      in
      ''
        ${pkgs.restic}/bin/restic unlock -o ${sftp} || true
        ${pkgs.restic}/bin/restic check --read-data-subset=1/10 -o ${sftp}
      '';
    environment = {
      RESTIC_REPOSITORY = config.services.restic.backups.offsite.repository;
      RESTIC_PASSWORD_FILE = config.services.restic.backups.offsite.passwordFile;
    };
  };
  systemd.timers.restic-check-offsite = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 06:00";
      Persistent = true;
    };
  };

  # =====================================================
  # MERGERFS — union mount across HDD pools at /media
  # =====================================================
  # Each HDD pool has /<pool>/media/{movies,shows,downloads}. mergerfs unions
  # them so Sonarr/Radarr/Jellyfin/qbit see a single /media tree. Per-pool
  # ZFS snapshots, scrubs, and SMART monitoring all keep working unchanged.
  # Underlying pools remain accessible at /<pool> directly.
  system.fsPackages = [ pkgs.mergerfs ];

  # ~/Projects lives on its own ZFS dataset. Legacy mount through fileSystems,
  # so systemd orders units under this path after it.
  # nofail: a failed arespool import must not drop boot into emergency mode (no sshd).
  # before= keeps the local-fs.target ordering that nofail drops.
  fileSystems."/home/matv/Projects" = {
    device = "arespool/projects";
    fsType = "zfs";
    options = [ "nofail" "x-systemd.before=local-fs.target" ];
  };

  fileSystems."/media" = {
    device = builtins.concatStringsSep ":" [
      "/deltapool/media"
      "/epsilpool/media"
      "/iotapool/media"
      "/lambdapool/media"
      "/platapool/media"
      "/rhopool/media"
      "/thetapool/media"
    ];
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      # cache.files=auto-full lets the kernel page cache back mergerfs reads —
      # huge win for Jellyfin scans/streams since `partial` round-trips every
      # page through FUSE. dropcacheonclose=true keeps memory bounded by
      # evicting page cache when files are closed (prevents double-caching
      # against ZFS ARC).
      "cache.files=auto-full"
      "dropcacheonclose=true"
      # Concurrent readdir across branches — collapses 7-pool serial enumeration
      # into parallel calls, drops library-scan wallclock dramatically.
      "func.readdir=cor"
      "category.create=pfrd"      # 2.41 default — weighted random favoring emptier branches
      # Stop placing new files on a branch below 1.5 TB free (~9%): ZFS on
      # single HDDs slows sharply past ~90% full.
      "minfreespace=1500G"
      "fsname=mergerfs"
      "inodecalc=path-hash"        # stable inodes across remounts (NFS-friendly)
      # A dead pool must not drop boot into emergency mode (no sshd);
      # before= keeps the local-fs.target ordering that nofail drops.
      "nofail"
      "x-systemd.before=local-fs.target"
    ];
    depends = [
      "/deltapool"
      "/epsilpool"
      "/iotapool"
      "/lambdapool"
      "/platapool"
      "/rhopool"
      "/thetapool"
    ];
    noCheck = true;
  };

  # Ensure each branch has the canonical media subtree. With every branch
  # exposing /movies, /shows, /downloads, mergerfs's link/rename functions
  # can always find a same-branch destination — keeping *arr's hardlink
  # imports atomic instead of falling back to copy.
  systemd.tmpfiles.rules =
    let
      pools = [ "delta" "epsil" "iota" "lambda" "plata" "rho" "theta" ];
      cats  = [ "" "/movies" "/shows" "/downloads" ];
    in
      builtins.concatMap (p:
        builtins.map (c: "d /${p}pool/media${c} 0775 matv users -") cats
      ) pools;
}
