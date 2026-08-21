{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    filterAttrs
    foldl'
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  cfg = config.fajita.quickSettings;

  builtinTileIds = [
    "wifi"
    "mobile-data"
    "wired"
    "bluetooth-tether"
    "vpn"
    "bluetooth"
    "power-mode"
    "night-light"
    "dark-style"
    "do-not-disturb"
    "keyboard-backlight"
    "airplane-mode"
    "auto-rotate"
    "unsafe-mode"
    "flashlight"
    "hotspot"
  ];

  actionCatalog = {
    screen-record = {
      title = "Screen Record";
      iconName = "camera-video-symbolic";
    };
    screenshot = {
      title = "Screenshot";
      iconName = "camera-photo-symbolic";
    };
    lock-screen = {
      title = "Lock Screen";
      iconName = "system-lock-screen-symbolic";
    };
  };

  settingsPanelDesktopIds = {
    about = "gnome-about-panel.desktop";
    applications = "gnome-applications-panel.desktop";
    background = "gnome-background-panel.desktop";
    bluetooth = "gnome-bluetooth-panel.desktop";
    color = "gnome-color-panel.desktop";
    datetime = "gnome-datetime-panel.desktop";
    displays = "gnome-display-panel.desktop";
    keyboard = "gnome-keyboard-panel.desktop";
    mouse = "gnome-mouse-panel.desktop";
    multitasking = "gnome-multitasking-panel.desktop";
    network = "gnome-network-panel.desktop";
    notifications = "gnome-notifications-panel.desktop";
    online-accounts = "gnome-online-accounts-panel.desktop";
    power = "gnome-power-panel.desktop";
    printers = "gnome-printers-panel.desktop";
    privacy = "gnome-privacy-panel.desktop";
    region = "gnome-region-panel.desktop";
    search = "gnome-search-panel.desktop";
    sharing = "gnome-sharing-panel.desktop";
    sound = "gnome-sound-panel.desktop";
    system = "gnome-system-panel.desktop";
    accessibility = "gnome-universal-access-panel.desktop";
    users = "gnome-users-panel.desktop";
    wacom = "gnome-wacom-panel.desktop";
    wellbeing = "gnome-wellbeing-panel.desktop";
    wifi = "gnome-wifi-panel.desktop";
    mobile = "gnome-wwan-panel.desktop";
  };

  quickSettingsFeedback = {
    "event-name" = "quick-settings-activated";
    type = "VibraPattern";
    magnitudes = [ 0.2 ];
    durations = [ 7 ];
  };

  # Extend the upstream 6T theme instead of copying it, preserving its quiet
  # incoming-call vibration and silent notification LEDs across updates.
  feedbackTheme =
    pkgs.runCommand "feedbackd-device-themes-fajita-quick-settings"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        mkdir -p $out/share/feedbackd/themes
        jq --argjson feedback '${builtins.toJSON quickSettingsFeedback}' '
          .profiles =
            [{name: "full", feedbacks: [$feedback]}]
            + (.profiles | map(
                if .name == "quiet"
                then .feedbacks += [$feedback]
                else .
                end))
        ' ${pkgs.feedbackd-device-themes}/share/feedbackd/themes/oneplus,fajita.json \
          > $out/share/feedbackd/themes/oneplus,fajita.json
      '';

  tileType = types.submodule {
    options = {
      app = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "org.gnome.Calculator.desktop";
        description = "Desktop file launched when this custom tile is tapped.";
      };

      action = mkOption {
        type = types.nullOr (types.enum (builtins.attrNames actionCatalog));
        default = null;
        description = "Whitelisted GNOME Shell action run when this custom tile is tapped.";
      };

      span = mkOption {
        type = types.enum [
          1
          2
          4
        ];
        default = 1;
        description = "Width in logical grid columns (1=compact, 2=wide).";
      };

      title = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom tile label. Shell actions provide a sensible default.";
      };

      icon = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "accessories-calculator-symbolic";
        description = "Symbolic icon name. Shell actions provide a sensible default.";
      };

      settings = mkOption {
        type = types.nullOr (types.enum (builtins.attrNames settingsPanelDesktopIds));
        default = null;
        example = "wifi";
        description = "GNOME Settings panel opened by a long press.";
      };

      persistent = mkOption {
        type = types.bool;
        default = false;
        description = "Keep a built-in tile present while its backend initializes.";
      };
    };
  };

  defaultTile = {
    app = null;
    action = null;
    span = 1;
    title = null;
    icon = null;
    settings = null;
    persistent = false;
  };

  getTile = id: cfg.tiles.${id} or defaultTile;
  tileKind =
    tile:
    if tile.app != null then
      "application"
    else if tile.action != null then
      "shell"
    else
      "builtin";
  tileDefaults = tile: if tile.action == null then { } else actionCatalog.${tile.action};

  resolvedTiles = map (
    id:
    let
      tile = getTile id;
      defaults = tileDefaults tile;
    in
    filterAttrs (_: value: value != null) {
      inherit id;
      type = tileKind tile;
      inherit (tile) span persistent action;
      title = if tile.title != null then tile.title else defaults.title or null;
      iconName = if tile.icon != null then tile.icon else defaults.iconName or null;
      desktopId = tile.app;
      longPressDesktopId =
        if tile.settings == null then null else settingsPanelDesktopIds.${tile.settings};
    }
  ) cfg.layout;

  usedCells = foldl' (total: tile: total + tile.span) 0 resolvedTiles;
  configuredTileIds = builtins.attrNames cfg.tiles;
  unusedTileIds = builtins.filter (id: !(builtins.elem id cfg.layout)) configuredTileIds;
  unknownTileIds = builtins.filter (
    id:
    let
      tile = getTile id;
    in
    !(builtins.elem id builtinTileIds) && tile.app == null && tile.action == null
  ) cfg.layout;
