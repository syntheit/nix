# construct backup: raven pushes /var/lib/construct to harbor every night; harbor keeps history and ships it offsite.
#
#   raven  construct-backup.service (03:30 ART): VACUUM INTO a staging snapshot (the DB is WAL: never cp it), rsync the
#          state dir (blobs, garmin tokens, memo audio, hunt exports) and then the snapshot as construct.db.
#   harbor /arespool/backups/construct: a plain mirror of /var/lib/construct. History = sanoid's arespool snapshots
#          (24 hourly, 30 daily, 12 monthly); offsite = the nightly restic job (hosts/harbor/storage.nix, 7d/4w/6m).
#          raven's key is forced to rrsync -wo: write-only into that one directory, no shell, no reads, and it can't
#          touch the ZFS snapshots, so a compromised raven can wipe the mirror but not the history.
#   alerts ntfy topic `backups` on vista (tailnet): raven posts when a run fails; harbor posts at noon ART when the
#          mirrored construct.db is older than 36 h (raven dead, timer never ran).
#
# RESTORE (harbor as matv reaches raven as droid; the mirror is readable by group users)
#   1. Pick a copy:  latest night  /arespool/backups/construct/
#                    older night   /arespool/.zfs/snapshot/autosnap_<YYYY-MM-DD>_*_daily/backups/construct/
#                    offsite       sudo restic -r <offsite repo, storage.nix> restore latest \
#                                    --include /arespool/backups/construct --target /tmp/r
#   2. raven:   sudo systemctl stop construct-life
#               rm -f /var/lib/construct/construct.db-wal /var/lib/construct/construct.db-shm   # a stale WAL would replay onto it
#   3. harbor:  rsync -a <copy>/ raven:/var/lib/construct/                     # DB snapshot + blobs + the rest
#               (DB only: rsync -a <copy>/construct.db raven:/var/lib/construct/; blobs only: add --ignore-existing)
#   4. raven:   sudo systemctl start construct-life
#   fdroid/ is not backed up here: harbor builds the repo (and holds its signing key) and re-publishes it with
#   construct-android-release.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.constructBackup;

  # notify <title>: posts stdin to the ntfy topic.
  notify = pkgs.writeShellScript "construct-backup-notify" ''
    ${pkgs.curl}/bin/curl -fsS --max-time 20 \
      -H "Title: $1" -H "Priority: high" -H "Tags: floppy_disk" \
      --data-binary @- ${lib.escapeShellArg cfg.ntfyUrl}
  '';

  push = cfg.push;
  sshCmd = lib.concatStringsSep " " [
    "ssh -F none"
    "-i ${config.sops.secrets.construct_backup_ssh_key.path}"
    "-p ${toString push.port}"
    "-o BatchMode=yes -o IdentitiesOnly=yes"
    "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/etc/ssh/ssh_known_hosts"
    "-o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=4"
  ];

  pushScript = pkgs.writeShellApplication {
    name = "construct-backup";
    runtimeInputs = [ pkgs.sqlite pkgs.rsync pkgs.openssh pkgs.coreutils ];
    text = ''
      src=${push.stateDir}
      stage="$STATE_DIRECTORY"
      remote=construct-backup@${push.host}
      ssh_cmd="${sshCmd}"

      echo "→ snapshot construct.db"
      rm -f "$stage/construct.db.tmp"
      sqlite3 -bail -cmd ".timeout 60000" "$src/construct.db" "VACUUM INTO '$stage/construct.db.tmp'"
      check=$(sqlite3 "$stage/construct.db.tmp" "PRAGMA quick_check;")
      if [ "$check" != ok ]; then
        echo "snapshot failed quick_check: $check" >&2
        exit 1
      fi
      mv -f "$stage/construct.db.tmp" "$stage/construct.db"

      # Unchanged files (every blob after its first night) are skipped on size + mtime. Excluded paths are also
      # protected from --delete on harbor, so the snapshot pushed below survives this pass.
      echo "→ push $src"
      rsync -a --delete --partial-dir=.rsync-partial --info=stats1 -e "$ssh_cmd" \
        --exclude=/construct.db --exclude=/construct.db-wal --exclude=/construct.db-shm --exclude=/construct.db-journal \
        --exclude=/fdroid/ --exclude='*.tmp' \
        "$src/" "$remote:./"

      # Last, so its mtime on harbor marks a complete run (harbor's staleness check reads it).
      echo "→ push snapshot"
      rsync -a --partial-dir=.rsync-partial -e "$ssh_cmd" "$stage/construct.db" "$remote:construct.db"
      echo "✓ construct backup done"
    '';
  };

  recv = cfg.receive;
