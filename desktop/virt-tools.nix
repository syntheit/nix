{ lib, pkgs, ... }:

# Local VMs plus client tools for harbor's. Connect to harbor with:
#   virt-manager → File → Add Connection → QEMU/KVM
#   Hostname: matv@harbor.lan   (uses port 64829 via ~/.ssh/config)
{
  programs.virt-manager.enable = true;

  # Socket-activated: libvirtd starts on first use, not at boot.
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  systemd.services.libvirtd.wantedBy = lib.mkForce [ ];
  systemd.sockets.libvirtd.wantedBy = [ "sockets.target" ];
  systemd.sockets.libvirtd-admin.wantedBy = [ "sockets.target" ];

  environment.systemPackages = with pkgs; [
    virt-viewer
    spice-gtk
  ];
}