in
{
  options.fajita.quickSettings = {
    enable = mkEnableOption "declarative GNOME Mobile quick settings";

    columns = mkOption {
      type = types.ints.positive;
      default = 4;
      description = "Number of logical columns in the quick-settings grid.";
    };

    rows = mkOption {
      type = types.ints.positive;
      default = 5;
      description = "Expanded design capacity; tiles above it trigger a warning.";
    };

    collapsedRows = mkOption {
      type = types.nullOr types.ints.positive;
      default = 2;
      description = "Tile rows shown before expanding; null shows all rows.";
    };

    layout = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "wifi"
        "bluetooth"
        "do-not-disturb"
        "flashlight"
      ];
      description = "Tile IDs in visual order, left-to-right then top-to-bottom.";
    };

    tiles = mkOption {
      type = types.attrsOf tileType;
      default = { };
      description = ''
        Per-tile overrides and custom tiles. Built-ins only need an entry when
        overriding span, persistence, or their long-press Settings panel.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Quick-toggle and snap-point haptics use feedbackd over D-Bus.
    programs.feedbackd = {
      enable = true;
      theme-package = feedbackTheme;
    };

    assertions = [
      {
        assertion = cfg.columns == 4;
        message = "fajita quick settings currently supports a four-column grid";
      }
      {
        assertion = cfg.collapsedRows == null || cfg.collapsedRows <= cfg.rows;
        message = "fajita quick-settings collapsedRows must not exceed rows";
      }
      {
        assertion = builtins.length cfg.layout == builtins.length (lib.unique cfg.layout);
        message = "fajita quick-settings layout IDs must be unique";
      }
      {
        assertion = unknownTileIds == [ ];
        message = "unknown quick-settings tiles: ${lib.concatStringsSep ", " unknownTileIds}";
      }
      {
        assertion = lib.all (
          tile:
          builtins.length (
            builtins.filter (value: value != null) [
              tile.app
              tile.action
            ]
          ) <= 1
        ) (builtins.attrValues cfg.tiles);
        message = "a quick-settings tile cannot define both app and action";
      }
      {
        assertion = lib.all (tile: tile.app == null || (tile.title != null && tile.icon != null)) (
          builtins.attrValues cfg.tiles
        );
        message = "application quick-settings tiles require title and icon";
      }
    ];

    warnings =
      optional (usedCells > cfg.columns * cfg.rows)
        "fajita quick settings uses ${toString usedCells} cells, above the ${toString cfg.columns}x${toString cfg.rows} design capacity"
      ++
        optional (unusedTileIds != [ ])
          "fajita quick-settings tile definitions are not in layout: ${lib.concatStringsSep ", " unusedTileIds}";

    environment.etc."gnome-shell-mobile/quick-settings.json".text = builtins.toJSON {
      version = 1;
      grid = {
        inherit (cfg) columns rows collapsedRows;
      };
      tiles = resolvedTiles;
    };
  };
}
