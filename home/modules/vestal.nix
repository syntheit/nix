{
  inputs,
  hostName,
  lib,
  pkgs,
  ...
}:

# Vestal dashboard, on swift and mini (home/darwin.nix) and on the Hyprland
# hosts mantle and ledger (home/default.nix). The settings are shared across
# platforms: put per-OS tweaks under settings.platform.<macos|linux>; vestal
# merges them over the rest. Schema: docs/CONFIG.md in github:syntheit/vestal.
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  # wttr.in JSON for wherever ipinfo.io places this machine, plus .place (the
  # city). Falls back to wttr.in's own IP lookup if ipinfo is unreachable.
  weatherHere = pkgs.writeShellScript "vestal-weather" ''
    geo=$(${pkgs.curl}/bin/curl -fsm5 https://ipinfo.io/json) || geo='{}'
    loc=$(${pkgs.jq}/bin/jq -r '.loc // empty' <<<"$geo")
    ${pkgs.curl}/bin/curl -fsm15 "https://wttr.in/$loc?m&format=j1" |
      ${pkgs.jq}/bin/jq -c --argjson geo "$geo" \
        '. + {place: ($geo.city // .nearest_area[0].areaName[0].value)}'
  '';

  # USB mic/camera privacy on Linux, through usb-toggle (system/default.nix).
  usbState = device: {
    type = "command";
    argv = [
      "usb-toggle"
      device
      "waybar"
    ];
    refresh = "2s";
    when = "visible";
  };
  usbToggle = device: icon: {
    type = "icon";
    source = device;
    "when" = ".class != null";
    size = 11;
    weight = "fill";
    name.expr = ''if .class == "on" then "${icon}" else "${icon}-slash" end'';
    color.expr = ''if .class == "on" then "bad" else "good" end'';
    action = {
      run = [
        "sudo"
        "-n"
        "/run/current-system/sw/bin/usb-toggle"
        device
        "toggle"
      ];
      optimistic = ''. + {class: (if .class == "on" then "off" else "on" end)}'';
    };
  };
  # The same toggle as a dashboard-wide key, so it works even before the
  # device's state has loaded (a widget's own key needs the widget shown).
  usbKey = device: {
    run = [
      "sudo"
      "-n"
      "/run/current-system/sw/bin/usb-toggle"
      device
      "toggle"
    ];
    refreshAfter = [ device ];
  };
in
{
  imports = [ inputs.vestal.homeManagerModules.default ];

  programs.vestal = {
    enable = true;
    # Linux: built with the system's nixpkgs (overlays/default.nix). macOS
    # keeps the flake's package, which follows nixpkgs-darwin.
    package = lib.mkIf isLinux pkgs.vestal;
    # macOS only (ignored on Linux): a stable signature, so calendar and
    # Spotify permissions survive rebuilds.
    signingIdentity = "Developer ID Application: Daniel Miller (6NHZWHQX37)";
    # Linux: a Hyprland bind for the hotkey (platform.linux.hotkey below) that
    # runs `vestal toggle`, and blur for the dashboard's layer surface.
    hyprland.enable = isLinux;

    settings = {
      # Built-in hotkey on swift only: mini's skhd uses F3 for space 3.
      hotkey = if hostName == "swift" then "f3" else null;
      # Thumb + three finger pinch toggles the dashboard (macOS; the Dock's
      # own pinch is off in modules/darwin/common.nix).
      gesture = if hostName == "swift" then "pinch" else null;
      theme = {
        palette = "tokyo-night";
        background = "aurora";
      };

      sources = {
        # wttr.in's own IP lookup lands ~300 km off (General Alvear), so
        # mantle (stationary) pins Buenos Aires and the rest locate through
        # ipinfo.io, which gets the city right, then query wttr.in by coords.
        weather =
          if hostName == "mantle" then
            {
              type = "http";
              url = "https://wttr.in/-34.6037,-58.3816?m&format=j1";
              refresh = "30m";
            }
          else
            {
              type = "command";
              argv = [ "${weatherHere}" ];
              refresh = "30m";
            };
        dolares = {
          type = "http";
          url = "https://dolarapi.com/v1/dolares";
          refresh = "4h";
        };
        rates = {
          type = "http";
          url = "https://raw.githubusercontent.com/syntheit/exchange-rates/refs/heads/main/rates.json";
          refresh = "4h";
        };
        calendar = {
          type = "calendar";
          refresh = "5m";
          days = 1;
        };
      };

      widgets = {
        clock = {
          type = "clock";
          worldClocks = [
            {
              label = "BA";
              tz = "America/Argentina/Buenos_Aires";
            }
            {
              label = "NYC";
              tz = "America/New_York";
            }
            {
              label = "CHI";
              tz = "America/Chicago";
            }
            {
              label = "AZ";
              tz = "America/Phoenix";
            }
          ];
        };
        systemBar = {
          type = "systemBar";
          show = [
            "uptime"
            "disk"
            "battery"
            "network"
            "privacy"
          ];
          privacy = {
            command = [
              "bash"
              "~/.local/bin/toggle-privacy"
            ];
            stateFile = "/tmp/.privacy-mode";
          };
        };
        # Claude and Codex plan usage: 5-hour and weekly bars. A service
        # with no data on a host (no status line, no codex) is left out.
        usage.type = "aiUsage";
        # Replace the default `media` widget with the Spotify one below.
        media = null;
        spotify = {
          type = "media";
          player = "Spotify";
          hideWhenOff = true;
        };
        agenda = {
          type = "agendaList";
          title = "Today";
          source = "calendar";
          maxEvents = 5;
        };
        systems = {
          type = "systemHealth";
          title = "Systems";
          provider = "foyer";
          hosts = [
            # No name: the local machine shows under its own hostname.
            { source = "local"; }
            {
              name = "harbor";
              url = "https://harbor.matv.io";
            }
            {
              name = "raven";
              url = "https://raven.matv.io";
            }
            {
              name = "conduit";
              url = "https://conduit.matv.io";
            }
          ];
        };
        exchange =
          let
            dolar = label: casa: {
              inherit label;
              match.casa = casa;
              picks = {
                buy = "compra";
                sell = "venta";
              };
              format = "int";
            };
          in
          {
            type = "keyValueList";
            title = "Currencies";
            source = "dolares";
            items = [
              (dolar "Blue" "blue")
              (dolar "Official" "oficial")
              (dolar "MEP" "bolsa")
              {
                label = "BRL";
                source = "rates";
                pick = "rates.BRL";
                format = "decimal";
              }
            ];
          };
        weather = {
          type = "weatherCard";
          title = "Weather";
          source = "weather";
          units = "metric";
          fields = {
            # A coordinate lookup names the nearest wttr.in area ("Centro"),
            # so mantle shows a fixed label and the rest use ipinfo's city.
            location = if hostName == "mantle" then ''"Buenos Aires"'' else ".place";
            region = if hostName == "mantle" then ''"Argentina"'' else ".nearest_area[0].country[0].value";
            condition = ".current_condition[0].weatherDesc[0].value";
            temp = ".current_condition[0].temp_C";
            sunrise = ".weather[0].astronomy[0].sunrise";
            sunset = ".weather[0].astronomy[0].sunset";
          };
        };
      };

      views.main.order = [
        "clock"
        "systemBar"
        "usage"
        "spotify"
        "agenda"
        "systems"
        "exchange"
        "weather"
      ];

      platform.linux = {
        # Home, as the old tmux dashboard had; Hyprland binds it (above).
        hotkey = "home";
        # mantle's 1440p monitors run at scale 1: enlarge text and icons to
        # roughly the proportions swift's Retina screen shows.
        theme = {
          scale = 1.25;
          # Apple's fonts, as on swift (packages/apple-fonts, installed by
          # desktop/default.nix).
          fonts = {
            sans = "SF Pro";
            mono = "SF Mono";
            rounded = "SF Pro Rounded";
          };
          # Tint over vestal's own blurred snapshot of the desktop.
          dim = 0.6;
        };
        # No calendar backend on Linux until an ICS source is set up: drop the
        # calendar source and the agenda.
        # mic and cam: usb-toggle (system/default.nix) prints each USB device's
        # state as {"class": "on"|"off"} (no class when unplugged).
        sources = {
          calendar = null;
          mic = usbState "mic";
          cam = usbState "cam";
        };
        widgets = {
          agenda = null;
          # The privacy toggle above is macOS's (toggle-privacy in
          # sketchybar.nix, state in /tmp/.privacy-mode). The Linux hosts have
          # only usb-toggle (system/default.nix), per device and without a
          # state file, so no privacy item here.
          systemBar = {
            show = [
              "uptime"
              "disk"
              "battery"
              "network"
            ];
            privacy = null;
            # Mic and camera toggles at the right end, as the old tmux
            # dashboard had: click, or ctrl+m / ctrl+c while it's open.
            trailing = [
              (usbToggle "mic" "microphone")
              (usbToggle "cam" "video-camera")
            ];
          };
        };
        keys = {
          "ctrl+m" = usbKey "mic";
          "ctrl+c" = usbKey "cam";
        };
        views.main.order = [
          "clock"
          "systemBar"
          "usage"
          "spotify"
          "systems"
          "exchange"
          "weather"
        ];
      };
    };
  };
}
