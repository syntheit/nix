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
    pkgs.systemstats
    pkgs.spotify-watcher
  ];

  home.file.".local/bin/toggle-dnd" = {
    executable = true;
    text = ''
      #!/bin/bash
      DB="$HOME/Library/DoNotDisturb/DB/Assertions.json"
      ACTIVE=$(${pkgs.jq}/bin/jq '.data[0].storeAssertionRecords // [] | length' "$DB" 2>/dev/null)

      if [ "$ACTIVE" -gt 0 ] 2>/dev/null; then
        # DND is ON → disable
        ${pkgs.python3}/bin/python3 -c "
import json, time
with open('$DB') as f: data = json.load(f)
data['data'][0]['storeAssertionRecords'] = []
data['header']['timestamp'] = time.time() - 978307200
with open('$DB', 'w') as f: json.dump(data, f)
"
      else
        # DND is OFF → enable
        ${pkgs.python3}/bin/python3 -c "
import json, uuid, time
with open('$DB') as f: data = json.load(f)
now = time.time() - 978307200
data['data'][0]['storeAssertionRecords'] = [{
    'assertionUUID': str(uuid.uuid4()).upper(),
    'assertionSource': {'assertionClientIdentifier': 'com.apple.controlcenter.dnd'},
    'assertionStartDateTimestamp': now,
    'assertionDetails': {
        'assertionDetailsIdentifier': 'com.apple.controlcenter.dnd',
        'assertionDetailsModeIdentifier': 'com.apple.donotdisturb.mode.default',
        'assertionDetailsReason': 'user-action'
    }
}]
data['header']['timestamp'] = now
with open('$DB', 'w') as f: json.dump(data, f)
"
      fi

      /usr/bin/notifyutil -p com.apple.DoNotDisturb.stateChanged
      sketchybar --trigger dnd_change
    '';
  };

  home.file.".local/bin/toggle-privacy" = {
    executable = true;
    text = ''
      #!/bin/bash
      STATE_FILE="/tmp/.privacy-mode"

      if [ -f "$STATE_FILE" ]; then
        # Privacy mode ON → restore
        PREV_VOL=$(cat "$STATE_FILE")
        osascript -e "set volume input volume $PREV_VOL"
        rm -f "$STATE_FILE"
      else
        # Privacy mode OFF → kill mic + camera
        CURRENT_VOL=$(osascript -e 'input volume of (get volume settings)')
        [ "$CURRENT_VOL" = "0" ] && CURRENT_VOL=75
        echo "$CURRENT_VOL" > "$STATE_FILE"
        osascript -e 'set volume input volume 0'
        sudo /usr/bin/killall VDCAssistant 2>/dev/null
        sudo /usr/bin/killall AppleCameraAssistant 2>/dev/null
      fi

      sketchybar --trigger privacy_change
    '';
  };

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
        label.y_offset=-1 \
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
            script="$CONFIG_DIR/plugins/space_select.sh" \
            click_script="yabai -m space --focus $i"
      done

      # Visibility-only observer. The highlight color is driven instantly
      # by space_select.sh via the per-space $SELECTED edge; this observer
      # only handles drawing=on/off for empty non-current spaces, where a
      # ~100ms delay isn't perceptible.
      sketchybar --add item space_observer left \
        --set space_observer \
          drawing=off \
          script="$CONFIG_DIR/plugins/space.sh" \
        --subscribe space_observer space_change space_windows_change

      sketchybar --add event spotify_change
      sketchybar --add event brightness_change
      sketchybar --add event brightness_hide

      sketchybar --add item spotify left \
        --set spotify \
          update_freq=60 \
          icon.drawing=off \
          script="$CONFIG_DIR/plugins/spotify.sh" \
          click_script="open -a Spotify" \
        --subscribe spotify spotify_change

      sketchybar --add slider brightness_overlay left 160 \
        --set brightness_overlay \
          drawing=off \
          icon="󰖨" \
          icon.padding_left=8 \
          icon.padding_right=10 \
          icon.color=0xffa9b1d6 \
          label.drawing=off \
          slider.highlight_color=0xff7aa2f7 \
          slider.background.color=0xff414868 \
          slider.background.height=4 \
          slider.background.corner_radius=2 \
          slider.knob.drawing=off \
          script="$CONFIG_DIR/plugins/brightness.sh" \
        --subscribe brightness_overlay brightness_change brightness_hide
      sketchybar --add item battery right \
        --set battery \
          update_freq=120 \
          icon.padding_right=0 \
          script="$CONFIG_DIR/plugins/battery.sh" \
        --subscribe battery system_woke power_source_change

      sketchybar --add item ram right \
        --set ram \
          update_freq=0 \
          icon="󰘚"

      sketchybar --add item cpu right \
        --set cpu \
          update_freq=0 \
          icon="󰍛"

      sketchybar --add item cpu_temp right \
        --set cpu_temp \
          update_freq=5 \
          icon="" \
          script="$CONFIG_DIR/plugins/stats.sh"

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
          click_script="bluetooth-panel dropdown"

      sketchybar --add item network right \
        --set network \
          update_freq=15 \
          icon.padding_right=0 \
          label.drawing=off \
          icon="󰤨" \
          script="$CONFIG_DIR/plugins/network.sh" \
          click_script="wifi-panel dropdown"

      sketchybar --add event privacy_change
      sketchybar --add event dnd_change

      sketchybar --add item camera right \
        --set camera \
          update_freq=0 \
          icon.padding_right=0 \
          label.drawing=off \
          icon="󰄀" \
          script="$CONFIG_DIR/plugins/privacy.sh" \
          click_script="${config.home.homeDirectory}/.local/bin/toggle-privacy" \
        --subscribe camera privacy_change

      sketchybar --add item mic right \
        --set mic \
          update_freq=0 \
          icon.padding_right=0 \
          label.drawing=off \
          icon="󰍬" \
          script="$CONFIG_DIR/plugins/privacy.sh" \
          click_script="${config.home.homeDirectory}/.local/bin/toggle-privacy" \
        --subscribe mic privacy_change

      sketchybar --add item dnd right \
        --set dnd \
          update_freq=0 \
          icon.padding_right=0 \
          label.drawing=off \
          icon="󰤄" \
          icon.color=$WHITE \
          drawing=off \
          script="$CONFIG_DIR/plugins/dnd.sh" \
          click_script="${config.home.homeDirectory}/.local/bin/toggle-dnd" \
        --subscribe dnd dnd_change

      sketchybar --add item clock right \
        --set clock \
          update_freq=10 \
          icon.drawing=off \
          script="$CONFIG_DIR/plugins/clock.sh"

      sketchybar --update
    '';
  };

  # Plugin scripts

  # Per-space script. sketchybar fires this only on $SELECTED edge for
  # this item, i.e. exactly twice per space switch (leaving + entering),
  # driven by native NSWorkspaceActiveSpaceDidChange — no yabai roundtrip.
  xdg.configFile."sketchybar/plugins/space_select.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      if [ "$SELECTED" = "true" ]; then
        sketchybar --set $NAME background.color=0xff7aa2f7 icon.color=0xff1a1b26 drawing=on
      else
        sketchybar --set $NAME background.color=0x00000000 icon.color=0xffa9b1d6
      fi
    '';
  };

  # Visibility observer. Hides empty, non-current spaces. Subscribed to
  # space_change so a vacated empty space disappears, and to
  # space_windows_change so newly-empty spaces hide without a switch.
  xdg.configFile."sketchybar/plugins/space.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      CURRENT_SPACE=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index')
      WINDOWS=$(yabai -m query --windows 2>/dev/null)

      ARGS=()
      for i in {1..10}; do
        if [ "$i" = "$CURRENT_SPACE" ]; then
          ARGS+=(--set space.$i drawing=on)
        else
          WINDOW_COUNT=$(echo "$WINDOWS" | jq "[.[] | select(.space == $i)] | length")
          if [ "$WINDOW_COUNT" -gt 0 ]; then
            ARGS+=(--set space.$i drawing=on)
          else
            ARGS+=(--set space.$i drawing=off)
          fi
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

  # System stats plugin — single systemstats call updates cpu, ram, and temp
  xdg.configFile."sketchybar/plugins/stats.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      STATS=$(systemstats 2>/dev/null)
      if [ -n "$STATS" ]; then
        eval $(echo "$STATS" | ${pkgs.jq}/bin/jq -r '"CPU=\(.cpu) RAM=\(.ram) TEMP=\(.temp)"')
        sketchybar --set cpu label="''${CPU}%" \
                   --set ram label="''${RAM}%" \
                   --set cpu_temp label="''${TEMP}°C"
      fi
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

  xdg.configFile."sketchybar/plugins/brightness.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      if [ "$SENDER" = "brightness_change" ]; then
        if [ "$KIND" = "keyboard" ]; then
          ICON="󰥻"
        else
          ICON="󰖨"
        fi
        sketchybar \
          --set spotify drawing=off \
          --set brightness_overlay drawing=on icon="$ICON" slider.percentage="$LEVEL"
      elif [ "$SENDER" = "brightness_hide" ]; then
        sketchybar \
          --set brightness_overlay drawing=off \
          --set spotify drawing=on
      fi
    '';
  };

  xdg.configFile."sketchybar/plugins/spotify.sh" = {
    executable = true;
    text = ''
      #!/bin/bash

      apply() {
        local state="$1" title="$2" artist="$3" label
        if [ -z "$title" ] || [ "$state" = "stopped" ]; then
          sketchybar --set $NAME label=""
          return
        fi
        label="$title - $artist"
        if [ "$state" = "playing" ]; then
          sketchybar --set $NAME label="$label" label.color=0xffa9b1d6
        else
          sketchybar --set $NAME label="$label" label.color=0x99a9b1d6
        fi
      }

      if [ "$SENDER" = "spotify_change" ]; then
        apply "$STATE" "$TITLE" "$ARTIST"
      elif pgrep -x "Spotify" > /dev/null; then
        RESULT=$(osascript -e 'tell application "Spotify" to (player state as string) & "|" & (name of current track) & "|" & (artist of current track)' 2>/dev/null)
        IFS='|' read -r STATE TITLE ARTIST <<< "$RESULT"
        apply "$STATE" "$TITLE" "$ARTIST"
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
      if [ -n "$LEVEL" ]; then
        # Fast path: wrapper-triggered with env vars
        VOLUME="$LEVEL"
        IS_MUTED="$MUTED"
      else
        # Fallback: system volume_change (e.g. external slider) — resync state file
        SETTINGS=$(osascript -e 'get volume settings')
        VOLUME=$(echo "$SETTINGS" | grep -o 'output volume:[0-9]*' | cut -d: -f2)
        IS_MUTED=$(echo "$SETTINGS" | grep -o 'output muted:[a-z]*' | cut -d: -f2)
        printf 'LEVEL=%d\nMUTED=%s\n' "$VOLUME" "$IS_MUTED" > /tmp/volume-state
      fi

      if [ "$IS_MUTED" = "true" ]; then
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


  # DND Plugin — only shows icon when DND is active
  xdg.configFile."sketchybar/plugins/dnd.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      ACTIVE=$(${pkgs.jq}/bin/jq '.data[0].storeAssertionRecords // [] | length' "$HOME/Library/DoNotDisturb/DB/Assertions.json" 2>/dev/null)
      if [ "$ACTIVE" -gt 0 ] 2>/dev/null; then
        sketchybar --set dnd drawing=on
      else
        sketchybar --set dnd drawing=off
      fi
    '';
  };

  # Privacy (mic/camera) Plugin — visible when devices are active, hidden when killed
  xdg.configFile."sketchybar/plugins/privacy.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      if [ -f /tmp/.privacy-mode ]; then
        sketchybar --set mic drawing=off --set camera drawing=off
      else
        sketchybar --set mic drawing=on --set camera drawing=on
      fi
    '';
  };

  home.activation.reloadSketchybar = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.sketchybar}/bin/sketchybar --reload 2>/dev/null || true
    # Reset overlay state — --reload doesn't clear drawing=on/off on existing items
    run ${pkgs.sketchybar}/bin/sketchybar --set brightness_overlay drawing=off --set spotify drawing=on 2>/dev/null || true
  '';

  home.activation.reloadSkhd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /usr/bin/killall -USR1 skhd 2>/dev/null || true
  '';

  launchd.agents.sketchybar = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.sketchybar}/bin/sketchybar" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        PATH = "${pkgs.sketchybar}/bin:${pkgs.yabai}/bin:${pkgs.jq}/bin:${pkgs.systemstats}/bin:${pkgs.volume-panel}/bin:${pkgs.bluetooth-panel}/bin:${pkgs.wifi-panel}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        CONFIG_DIR = "${config.home.homeDirectory}/.config/sketchybar";
      };
    };
  };

  launchd.agents.spotify-watcher = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.spotify-watcher}/bin/spotify-watcher" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        SKETCHYBAR_BIN = "${pkgs.sketchybar}/bin/sketchybar";
      };
    };
  };
}
