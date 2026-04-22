{ pkgs, ... }:

{
  home.packages = [ pkgs.dashboard ];

  home.file.".local/bin/toggle-dashboard" = {
    executable = true;
    text = ''
      #!/bin/bash
      if pgrep -qx dashboard; then
        pkill -x dashboard
      else
        ${pkgs.dashboard}/bin/dashboard &
        disown
      fi
    '';
  };
}
