{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.vestal;
  vestal = inputs.vestal.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Generate the JSON config file from the Nix attrset. Lives in the Nix
  # store, so any change to `settings` forces a new hash → new toggle script
  # → next F3 press launches vestal with the updated config. (Already-
  # running vestal needs to be dismissed + reopened for changes to apply.)
  configFile = pkgs.writeText "vestal-config.json" (builtins.toJSON cfg.settings);
  hasSettings = cfg.settings != { };
in
{
  options.programs.vestal = {
    enable = lib.mkEnableOption "Vestal dashboard";

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Vestal configuration attrset. Serialized to JSON and passed to the
        vestal binary via the VESTAL_CONFIG env var. When empty, vestal
        falls back to its bundled defaults.

        See https://github.com/syntheit/vestal for the schema.
      '';
      example = lib.literalExpression ''
        {
          hotkey = "f3";
          sources.weather = {
            type = "http";
            url = "https://wttr.in/?m&format=j1";
            refresh = "30m";
            parse = "json";
          };
          widgets.clock = {
            type = "clock";
            worldClocks = [
              { label = "BA";  tz = "America/Argentina/Buenos_Aires"; }
              { label = "NYC"; tz = "America/New_York"; }
            ];
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ vestal ];

    home.file.".local/bin/toggle-vestal" = {
      executable = true;
      text = ''
        #!/bin/bash
        ${lib.optionalString hasSettings "export VESTAL_CONFIG=${configFile}"}
        if pgrep -qx vestal; then
          pkill -x vestal
        else
          ${vestal}/bin/vestal &
          disown
        fi
      '';
    };
  };
}
