{ pkgs, ... }:
{
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable systemd in initrd for a better LUKS decryption prompt
  # Previously, the initrd used the legacy/simple init system which provides
  # a basic text-based password prompt. With systemd in initrd, you get a
  # cleaner, more modern password prompt interface with better visual feedback.
  # Note: This is separate from systemd-boot (the bootloader) - that was
  # already enabled above. This controls the init system used during early boot.
  boot.initrd.systemd.enable = true;

  # Customize the LUKS password prompt
  # You can customize the prompt message by setting:
  # boot.initrd.luks.devices."luks-3e72a884-3bf1-43ba-815c-b04b5efb3e26".preLVM = true;
  # And adding a custom askPassword program if desired

  # Kernel parameters for performance/optimization
  # TODO: Review and enable as needed for your hardware
  # boot.kernelParams = [
  #   # Performance
  #   "mitigations=off"  # Disable CPU mitigations (security vs performance tradeoff)
  #   "preempt=none"     # For low-latency workloads (may impact desktop responsiveness)
  #   # Power management
  #   "acpi_backlight=vendor"  # For better backlight control
  #   # I/O scheduler
  #   "elevator=deadline"  # Better I/O scheduler for SSDs
  #   # Memory
  #   "transparent_hugepage=always"  # Enable transparent huge pages
  # ];
}

