{
  # Declarative disk layout for vista's internal SSD.
  #
  # On a T2 Mac the internal storage presents as a normal NVMe device, so disko
  # partitions it like any other machine. Whole-disk wipe, unencrypted (this is
  # a headless HTPC — there's no keyboard at boot to type a LUKS passphrase, and
  # it must come up unattended), btrfs with subvolumes.
  #
  # NOTE: confirm the device name from the live installer before running:
  #   lsblk -dno NAME,SIZE,MODEL    # the 2 TB Apple SSD is almost always nvme0n1
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          # Generous EFI partition — systemd-boot keeps 15 generations of
          # kernels + initrds (configurationLimit in system/kernel.nix), which
          # adds up fast.
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
