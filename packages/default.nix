{
  lib,
  pkgs,
  ...
}:

{
  hyprland-dynamic-borders = pkgs.callPackage ./hyprland-dynamic-borders { };
  argus = pkgs.callPackage ./argus { };
  cputemp = pkgs.callPackage ./cputemp { };
  systemstats = pkgs.callPackage ./systemstats { };
}

