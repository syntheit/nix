{ pkgs, ... }:

{
  home.packages = [ pkgs.square-corners ];

  # Dylib injection: set DYLD_INSERT_LIBRARIES at login for bottom corners
  launchd.agents.square-corners-dylib = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/launchctl"
        "setenv"
        "DYLD_INSERT_LIBRARIES"
        "${pkgs.square-corners}/lib/libsquarecorners.dylib"
      ];
      RunAtLoad = true;
    };
  };

  # Overlay daemon: draws black ears over top corners of tiled windows
  launchd.agents.square-corners-overlay = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.square-corners}/bin/square-corners-overlay" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
