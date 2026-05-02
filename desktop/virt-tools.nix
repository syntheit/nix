{ pkgs, ... }:

# Client-side VM tools. Connect to harbor with:
#   virt-manager → File → Add Connection → QEMU/KVM
#   Hostname: matv@harbor.lan   (uses port 64829 via ~/.ssh/config)
{
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    virt-viewer
    spice-gtk
  ];
}
