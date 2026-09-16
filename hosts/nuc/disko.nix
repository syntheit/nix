{
  # Declarative disk layout for the colo NUC's internal storage. Same shape as
  # vista's disko.nix: whole-disk wipe, unencrypted (headless, no keyboard at
  # boot to type a LUKS passphrase, no out-of-band console at the colo), btrfs
  # with subvolumes.
  #
  # The target NUC7i3BNK has a Samsung 860 EVO M.2 250 GB, which is a *SATA*
  # M.2 drive (the 7i3BNK's M.2 slot takes both PCIe and SATA) — so it
  # enumerates as /dev/sda via ahci, NOT /dev/nvme0n1. Hence the default
  # below. Always confirm against the real box first:
  #   lsblk -dno NAME,SIZE,MODEL
  # `disko --argstr diskoFile ... ` / `disko-install --disk main <device>`
  # override this at install time, so the same file is reused unmodified for
  # the QEMU rehearsal (/dev/vda).
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "2G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ]; # force overwrite any existing signature
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@snapshots" = {
                mountpoint = "/.snapshots";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
