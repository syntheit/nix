{ pkgs, ... }:

{
  home.packages = [ pkgs.wallpaper-cycle ];

  launchd.agents.wallpaper-cycle = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.wallpaper-cycle}/bin/wallpaper-cycle" "watch" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
