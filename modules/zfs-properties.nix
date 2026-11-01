{
  config,
  lib,
  ...
}:

# Declared ZFS dataset properties, applied at boot and on every switch.
# Only the listed properties are touched; everything else stays as it is.
# Datasets that aren't imported are skipped, not failed.
let
  cfg = config.services.zfsProperties;
  esc = lib.escapeShellArg;

  setProps =
    ds: props:
    ''
      if zfs list -H -o name ${esc ds} >/dev/null 2>&1; then
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (k: v: ''
        cur=$(zfs get -H -o value ${esc k} ${esc ds})
        if [ "$cur" != ${esc v} ]; then
          echo ${esc ds}": ${k} $cur -> ${v}"
          zfs set ${esc "${k}=${v}"} ${esc ds}
        fi
      '') props
    )
    + ''
      else
        echo ${esc ds}": not imported, skipped" >&2
      fi
    '';
in
{
  options.services.zfsProperties = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
    default = { };
    example = {
      tank = {
        atime = "off";
        recordsize = "1M";
      };
    };
    description = "ZFS properties to enforce, per dataset.";
  };

  config = lib.mkIf (cfg != { }) {
    systemd.services.zfs-properties = {
      description = "Apply declared ZFS dataset properties";
      after = [
        "zfs-import.target"
        "zfs-mount.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [ config.boot.zfs.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatStrings (lib.mapAttrsToList setProps cfg);
    };
  };
}
