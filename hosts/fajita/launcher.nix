{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.fajita.launcher;

  # Each favorite maps to a MINIMAL attrset; null attrs are dropped so the
  # emitted JSON only carries the keys that entry actually uses.
  favEntries = map (
    f:
    let
      base =
        if f.type == "folder" then
          {
            type = "folder";
            title = f.title;
            iconName = f.iconName;
            apps = f.apps;
          }
        else
          {
            type = "app";
            desktopId = f.desktopId;
          };
    in
    lib.filterAttrs (_: v: v != null) base
  ) cfg.favorites;
in
{
  options.fajita.launcher = {
    enable = mkEnableOption "declarative Niagara-style launcher favorites";

    favorites = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            type = mkOption {
              type = types.enum [
                "app"
                "folder"
              ];
              default = "app";
              description = "Whether this favorite launches an app or opens a folder.";
            };

            desktopId = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Desktop file id for an app entry.";
            };

            title = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Display title (folder entries).";
            };

            iconName = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Symbolic icon name (folder entries).";
            };

            apps = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Member desktop ids (folder entries).";
            };
          };
        }
      );
      default = [ ];
      description = "Ordered Niagara-style favorites shown on the home launcher.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (f: f.type != "app" || f.desktopId != null) cfg.favorites;
        message = "fajita launcher app favorites require a desktopId";
      }
      {
        assertion = lib.all (f: f.type != "folder" || f.title != null) cfg.favorites;
        message = "fajita launcher folder favorites require a title";
      }
    ];

    environment.etc."gnome-shell-mobile/launcher.json".text = builtins.toJSON {
      version = 1;
      favorites = favEntries;
    };
  };
}
