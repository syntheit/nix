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
  eq = pkgs.callPackage ./eq { };
  dashboard = pkgs.callPackage ./dashboard { };
  overview = pkgs.callPackage ./overview { };
  volume-panel = pkgs.callPackage ./volume-panel { };
  bluetooth-panel = pkgs.callPackage ./bluetooth-panel { };
  wifi-panel = pkgs.callPackage ./wifi-panel { };
}

