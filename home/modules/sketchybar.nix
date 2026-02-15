{
  pkgs,
  lib,
  config,
  ...
}:

lib.mkIf pkgs.stdenv.isDarwin {
  home.packages = [
    pkgs.sketchybar
    pkgs.blueutil
    pkgs.macmon
  ];

  xdg.configFile."sketchybar/sketchybarrc" = {
    executable = true;
    text = ''
      #!/bin/bash

      export BLACK=0xff000000
      export WHITE=0xffa9b1d6
      export BLUE=0xff7aa2f7
      export CYAN=0xff7dcfff
      export GREEN=0xff9ece6a
      export MAGENTA=0xffbb9af7
      export RED=0xfff7768e
      export YELLOW=0xffe0af68
      export TRANSPARENT=0x00000000

      sketchybar --bar \
        height=38 \
        blur_radius=0 \
        position=top \
        sticky=on \
        padding_left=10 \
        padding_right=10 \
        color=$BLACK \
        shadow=off

      sketchybar --default \
        icon.font="JetBrainsMono Nerd Font:Bold:14.0" \
        icon.color=$WHITE \
        label.font="JetBrainsMono Nerd Font:Bold:13.0" \
        label.color=$WHITE \
        padding_left=7 \
        padding_right=7


      for i in {1..10}; do
        sketchybar --add space space.$i left \
          --set space.$i \
            associated_space=$i \
            icon=$i \
            icon.padding_left=8 \
            icon.padding_right=8 \
            background.color=$TRANSPARENT \
            background.corner_radius=5 \
            background.height=24 \
            background.drawing=on \
            script="$CONFIG_DIR/plugins/space.sh" \
          --subscribe space.$i space_change space_windows_change
      done

      sketchybar --add item spotify left \
        --set spotify \
          update_freq=5 \
          icon.drawing=off \
          script="$CONFIG_DIR/plugins/spotify.sh"
      sketchybar --remove clock network bluetooth volume cpu_temp cpu ram battery >/dev/null 2>&1 || true

      sketchybar --add item battery right \
        --set battery \
          update_freq=120 \
          script="$CONFIG_DIR/plugins/battery.sh" \
        --subscribe battery system_woke power_source_change

      sketchybar --add item ram right \
        --set ram \
          update_freq=5 \
          icon="󰘚" \
          script="$CONFIG_DIR/plugins/ram.sh"

      sketchybar --add item cpu right \
        --set cpu \
          update_freq=5 \
          icon="󰍛" \
          script="$CONFIG_DIR/plugins/cpu.sh"

      sketchybar --add item cpu_temp right \
        --set cpu_temp \
          update_freq=5 \
          icon="" \
          script="$CONFIG_DIR/plugins/cpu_temp.sh"

      sketchybar --add item volume right \
        --set volume \
          update_freq=0 \
          icon="" \
          script="$CONFIG_DIR/plugins/volume.sh" \
        --subscribe volume volume_change

      sketchybar --add item bluetooth right \
        --set bluetooth \
          update_freq=5 \
          icon="" \
          script="$CONFIG_DIR/plugins/bluetooth.sh" \
          click_script="open 'x-apple.systempreferences:com.apple.BluetoothSettings'"

      sketchybar --add item network right \
        --set network \
          update_freq=5 \
          icon="󰤨" \
          script="$CONFIG_DIR/plugins/network.sh" \
          click_script="open 'x-apple.systempreferences:com.apple.wifi-settings-extension'"

      sketchybar --add item clock right \
        --set clock \
          update_freq=10 \
          icon.drawing=off \
          script="$CONFIG_DIR/plugins/clock.sh"

      sketchybar --update
    '';
  };

  # Plugin scripts
  xdg.configFile."sketchybar/plugins/space.sh" = {
    executable = true;
    text = ''
      #!/bin/bash

      # Get the space number from the item name (e.g., space.1 -> 1)
      SPACE_NUM=''${NAME#*.}

      # Query yabai to check if this space has any windows
      WINDOW_COUNT=$(yabai -m query --windows --space "$SPACE_NUM" 2>/dev/null | jq -e 'length' || echo "0")

      # Show space if it has windows OR if it's currently selected
      if [ "$WINDOW_COUNT" -gt 0 ] || [ "$SELECTED" = "true" ]; then
        # This space should be visible
        if [ "$SELECTED" = "true" ]; then
          # Selected space: highlighted background
          sketchybar --set $NAME \
            background.color=0xff7aa2f7 \
            icon.color=0xff1a1b26 \
            drawing=on
        else
          # Has windows but not selected: normal colors
          sketchybar --set $NAME \
            background.color=0x00000000 \
            icon.color=0xffa9b1d6 \
            drawing=on
        fi
      else
        # No windows and not selected: hide
        sketchybar --set $NAME drawing=off
      fi
    '';
  };

  xdg.configFile."sketchybar/plugins/clock.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      sketchybar --set $NAME label="$(date '+%H:%M')"
    '';
  };

  xdg.configFile."sketchybar/plugins/battery.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
      CHARGING=$(pmset -g batt | grep 'AC Power')

      if [ -n "$CHARGING" ]; then
        ICON="󱐋"
      elif [ "$PERCENTAGE" -gt 80 ]; then
        ICON=""
      elif [ "$PERCENTAGE" -gt 60 ]; then
        ICON=""
      elif [ "$PERCENTAGE" -gt 40 ]; then
        ICON=""
      elif [ "$PERCENTAGE" -gt 20 ]; then
        ICON=""
      else
        ICON=""
      fi

      sketchybar --set $NAME icon="$ICON" label="''${PERCENTAGE}%"
    '';
  };

  xdg.configFile."sketchybar/plugins/cpu.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      CPU=$(top -l 1 | grep -E "^CPU" | awk '{print $3}' | cut -d% -f1 | awk '{printf "%d", $1}')
      sketchybar --set $NAME label="''${CPU}%"
    '';
  };

  xdg.configFile."sketchybar/plugins/network.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      SSID=$(ipconfig getsummary en0 | awk -F ' SSID : '  '/ SSID : / {print $2}')

      if [ -n "$SSID" ]; then
        sketchybar --set $NAME icon="󰤨" label=""
      else
        # Fallback to check if generic connectivity exists
        IP=$(scutil --nwi | grep "address" | head -n 1 | awk '{print $3}')
        if [ -n "$IP" ]; then
             sketchybar --set $NAME icon="󰤨" label=""
        else
             sketchybar --set $NAME icon="󰤭" label=""
        fi
      fi
    '';
  };

  xdg.configFile."sketchybar/plugins/spotify.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      if pgrep -x "Spotify" > /dev/null; then
        TRACK=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null)
        ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null)
        if [ -n "$TRACK" ] && [ -n "$ARTIST" ]; then
          sketchybar --set $NAME label="$TRACK - $ARTIST"
        else
          sketchybar --set $NAME label=""
        fi
      else
        sketchybar --set $NAME label=""
      fi
    '';
  };

  # Volume Plugin
  xdg.configFile."sketchybar/plugins/volume.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      VOLUME=$(osascript -e "output volume of (get volume settings)")
      MUTED=$(osascript -e "output muted of (get volume settings)")

      if [ "$MUTED" != "false" ]; then
        ICON="󰝟"
      else
        case ''${VOLUME} in
          100) ICON="";;
          9[0-9]) ICON="";;
          8[0-9]) ICON="";;
          7[0-9]) ICON="";;
          6[0-9]) ICON="";;
          5[0-9]) ICON="";;
          4[0-9]) ICON="";;
          3[0-9]) ICON="";;
          2[0-9]) ICON="";;
          1[0-9]) ICON="";;
          [0-9]) ICON="";;
          *) ICON=""
        esac
      fi

      sketchybar --set $NAME icon="$ICON" label="$VOLUME%"
    '';
  };

  # Bluetooth Plugin
  xdg.configFile."sketchybar/plugins/bluetooth.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      if [ $(blueutil -p) = "1" ]; then
        sketchybar --set $NAME icon="" label=""
      else
        sketchybar --set $NAME icon="󰂲" label=""
      fi
    '';
  };

  # RAM Plugin
  xdg.configFile."sketchybar/plugins/ram.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      PAGE_SIZE=$(sysctl -n hw.pagesize)
      TOTAL_RAM=$(sysctl -n hw.memsize)

      # Get free, inactive and speculative pages
      FREE_PAGES=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
      SPEC_PAGES=$(vm_stat | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
      INACTIVE_PAGES=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')

      FREE_MEM_BYTES=$(( (FREE_PAGES + SPEC_PAGES + INACTIVE_PAGES) * PAGE_SIZE ))
      USED_MEM_BYTES=$(( TOTAL_RAM - FREE_MEM_BYTES ))

      PERCENTAGE=$(echo "scale=0; ($USED_MEM_BYTES * 100) / $TOTAL_RAM" | bc)

      sketchybar --set $NAME label="''${PERCENTAGE}%"
    '';
  };

  # Traffic Plugin (placeholder removed from main config but keeping script for now)
  xdg.configFile."sketchybar/plugins/traffic.sh" = {
    executable = true;
    text = ''
      #!/bin/bash

      function get_bytes {
        netstat -w1 -I en0 -l 1 | awk 'NR==3 {print $3, $6}'
      }

      BYTES=$(get_bytes)
      DOWN=$(echo $BYTES | awk '{print $1}')
      UP=$(echo $BYTES | awk '{print $2}')

      function format_speed {
        local speed=$1
        if [ -z "$speed" ]; then
          echo "0 B/s"
          return
        fi
        
        if [ "$speed" -ge 1048576 ]; then
          echo "$(echo "scale=1; $speed / 1048576" | bc) MB/s"
        elif [ "$speed" -ge 1024 ]; then
          echo "$(echo "scale=1; $speed / 1024" | bc) KB/s"
        else
          echo "$speed B/s"
        fi
      }

      DOWN_FORMAT=$(format_speed $DOWN)
      UP_FORMAT=$(format_speed $UP)

      sketchybar --set $NAME label="↓ $DOWN_FORMAT ↑ $UP_FORMAT"
    '';
  };

  # CPU Temp Plugin
  xdg.configFile."sketchybar/plugins/cpu_temp.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      # Use macmon to get actual CPU temperature on Apple Silicon
      TEMP=$(macmon pipe --interval 100 2>/dev/null | head -n 1 | jq -r '.temp.cpu_temp_avg | round' 2>/dev/null)

      if [ -n "$TEMP" ] && [ "$TEMP" != "null" ]; then
        sketchybar --set $NAME label="''${TEMP}°C"
      else
        sketchybar --set $NAME label="N/A"
      fi
    '';
  };

  launchd.agents.sketchybar = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.sketchybar}/bin/sketchybar" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        PATH = "${pkgs.sketchybar}/bin:${pkgs.yabai}/bin:${pkgs.jq}/bin:${pkgs.macmon}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        CONFIG_DIR = "${config.home.homeDirectory}/.config/sketchybar";
      };
    };
  };
}
