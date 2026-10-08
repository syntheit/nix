# Brightness of the external monitors over DDC/CI: telmo's display popup
# (Super+D) and the keyboard's brightness keys (home/modules/hyprland.nix)
# both go through ddcutil, which needs /dev/i2c-* access.
#
# If `ddcutil detect` finds no monitors on the NVIDIA driver, ddcutil's docs
# suggest boot.extraModprobeConfig = "options nvidia NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100".
{ pkgs, vars, ... }:
{
  hardware.i2c.enable = true;
  users.users.${vars.user.name}.extraGroups = [ "i2c" ];
  environment.systemPackages = [ pkgs.ddcutil ];
}
