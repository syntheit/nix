{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.bluetooth-panel ];

  launchd.agents.bluetooth-panel = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.bluetooth-panel}/bin/bluetooth-panel" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
      };
    };
  };
}
