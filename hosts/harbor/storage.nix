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
        "/arespool/appdata/bitwarden"
        "/arespool/appdata/bitwarden_db"
        "/arespool/appdata/linkding"
        "/arespool/appdata/memos"
        "/arespool/appdata/syncthing"
        "/arespool/appdata/srcutiny"
        "/arespool/appdata/qbittorrent"
        "/arespool/appdata/vpn"
        "/arespool/appdata/jellyseerr_config"
        "/arespool/photos-videos"

        # Radarr/Sonarr/Bazarr/Jackett (DBs only, exclude MediaCover)
        "/arespool/appdata/radarr"
        "/arespool/appdata/sonarr"
        "/arespool/appdata/bazarr"
        "/arespool/appdata/jackett"

        # Jellyfin (DB + config only, exclude metadata/cache)
        "/arespool/appdata/jellyfin_config"

        # Seerr (native NixOS service)
        "/var/lib/private/jellyseerr"

        # DB dumps (created by pre-backup hook)
        "/var/lib/harbor-backups/db-dumps"

        # Docker named volumes (retrospend, tracearr, bitwarden)
        "/var/lib/docker/volumes/retrospend_postgres_data"
        "/var/lib/docker/volumes/retrospend_uploads"
        "/var/lib/docker/volumes/retrospend_sidecar_data"
        "/var/lib/docker/volumes/retrospend_backup_data"
        "/var/lib/docker/volumes/retrospend_importer_data"
        "/var/lib/docker/volumes/tracearr_tracearr_postgres"
        "/var/lib/docker/volumes/tracearr_tracearr_data"
        "/var/lib/docker/volumes/bitwarden_data"
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
        "sftp.command='ssh -i /home/matv/.ssh/mainkey daniel_backups@beta.mregirouard.com -s sftp'"
      ];

      extraBackupArgs = [
        "--compression=auto"
        "--verbose"
      ];

      # Dump databases before backing up
      backupPrepareCommand = ''
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

        echo "Dumping Bitwarden MariaDB..."
        ${pkgs.docker}/bin/docker exec bitwarden_db sh -c 'mariadb-dump -u bitwarden -p"$MARIADB_PASSWORD" bitwarden_vault' \
          > /var/lib/harbor-backups/db-dumps/bitwarden.sql 2>/dev/null || true

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
}
