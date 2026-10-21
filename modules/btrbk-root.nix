# btrbk-root — mount the btrfs top level so btrbk can snapshot the root subvol
#
# Hosts with `/` on btrfs `subvol=@` only expose the inside of @, so a btrbk
# `volume."/"` + `subvolume."@"` looks for `/@`, which doesn't exist. This
# module mounts the top level (subvolid=5) at /mnt/btrfs-root; hosts then point
# btrbk at `volume."/mnt/btrfs-root"` and keep `subvolume."@"` +
# `snapshot_dir = "@snapshots"` as-is.
#
# btrbk-default runs as root with the plain `btrfs-progs` backend instead of
# upstream's User=btrbk + `btrfs-progs-sudo`: hosts importing services/ set
# security.sudo.execWheelOnly, so /run/wrappers/bin/sudo is 4510 root:wheel and
# the btrbk user can't exec it (exit 126, "Permission denied").
{
  config,
  lib,
  pkgs,
  ...
}:

let
  mountPoint = "/mnt/btrfs-root";
  rootFs = config.fileSystems."/";

  # Root's options minus anything that selects a subvolume, so fs-wide btrfs
  # options (compress, space_cache, ...) match the root mount exactly. Also
  # drops x-* per-mount userspace options: NixOS adds x-initrd.mount to `/`
  # (neededForBoot), and this mount must not be pulled into the initrd.
  dropOpt =
    o: lib.hasPrefix "subvol=" o || lib.hasPrefix "subvolid=" o || lib.hasPrefix "x-" o;

  # Runs before btrbk as an ExecStartPre. Creates
  # @snapshots here rather than via tmpfiles, which would race the mount on a
  # first deploy and create a plain directory on the root subvol instead.
  prepareSnapshots = pkgs.writeShellScript "btrbk-root-prepare" ''
    set -eu
    if ! ${pkgs.util-linux}/bin/mountpoint -q ${mountPoint}; then
      echo "btrbk-root: ${mountPoint} is not mounted; refusing to run btrbk" >&2
      exit 1
    fi
    if [ ! -e ${mountPoint}/@snapshots ]; then
      ${pkgs.btrfs-progs}/bin/btrfs subvolume create ${mountPoint}/@snapshots
    fi
  '';
in
{
  assertions = [
    {
      assertion = rootFs.fsType == "btrfs";
      message = "modules/btrbk-root.nix requires fileSystems.\"/\" to be btrfs (got ${rootFs.fsType}).";
    }
  ];

  # nofail so it can never block boot.
  fileSystems.${mountPoint} = {
    inherit (rootFs) device;
    fsType = "btrfs";
    options = (lib.filter (o: !dropOpt o) rootFs.options) ++ [
      "subvolid=5"
      "nofail"
    ];
  };

  # Upstream renders `{ backend = "btrfs-progs-sudo"; } // settings`, so a
  # backend set here wins.
  services.btrbk.instances.default.settings.backend = lib.mkForce "btrfs-progs";

  systemd.services.btrbk-default = {
    unitConfig.RequiresMountsFor = [ mountPoint ];
    serviceConfig = {
      User = lib.mkForce "root";
      Group = lib.mkForce "root";
      # Upstream's StateDirectory=btrbk would make systemd chown
      # /var/lib/btrbk to root:root on every run, fighting upstream's tmpfiles
      # rule (btrbk:btrbk, the ssh-access home). btrbk itself doesn't use it.
      StateDirectory = lib.mkForce [ ];
      # "+" = full privileges regardless of User= (kept from the btrbk-user
      # days; harmless as root). Upstream's btrbk module sets no
      # ExecStartPre, so a list merges cleanly.
      ExecStartPre = [ "+${prepareSnapshots}" ];
    };
  };
}
