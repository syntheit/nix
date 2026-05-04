{ config, pkgs, ... }:

{
  services = {
    # SMART drive monitoring
    smartd = {
      enable = true;
      autodetect = true;
      notifications.wall.enable = true;
    };
    # ZFS automatic scrub — detects silent data corruption
    zfs.autoScrub = {
      enable = true;
      interval = "monthly";
    };
    # BTRFS periodic scrub on root filesystem
    btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = [ "/" ];
    };
    # BTRFS automated snapshots on root
    btrbk.instances."default" = {
      onCalendar = "daily";
      settings = {
        snapshot_preserve_min = "2d";
        snapshot_preserve = "7d 4w";
        volume."/" = {
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
      ];

      extraOptions = [
        "sftp.command='ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i /home/matv/.ssh/mainkey daniel_backups@beta.mregirouard.com -s sftp'"
      ];

      extraBackupArgs = [
        "--compression=auto"
        "--verbose"
        "--retry-lock=5m"
      ];

      # Dump databases before backing up
      backupPrepareCommand = ''
        echo "Clearing any stale repo locks..."
        ${pkgs.restic}/bin/restic unlock \
          -o sftp.command='ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i /home/matv/.ssh/mainkey daniel_backups@beta.mregirouard.com -s sftp' || true

        ${pkgs.coreutils}/bin/mkdir -p /var/lib/harbor-backups/db-dumps

        echo "Dumping Immich postgres..."
        ${pkgs.docker}/bin/docker exec immich_postgres pg_dump -U postgres immich \
          > /var/lib/harbor-backups/db-dumps/immich.sql 2>/dev/null || true

        echo "Dumping Retrospend postgres..."
        ${pkgs.docker}/bin/docker exec retrospend_postgres pg_dump -U postgres retrospend \
          > /var/lib/harbor-backups/db-dumps/retrospend.sql 2>/dev/null || true

        echo "Dumping Nextcloud MariaDB..."
        ${pkgs.docker}/bin/docker exec nextcloud_db sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' \
          > /var/lib/harbor-backups/db-dumps/nextcloud.sql 2>/dev/null || true

        echo "Dumping Docmost postgres..."
        ${pkgs.docker}/bin/docker exec docmost_postgres pg_dump -U docmost docmost \
          > /var/lib/harbor-backups/db-dumps/docmost.sql 2>/dev/null || true

        echo "Dumping Pelican MariaDB..."
        ${pkgs.docker}/bin/docker exec pelican_db sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' \
          > /var/lib/harbor-backups/db-dumps/pelican.sql 2>/dev/null || true

        echo "Dumping Seafile MariaDB..."
        ${pkgs.docker}/bin/docker exec seafile_db sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' \
          > /var/lib/harbor-backups/db-dumps/seafile.sql 2>/dev/null || true

        echo "Dumping Paperless SQLite..."
        ${pkgs.sqlite}/bin/sqlite3 /arespool/appdata/paperless/db.sqlite3 \
          ".backup '/var/lib/harbor-backups/db-dumps/paperless.sqlite3'" 2>/dev/null || true

        echo "DB dumps complete."
      '';

      # Verify backup integrity after each run — reads 1/20 of stored data
      # and checks SHA-256 hashes. Full coverage over ~20 daily backups.
      backupCleanupCommand = ''
        echo "Verifying backup integrity (reading 1/20 of data)..."
        ${pkgs.restic}/bin/restic check \
          --read-data-subset=1/20 \
          -o sftp.command='ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -i /home/matv/.ssh/mainkey daniel_backups@beta.mregirouard.com -s sftp'
        echo "Integrity check passed."
      '';

      # Retention policy: 7 daily, 4 weekly, 6 monthly
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
    };
  };

  # Give the post-backup integrity check enough time to download and verify
  # data over SFTP. The default TimeoutStopSec=90s kills it mid-check.
  systemd.services.restic-backups-offsite.serviceConfig.TimeoutStopSec = "30min";

  # =====================================================
  # MERGERFS — union mount across HDD pools at /media
  # =====================================================
  # Each HDD pool has /<pool>/media/{movies,shows,downloads}. mergerfs unions
  # them so Sonarr/Radarr/Jellyfin/qbit see a single /media tree. Per-pool
  # ZFS snapshots, scrubs, and SMART monitoring all keep working unchanged.
  # Underlying pools remain accessible at /<pool> directly.
  system.fsPackages = [ pkgs.mergerfs ];

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
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=pfrd"      # 2.41 default — weighted random favoring emptier branches
      "minfreespace=20G"           # don't write to nearly-full branches
      "fsname=mergerfs"
      "inodecalc=path-hash"        # stable inodes across remounts (NFS-friendly)
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
