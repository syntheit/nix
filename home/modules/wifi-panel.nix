{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.wifi-panel ];

  launchd.agents.wifi-panel = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.wifi-panel}/bin/wifi-panel" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
        SPEEDTEST_PATH = "${pkgs.speedtest-cli}/bin/speedtest-cli";
      };
    };
  };
}
