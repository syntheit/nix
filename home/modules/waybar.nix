{
  pkgs,
  lib,
  hostName,
  ...
}:

{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        modules-left = [
          "hyprland/workspaces"
          "mpris"
        ];
        modules-center = [
          "clock"
          "custom/dnd"
        ];
        modules-right = [
          "custom/network-activity"
          "custom/network-status"
          "bluetooth"
          "custom/weather"
          "pulseaudio"
          "custom/temperature"
          "cpu"
          "memory"
        ]
        ++ lib.optionals (hostName == "ionian") [ "battery" ];
        pulseaudio = {
          format = "󰕾 {volume}%";
          format-bluetooth = "󰕾 {volume}%";
          format-bluetooth-muted = "󰝟 0%";
          format-muted = "󰝟 0%";
          on-click = "pavucontrol";
        };
        "custom/network-activity" = {
          format = "{}";
          interval = 2;
          tooltip = false;
          exec = ''
            ${pkgs.bash}/bin/bash -c '
            state="/tmp/waybar_net_activity"
            interface=$(ip route | grep default | awk "{print \$5}" | head -1)
            if [ -z "$interface" ]; then
              echo "⬇ 0 mb/s ⬆ 0 mb/s"
              exit 0
            fi

            rx_now=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
            tx_now=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
            now=$(date +%s%N)

            if [ -f "$state" ]; then
              read -r rx_prev tx_prev ts_prev < "$state"
              elapsed_ns=$((now - ts_prev))
              if [ "$elapsed_ns" -gt 0 ]; then
                rx_diff=$((rx_now - rx_prev))
                tx_diff=$((tx_now - tx_prev))
                elapsed_s=$(awk "BEGIN {printf \"%.6f\", $elapsed_ns / 1000000000}")
                rx_mb=$(awk "BEGIN {printf \"%.2f\", $rx_diff / 1048576 / $elapsed_s}")
                tx_mb=$(awk "BEGIN {printf \"%.2f\", $tx_diff / 1048576 / $elapsed_s}")
                echo "⬇ $rx_mb mb/s ⬆ $tx_mb mb/s"
                echo "$rx_now $tx_now $now" > "$state"
                exit 0
              fi
            fi

            echo "$rx_now $tx_now $now" > "$state"
            echo "⬇ 0.00 mb/s ⬆ 0.00 mb/s"
            '
          '';
        };
        "custom/temperature" = {
          format = "󰔏 {}°";
          tooltip-format = "CPU Temp: {}°";
          interval = 5;
          exec =
            if hostName == "ionian" then
              ''
                ${pkgs.bash}/bin/bash -c '
                # For ionian, prefer Package id from coretemp or CPU from thinkpad sensor
                temp=$(sensors 2>/dev/null | grep -E "Package id 0:|CPU:" | grep -oE "\+[0-9]+\.[0-9]+" | head -1 | tr -d "+")
                if [ -z "$temp" ]; then
                  temp=$(sensors 2>/dev/null | grep -i "core 0" | grep -oE "[0-9]+\.[0-9]+|[0-9]+" | head -1)
                fi
                if [ -z "$temp" ]; then
                  echo "N/A"
                else
                  # Remove decimal part for cleaner display
                  echo "$temp" | awk "{printf \"%.0f\", \$1}"
                fi
                '
              ''
            else
              ''
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
        "custom/network-status" = {
          exec = ''
            ${pkgs.bash}/bin/bash -c '
            # Check if connected
            if ! ${pkgs.networkmanager}/bin/nmcli -t -f STATE g | grep -q connected; then
              echo "{\"text\": \"󰤭\", \"tooltip\": \"Disconnected\", \"class\": \"disconnected\"}"
              exit 0
            fi

            # Get connection info
            device=$(${pkgs.networkmanager}/bin/nmcli -t -f DEVICE,TYPE,STATE d | grep "connected" | head -1)
            ifname=$(echo "$device" | cut -d: -f1)
            type=$(echo "$device" | cut -d: -f2)

            # Get Local IP
            local_ip=$(${pkgs.iproute2}/bin/ip -4 addr show "$ifname" | grep -oP "(?<=inet\s)\d+(\.\d+){3}")

            # Get Global IP (cache for 1 hour)
            cache="/tmp/waybar_global_ip"
            if [ ! -f "$cache" ] || [ $(($(date +%s) - $(stat -c %Y "$cache"))) -gt 3600 ]; then
              ${pkgs.curl}/bin/curl -s --max-time 2 https://api.ipify.org > "$cache" &
            fi
            global_ip=$(cat "$cache" 2>/dev/null || echo "Fetching...")

            if [ "$type" = "wifi" ]; then
              ssid=$(${pkgs.networkmanager}/bin/nmcli -t -f ACTIVE,SSID dev wifi | grep "^yes" | cut -d: -f2)
              signal=$(${pkgs.networkmanager}/bin/nmcli -t -f ACTIVE,SIGNAL dev wifi | grep "^yes" | cut -d: -f2)
              
              # Select icon
              if [ "$signal" -gt 80 ]; then icon="󰤨"
              elif [ "$signal" -gt 60 ]; then icon="󰤥"
              elif [ "$signal" -gt 40 ]; then icon="󰤢"
              elif [ "$signal" -gt 20 ]; then icon="󰤟"
              else icon="󰤯"
              fi
              
              text="$icon"
              tooltip="$ssid\nLocal IP: $local_ip\nGlobal IP: $global_ip"
            else
              text="󰈀 Connected"
              tooltip="$ifname\nLocal IP: $local_ip\nGlobal IP: $global_ip"
            fi

            echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"connected\"}"
            '
          '';
          return-type = "json";
          interval = 10;
          on-click = "kitty --class tui-network --override confirm_os_window_close=0 -e nmtui";
          on-click-right = "kitty --class tui-speedtest -e sh -c 'speedtest; read -p \"Press Enter to close...\"'";
        };
        bluetooth = {
          format = "󰂯";
          format-disabled = "󰂯";
          format-off = "󰂯";
          format-on = "󰂯";
          format-connected = "󰂯";
          tooltip-format = "{controller_alias}\t{controller_address}\n\n{num_connections} connected";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{num_connections} connected\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
          on-click = "kitty --class tui-bluetooth --override confirm_os_window_close=0 -e bluetuith";
        };
        battery = {
          format = "{icon} {capacity}%";
          format-charging = "󱐋 {capacity}%";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
          tooltip-format = "{time}";
          tooltip-format-charging = "{time} until fully charged";
          tooltip-format-discharging = "{time} until empty";
        };
        "custom/dnd" = {
          format = "{}";
          interval = "once";
          signal = 8;
          tooltip = false;
          exec = ''
            ${pkgs.bash}/bin/bash -c '
            result=$(${pkgs.dunst}/bin/dunstctl is-paused 2>/dev/null)
            if [ "$result" = "true" ]; then
              echo "󰂛"
            else
              echo ""
            fi
            '
          '';
          on-click-right = ''
            ${pkgs.bash}/bin/bash -c '${pkgs.dunst}/bin/dunstctl set-paused toggle && pkill -SIGRTMIN+8 waybar'
          '';
        };
        clock = {
          format = "{:%R}";
          format-alt = "{:%R %A, %B %d}";
          timezone = "America/Argentina/Buenos_Aires";
          tooltip = false;
          on-click-right = ''
            ${pkgs.bash}/bin/bash -c '${pkgs.dunst}/bin/dunstctl set-paused toggle && pkill -SIGRTMIN+8 waybar'
          '';
          actions = {
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
          dynamic-order = [
            "title"
            "artist"
          ];
          tooltip = false;
          cursor = 60; # GDK cursor type 60 = HAND2 (pointer)
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
            ${pkgs.curl}/bin/curl -s "wttr.in?format=%t" | head -1 | tr -d '+'
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
            padding: 2px 6px;
        }

        #custom-network-activity,
        #custom-network-status,
        #bluetooth,
        #custom-weather,
        #pulseaudio,
        #custom-temperature,
        #cpu,
        #memory,
        #battery {
            padding: 2px 6px;
            margin: 0 2px;
        }
        
        #custom-dnd {
            padding: 2px 10px;
        }
        
        /* Force no borders/margins on all workspace button states to prevent shifting */
        #workspaces button {
            padding: 4px;
            min-width: 20px;
            min-height: 20px;
            background-color: transparent;
            box-shadow: none;
            border: none;
            border-radius: 50%;
            margin: 0;
            transition: background-color 0.3s ease-in-out;
        }

        #workspaces button:hover,
        #workspaces button.active:hover,
        #workspaces button.focused:hover {
            box-shadow: none;
            background-color: rgba(255, 255, 255, 0.2);
            border-radius: 50%;
            border: none;
            text-shadow: none;
        }
        
        #workspaces button.active,
        #workspaces button.focused {
          background-color: transparent;
          box-shadow: none;
          text-shadow: none;
          border: none;
          padding: 4px;
          min-width: 20px;
          min-height: 20px;
          margin: 0;
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
        #battery {
            letter-spacing: 0.1em;
        }
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
      PassEnvironment = [
        "WAYLAND_DISPLAY"
        "XDG_SESSION_TYPE"
        "PATH"
        "DBUS_SESSION_BUS_ADDRESS"
      ];
      Environment = [
        "XDG_SESSION_TYPE=wayland"
      ];
      # Unset DISPLAY to prevent X11 fallback
      UnsetEnvironment = [ "DISPLAY" ];
    };
  };
}
