{ pkgs, ... }:

{
  home.packages = [ pkgs.menubar-blocker ];

  launchd.agents.menubar-blocker = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.menubar-blocker}/bin/menubar-blocker" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