in
{
  options.services.constructBackup = {
    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://100.96.21.56:2586/backups"; # vista's ntfy, tailnet only (hosts/vista/hunt.nix)
      description = "ntfy topic URL that failure alerts are posted to.";
    };

    push = {
      enable = lib.mkEnableOption "the nightly construct backup push (on the host running construct)";
      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/construct";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = config.services.constructLife.user;
        defaultText = lib.literalExpression "config.services.constructLife.user";
        description = "Reads the DB and state dir; owns the sops key construct_backup_ssh_key.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "harbor"; # MagicDNS
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 64829;
      };
      hostKey = lib.mkOption {
        type = lib.types.str;
        default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKkt8FCC7I+JxVVoBT80s9sTpulEtkFx4eFjkL1s64ia";
        description = "Pinned sshd host key of the receiving host.";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 03:30:00 America/Argentina/Buenos_Aires"; # done well before harbor's 03:00 New York restic run
      };
    };

    receive = {
      enable = lib.mkEnableOption "the construct backup landing directory (on the backup host)";
      dir = lib.mkOption {
        type = lib.types.str;
        default = "/arespool/backups/construct";
        description = "Mirror of the state dir. Must sit on a snapshotted dataset; history comes from those snapshots.";
      };
      authorizedKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public half of the pushing host's construct_backup_ssh_key; null = nobody can push yet.";
      };
      maxAgeHours = lib.mkOption {
        type = lib.types.int;
        default = 36;
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf push.enable {
      programs.ssh.knownHosts.construct-backup-target = {
        hostNames = [ "[${push.host}]:${toString push.port}" ];
        publicKey = push.hostKey;
      };

      systemd.services.construct-backup = {
        description = "Push construct's data to ${push.host}";
        after = [ "network-online.target" "tailscaled.service" ];
        wants = [ "network-online.target" ];
        onFailure = [ "construct-backup-notify.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = push.user;
          ExecStart = "${pushScript}/bin/construct-backup";
          StateDirectory = "construct-backup"; # staging snapshot
          StateDirectoryMode = "0700";
          Nice = 19;
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
          TimeoutStartSec = "8h"; # the first night carries every blob; --partial-dir resumes an interrupted run
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ push.stateDir ]; # opening a WAL database writes its -shm
          ProtectHome = true;
          NoNewPrivileges = true;
        };
      };

      systemd.timers.construct-backup = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = push.onCalendar;
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
      };

      systemd.services.construct-backup-notify = {
        description = "Alert: construct backup failed";
        path = [ pkgs.systemd ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          SupplementaryGroups = [ "systemd-journal" ];
        };
        script = ''
          journalctl -u construct-backup.service -n 15 --no-pager -o cat \
            | ${notify} "construct backup failed on ${config.networking.hostName}"
        '';
      };
    })

    (lib.mkIf recv.enable {
      warnings = lib.optional (recv.authorizedKey == null)
        "services.constructBackup.receive.authorizedKey is unset: raven's nightly construct backup can't log in yet.";

      users.groups.construct-backup = { };
      users.users.construct-backup = {
        isSystemUser = true;
        group = "construct-backup";
        home = "/var/empty";
        shell = "${pkgs.bash}/bin/bash"; # rrsync needs a login shell to exec the forced command
        openssh.authorizedKeys.keys = lib.optional (recv.authorizedKey != null)
          ''restrict,command="${pkgs.rrsync}/bin/rrsync -wo -munge ${recv.dir}" ${recv.authorizedKey}'';
      };

      # Group users: matv reads the mirror for restores without sudo.
      systemd.tmpfiles.rules = [
        "d ${builtins.dirOf recv.dir} 0755 root root -"
        "d ${recv.dir} 0750 construct-backup users -"
      ];

      # Catches what raven can't report itself: raven down, timer not firing, tailnet broken for days.
      systemd.services.construct-backup-check = {
        description = "Alert if the construct backup mirror is stale";
        path = [ pkgs.coreutils pkgs.findutils ];
        serviceConfig = {
          Type = "oneshot";
          User = "construct-backup";
        };
        script = ''
          db=${recv.dir}/construct.db
          if [ ! -e "$db" ]; then
            msg="no snapshot at $db yet"
          elif [ -z "$(find "$db" -mmin -${toString (recv.maxAgeHours * 60)})" ]; then
            msg="newest snapshot is from $(date -r "$db" '+%F %R %Z'), over ${toString recv.maxAgeHours} h old"
          else
            echo "fresh: $(date -r "$db" '+%F %R %Z')"
            exit 0
          fi
          echo "$msg"
          echo "$msg" | ${notify} "construct backup stale on ${config.networking.hostName}"
          exit 1
        '';
      };
      systemd.timers.construct-backup-check = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 12:00:00 America/Argentina/Buenos_Aires";
          Persistent = true;
        };
      };
    })
  ];
}
