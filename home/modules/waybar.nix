{ pkgs, ... }:

{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        modules-left = [ "hyprland/workspaces" "mpris" ];
        modules-center = [ "clock" ];
        modules-right = [
          "custom/network-activity"
          "tray"
          "custom/weather"
          "pulseaudio"
          "custom/temperature"
          "cpu"
          "memory"
        ];
        pulseaudio = {
          format = "󰕾 {volume}%";
          format-bluetooth = "󰕾 {volume}%";
          format-bluetooth-muted = "󰝟 0%";
          format-muted = "󰝟 0%";
          on-click = "pavucontrol";
        };
        "custom/network-activity" = {
          format = "{}";
          interval = 1;
          tooltip = false;
          exec = ''
            ${pkgs.bash}/bin/bash -c '
            interface=$(ip route | grep default | awk "{print \$5}" | head -1)
            if [ -z "$interface" ]; then
              echo "⬇ 0 mb/s ⬆ 0 mb/s"
              exit 0
            fi

            rx_old=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
            tx_old=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
            sleep 1
            rx_new=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
            tx_new=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)

            rx_diff=$((rx_new - rx_old))
            tx_diff=$((tx_new - tx_old))

            rx_mb=$(awk "BEGIN {printf \"%.2f\", $rx_diff / 1048576}")
            tx_mb=$(awk "BEGIN {printf \"%.2f\", $tx_diff / 1048576}")

            echo "⬇ $rx_mb mb/s ⬆ $tx_mb mb/s"
            '
          '';
        };
        "custom/temperature" = {
          format = "󰔏 {}°";
          tooltip-format = "CPU Temp: {}°";
          interval = 5;
          exec = ''
            ${pkgs.bash}/bin/bash -c '
            temp=$(sensors 2>/dev/null | grep -i "core 0" | grep -oE "[0-9]+\.[0-9]+|[0-9]+" | head -1)
            if [ -z "$temp" ]; then
              temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk "{printf \"%.0f\", \$1/1000}")
            fi
            if [ -z "$temp" ]; then
              echo "N/A"
            else
              echo "$temp"
            fi
            '
          '';
        };
        cpu = {
          format = "󰍛 {usage}%";
        };
        memory = {
          format = "󰟂 {}%";
          tooltip-format = "RAM: {used}GiB / {total}GiB\nSwap: {swapUsed}GiB / {swapTotal}GiB";
        };
        tray = {
          icon-size = 15;
          spacing = 10;
        };
        battery = {
          format = "{capacity}% {icon}";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
        };
        clock = {
          format = "{:%R %A, %B %d}";
          format-alt = "{:%R}";
          timezone = "America/Argentina/Buenos_Aires";
          tooltip = false;
          actions = {
            on-click-right = "mode";
            on-click-forward = "tz_up";
            on-click-backward = "tz_down";
            on-scroll-up = "shift_up";
            on-scroll-down = "shift_down";
          };
        };
        mpris = {
          format = "{dynamic}";
          max-length = 75;
          ellipsize = true;
          dynamic-order = [ "title" "artist" ];
          tooltip = false;
          status-icons = {
            paused = "⏸";
          };
          on-click = ''
            ${pkgs.bash}/bin/bash -c 'hyprctl dispatch focuswindow "class:.*[Ss]potify.*" 2>/dev/null || hyprctl dispatch focuswindow "class:spotify" 2>/dev/null || hyprctl dispatch focuswindow "class:Spotify" 2>/dev/null || true'
          '';
        };
        "custom/weather" = {
          format = "{}";
          interval = 1800; # Update every 30 minutes
          exec = ''
            curl -s "wttr.in?format=%t" | head -1
          '';
          tooltip = true;
          on-click = "zen 'https://www.accuweather.com/en/ar/buenos-aires/7894/weather-forecast/7894'";
        };
      };
    };

    style = ''
        * {
            border: none;
            font-family: "JetBrains Mono Nerd Font", sans-serif;
            font-size: 13px;
            color: #ffffff;
            border-radius: 20px;
        }
        
        window {
          font-weight: bold;
        }

        window#waybar {
            background: #000;
            border-radius: 0;
        }
        
      /*-----module groups----*/
        .modules-right {
          background-color: transparent;
            margin: 0 10px 0 0;
        }

        .modules-center {
          background-color: transparent;
            margin: 0;
        }

        .modules-left {
            margin: 0 0 0 5px;
          background-color: transparent;
        }

      /*-----modules indv----*/
        .modules-left > *,
        .modules-center > *,
        .modules-right > * {
            padding: 2px 10px;
        }
        
        #workspaces button {
            padding: 2px 5px;
            background-color: transparent;
        }
        #workspaces button:hover {
            box-shadow: inherit;
          background-color: transparent;
        }
        
        #workspaces button.focused {
          background-color: transparent;
        }
        
        #memory {
            padding: 2px 0 2px 10px;
        }
        #cpu {
            padding: 2px 0 2px 10px;
        }
        #custom-temperature {
            padding: 2px 0 2px 10px;
        }
        #pulseaudio {
            padding: 2px 0 2px 10px;
        }
        #tray {
            padding: 2px 0 2px 10px;
        }
        #custom-weather {
            padding: 2px 0 2px 10px;
            margin-left: 0;
        }
        #custom-copyq:hover {
            background-color: rgba(255, 255, 255, 0.1);
        }
        #mode {
            color: #cc3436;
            font-weight: bold;
        }
        #custom-power {
          background-color: transparent;
          border-radius: 100px;
          margin: 5px 5px;
          padding: 0 6px 0 0;
        }
        /*-----Indicators----*/
        #idle_inhibitor.activated {
            color: #2dcc36;
        }
        #battery.charging {
            color: #2dcc36;
        }
        #battery.warning:not(.charging) {
          color: #e6e600;
        }
        #battery.critical:not(.charging) {
            color: #cc3436;
        }
        #temperature.critical {
            color: #cc3436;
        }
        #mpris {
            border-radius: 20px;
            background-color: rgba(0, 0, 0, 0.6);
            padding: 0 12px;
        }
        #mpris.stopped {
            background-color: transparent;
            color: transparent;
        }
        #mpris.paused {
            opacity: 0.6;
        }
    '';
  };

  # Override waybar systemd service to ensure proper Wayland environment
  systemd.user.services.waybar = {
    Service = {
      # Pass through Wayland environment variables from user session
      PassEnvironment = [ "WAYLAND_DISPLAY" "XDG_SESSION_TYPE" ];
      Environment = [
        "XDG_SESSION_TYPE=wayland"
      ];
      # Unset DISPLAY to prevent X11 fallback
      UnsetEnvironment = [ "DISPLAY" ];
    };
  };
}
