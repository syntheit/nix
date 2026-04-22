{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.search-panel ];

  launchd.agents.search-panel = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.search-panel}/bin/search-panel" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
      };
    };
  };
}
