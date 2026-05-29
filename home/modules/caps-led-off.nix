{ pkgs, ... }:

{
  home.packages = [ pkgs.caps-led-off ];

  launchd.agents.caps-led-off = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.caps-led-off}/bin/caps-led-off" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
