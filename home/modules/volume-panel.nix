{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.volume-panel ];

  launchd.agents.volume-panel = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.volume-panel}/bin/volume-panel" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
      };
    };
  };
}
