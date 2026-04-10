{ ... }:

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
  };
}
