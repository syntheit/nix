{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.brightness-panel ];

  launchd.agents.brightness-panel = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.brightness-panel}/bin/brightness-panel" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
      };
    };
  };
}
