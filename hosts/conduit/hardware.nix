{ inputs, ... }:

{
  imports = [
    inputs.disko.nixosModules.disko
  ];

  # Disko disk layout — BIOS boot + BTRFS root with subvolumes
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # BIOS boot partition
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@snapshots" = {
                mountpoint = "/.snapshots";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
            };
          };
        };
      };
    };
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    configurationLimit = 10;
    # disko handles the device via mirroredBoots
  };

  # QEMU/KVM virtio guest
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "ahci"
    "sd_mod"
  ];
  boot.kernelModules = [ "virtio_balloon" ];

  nixpkgs.hostPlatform = "x86_64-linux";
}
