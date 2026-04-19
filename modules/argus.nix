# Argus — container update manager
# Replaces Watchtower with systemd-native image updates, pre-update database backups, and rollback.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.argus;
  ociContainers = config.virtualisation.oci-containers.containers;

  backupSubmodule = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [ "postgres" "mariadb" ];
        description = "Database type";
      };
      container = lib.mkOption {
        type = lib.types.str;
        description = "Docker container running the database";
      };
      database = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Database name (required for postgres)";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        description = "Database user (required for postgres)";
      };
    };
  };

  containerSubmodule = lib.types.submodule {
    options = {
      policy = lib.mkOption {
        type = lib.types.enum [ "auto" "manual" ];
        default = "auto";
        description = "auto = updated by timer, manual = check only";
      };
      backups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Backup names (from services.argus.backups) to run before updating";
      };
    };
  };

  # Build the full container config: explicit entries + defaults for unlisted ones
  managedContainerNames = lib.filter
    (name: ! builtins.elem name cfg.exclude)
    (builtins.attrNames ociContainers);

  containerConfigs = lib.listToAttrs (map
    (name:
      let
        explicit = cfg.containers.${name} or { policy = "auto"; backups = [ ]; };
      in
      {
        inherit name;
        value = {
          image = ociContainers.${name}.image;
          policy = explicit.policy;
          backups = explicit.backups;
        };
      })
    managedContainerNames);

  configJson = builtins.toJSON {
    containers = containerConfigs;
    backups = lib.mapAttrs (_: b: {
      inherit (b) type container database user;
    }) cfg.backups;
    retention = cfg.retention;
  };
in
{
  options.services.argus = {
    enable = lib.mkEnableOption "Argus container update manager";

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 04:00:00";
      description = "systemd calendar expression for automatic update checks";
    };

    retention = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Number of pre-update database backups to retain per backup name";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Container names to exclude entirely from Argus management";
    };

    containers = lib.mkOption {
      type = lib.types.attrsOf containerSubmodule;
      default = { };
      description = "Per-container update configuration. Unlisted containers default to auto with no backups.";
    };

    backups = lib.mkOption {
      type = lib.types.attrsOf backupSubmodule;
      default = { };
      description = "Database backup definitions, referenced by name from container configs";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      # Every explicitly configured container must exist in oci-containers
      (map
        (name: {
          assertion = builtins.hasAttr name ociContainers;
          message = "Argus: container '${name}' is configured but not defined in virtualisation.oci-containers.containers";
        })
        (builtins.attrNames cfg.containers))
      ++
      # Every excluded container must exist
      (map
        (name: {
          assertion = builtins.hasAttr name ociContainers;
          message = "Argus: excluded container '${name}' is not defined in virtualisation.oci-containers.containers";
        })
        cfg.exclude)
      ++
      # Every backup reference must point to a valid backup name
      (lib.concatMap
        (name:
          map
            (backupName: {
              assertion = builtins.hasAttr backupName cfg.backups;
              message = "Argus: container '${name}' references backup '${backupName}' which is not defined";
            })
            (cfg.containers.${name} or { backups = [ ]; }).backups)
        (builtins.attrNames cfg.containers))
      ++
      # Postgres backups must have database and user
      (map
        (name: {
          assertion = cfg.backups.${name}.type != "postgres" || (cfg.backups.${name}.database != "" && cfg.backups.${name}.user != "");
          message = "Argus: postgres backup '${name}' must specify both 'database' and 'user'";
        })
        (builtins.attrNames cfg.backups));

    # Generated config file
    environment.etc."argus/config.json".text = configJson;

    # CLI available system-wide
    environment.systemPackages = [ pkgs.argus ];

    # State and backup directories
    systemd.tmpfiles.rules = [
      "d /var/lib/argus 0755 root root -"
      "d /var/lib/argus/state 0755 root root -"
      "d /var/lib/argus/backups 0750 root root -"
    ];

    # Automatic update service
    systemd.services.argus-auto = {
      description = "Argus automatic container update";
      after = [ "docker.service" "network-online.target" ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.argus}/bin/argus auto";
        TimeoutStartSec = "30min";
      };
    };

    # Daily timer
    systemd.timers.argus-auto = {
      description = "Argus daily container update timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
