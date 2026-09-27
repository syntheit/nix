{
  inputs,
  hostName,
  ...
}:

# Vestal dashboard. The settings are meant to be shared across platforms:
# the same config drives swift (macOS) and, later, the Hyprland hosts. Put
# per-OS tweaks under settings.platform.<macos|linux>; vestal merges them
# over the rest. Schema: docs/CONFIG.md in github:syntheit/vestal.
{
  imports = [ inputs.vestal.homeManagerModules.default ];

  programs.vestal = {
    enable = true;
    # Stable signature, so calendar and Spotify permissions survive rebuilds.
    signingIdentity = "Developer ID Application: Daniel Miller (6NHZWHQX37)";

    settings = {
      # Built-in hotkey on swift only: mini's skhd uses F3 for space 3.
      hotkey = if hostName == "swift" then "f3" else null;
      theme = {
        palette = "tokyo-night";
        background = "aurora";
      };

      sources = {
        weather = {
          type = "http";
          url = "https://wttr.in/?m&format=j1";
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
          ];
        };
        systemBar = {
          type = "systemBar";
          show = [
            "uptime"
            "disk"
            "battery"
            "claudeUsage"
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
        claude = {
          type = "claudeUsage";
          path = "~/.claude/projects";
          fiveHourLimit = 8000000;
          weeklyLimit = 95000000;
        };
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
            location = ".nearest_area[0].areaName[0].value";
            region = ".nearest_area[0].region[0].value";
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
        "spotify"
        "agenda"
        "systems"
        "exchange"
        "weather"
      ];
    };
  };
}
