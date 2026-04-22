{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.eq ];

  launchd.agents.eq = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.eq}/bin/eq" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
      };
    };
  };
}
