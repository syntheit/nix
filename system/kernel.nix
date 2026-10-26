{ pkgs, lib, ... }:
{
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 15;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  # mkDefault so hosts that need a specific kernel can override without a
  # conflict — e.g. vista (Apple T2) whose nixos-hardware apple-t2 module
  # pins its own T2-patched kernel for the apple-bce driver.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  # Enable filesystem support (read and write)
  boot.supportedFilesystems = [
    "ntfs"
    "exfat"
    "f2fs"
    "xfs"
    "nfs"
    "cifs"
  ];
}
