{ pkgs, inputs, ... }:

let
  vestal = inputs.vestal.packages.${pkgs.system}.default;
in
{
  home.packages = [ vestal ];

  home.file.".local/bin/toggle-vestal" = {
    executable = true;
    text = ''
      #!/bin/bash
      if pgrep -qx vestal; then
        pkill -x vestal
      else
        ${vestal}/bin/vestal &
        disown
      fi
    '';
  };
}
