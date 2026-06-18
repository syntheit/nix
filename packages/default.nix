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
  overview = pkgs.callPackage ./overview { };
  volume-panel = pkgs.callPackage ./volume-panel { };
  bluetooth-panel = pkgs.callPackage ./bluetooth-panel { };
  wifi-panel = pkgs.callPackage ./wifi-panel { };
  brightness-panel = pkgs.callPackage ./brightness-panel { };
  wallpaper-cycle = pkgs.callPackage ./wallpaper-cycle { };
  menubar-blocker = pkgs.callPackage ./menubar-blocker { };
  square-corners = pkgs.callPackage ./square-corners { };
  spotify-watcher = pkgs.callPackage ./spotify-watcher { };
  caps-led-off = pkgs.callPackage ./caps-led-off { };
  q6voiced = pkgs.callPackage ./q6voiced { };
  hexagonrpc = pkgs.callPackage ./hexagonrpc { };
  alsa-ucm-fajita = pkgs.callPackage ./alsa-ucm-fajita { };
  mobile-config-firefox = pkgs.callPackage ./mobile-config-firefox { };
}

