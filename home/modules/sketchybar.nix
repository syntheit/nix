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
        icon.padding_right=6 \
        label.font="JetBrainsMono Nerd Font:Bold:13.0" \
        label.color=$WHITE \
        padding_left=9 \
        padding_right=9


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
            click_script="yabai -m space --focus $i"
      done

      sketchybar --add item space_observer left \
        --set space_observer \
          drawing=off \
          script="$CONFIG_DIR/plugins/space.sh" \
        --subscribe space_observer space_change space_windows_change

      sketchybar --add item spotify left \
        --set spotify \
          update_freq=5 \
          icon.drawing=off \
          script="$CONFIG_DIR/plugins/spotify.sh" \
          click_script="open -a Spotify"
      sketchybar --add item battery right \
        --set battery \
          update_freq=120 \
          icon.padding_right=0 \
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
          update_freq=15 \
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
          update_freq=30 \
          icon.padding_right=0 \
          label.drawing=off \
          icon="" \
          script="$CONFIG_DIR/plugins/bluetooth.sh" \
          click_script="open 'x-apple.systempreferences:com.apple.BluetoothSettings'"

      sketchybar --add item network right \
        --set network \
          update_freq=15 \
          icon.padding_right=0 \
          label.drawing=off \
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

      # Single observer updates all space items atomically
      CURRENT_SPACE=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index')
      WINDOWS=$(yabai -m query --windows 2>/dev/null)

      ARGS=()
      for i in {1..10}; do
        WINDOW_COUNT=$(echo "$WINDOWS" | jq "[.[] | select(.space == $i)] | length")

        if [ "$i" = "$CURRENT_SPACE" ]; then
          ARGS+=(--set space.$i background.color=0xff7aa2f7 icon.color=0xff1a1b26 drawing=on)
        elif [ "$WINDOW_COUNT" -gt 0 ]; then
          ARGS+=(--set space.$i background.color=0x00000000 icon.color=0xffa9b1d6 drawing=on)
        else
          ARGS+=(--set space.$i drawing=off)
        fi
      done

      sketchybar "''${ARGS[@]}"
    '';
  };

  xdg.configFile."sketchybar/plugins/clock.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      sketchybar --set $NAME label="$(date '+%a %-d %b %H:%M')"
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
      NCPU=$(sysctl -n hw.logicalcpu)
      CPU=$(ps -A -o %cpu | awk -v n="$NCPU" 'NR>1{s+=$1} END {printf "%d", s/n}')
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
        INFO=$(osascript -e 'tell application "Spotify" to (name of current track) & " - " & (artist of current track)' 2>/dev/null)
        if [ -n "$INFO" ]; then
          sketchybar --set $NAME label="$INFO"
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
      SETTINGS=$(osascript -e 'get volume settings')
      VOLUME=$(echo "$SETTINGS" | grep -o 'output volume:[0-9]*' | cut -d: -f2)
      MUTED=$(echo "$SETTINGS" | grep -o 'output muted:[a-z]*' | cut -d: -f2)

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
      TOTAL_RAM=$(sysctl -n hw.memsize)
      VMSTAT=$(vm_stat)

      FREE_PAGES=$(echo "$VMSTAT" | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
      SPEC_PAGES=$(echo "$VMSTAT" | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')
      INACTIVE_PAGES=$(echo "$VMSTAT" | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')

      FREE_MEM_BYTES=$(( (FREE_PAGES + SPEC_PAGES + INACTIVE_PAGES) * 16384 ))
      PERCENTAGE=$(( (TOTAL_RAM - FREE_MEM_BYTES) * 100 / TOTAL_RAM ))

      sketchybar --set $NAME label="''${PERCENTAGE}%"
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

  home.activation.reloadSketchybar = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.sketchybar}/bin/sketchybar --reload 2>/dev/null || true
  '';

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
