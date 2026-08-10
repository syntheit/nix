{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.fajita.quickSettings;

  tileType = types.submodule (
    { ... }: {
      options = {
        id = mkOption {
          type = types.str;
          description = "Stable quick-settings tile identifier.";
        };

        type = mkOption {
          type = types.enum [
            "builtin"
            "application"
            "shell"
          ];
          default = "builtin";
          description = "Tile implementation type.";
        };

        span = mkOption {
          type = types.enum [
            1
            2
            4
          ];
          default = 2;
          description = "Width in logical grid columns (1=compact, 2=wide).";
        };

        title = mkOption {
          type = types.nullOr types.str;
          default = null;
        };

        iconName = mkOption {
          type = types.nullOr types.str;
          default = null;
        };

        desktopId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Desktop file launched by an application tile.";
        };

        action = mkOption {
          type = types.nullOr (types.enum [ "screen-record" ]);
          default = null;
          description = "Whitelisted GNOME Shell action.";
        };

        longPressDesktopId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "GNOME Settings panel opened by a long press.";
        };

        persistent = mkOption {
          type = types.bool;
          default = false;
          description = "Keep the tile present while its backend initializes.";
        };
      };
    }
  );

  ids = map (tile: tile.id) cfg.tiles;
  usedCells = lib.foldl' (total: tile: total + tile.span) 0 cfg.tiles;
  jsonTiles = map (lib.filterAttrs (_: value: value != null)) cfg.tiles;
in
{
  options.fajita.quickSettings = {
    enable = mkEnableOption "declarative GNOME Mobile quick settings";

    columns = mkOption {
      type = types.ints.positive;
      default = 4;
    };

    rows = mkOption {
      type = types.ints.positive;
      default = 5;
      description = "Design capacity; overflow remains visible and scrollable.";
    };

    tiles = mkOption {
      type = types.listOf tileType;
      default = [ ];
      description = "Ordered quick-settings tile layout.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.columns == 4;
        message = "fajita quick settings currently supports a four-column grid";
      }
      {
        assertion = lib.length ids == lib.length (lib.unique ids);
        message = "fajita quick-settings tile IDs must be unique";
      }
      {
        assertion = lib.all (tile: tile.type != "application" || tile.desktopId != null) cfg.tiles;
        message = "application quick-settings tiles require desktopId";
      }
      {
        assertion = lib.all (tile: tile.type != "shell" || tile.action != null) cfg.tiles;
        message = "shell quick-settings tiles require action";
      }
    ];

    warnings =
      lib.optional (usedCells > cfg.columns * cfg.rows)
        "fajita quick settings uses ${toString usedCells} cells, above the ${toString cfg.columns}x${toString cfg.rows} design capacity";

    environment.etc."gnome-shell-mobile/quick-settings.json".text = builtins.toJSON {
      version = 1;
      grid = {
        inherit (cfg) columns rows;
      };
      tiles = jsonTiles;
    };
  };
}
