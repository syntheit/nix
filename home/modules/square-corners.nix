{ pkgs, ... }:

{
  launchd.agents.square-corners = {
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
}
