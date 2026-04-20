{ pkgs, lib, ... }:
let
  jq = "${pkgs.jq}/bin/jq";

  # Runs on remote Linux servers via SSH — collects uptime, load, memory, temp, container count
  serverHealthScript = pkgs.writeShellScript "server-health" ''
    days=$(( $(cut -d. -f1 /proc/uptime | cut -d" " -f1) / 86400 ))
    load=$(cut -d" " -f1 /proc/loadavg)
    eval $(awk '/MemTotal/{printf "total=%d ", $2/1048576} /MemAvailable/{printf "avail=%d", $2/1048576}' /proc/meminfo)
    used=$((total - avail))
    temp=""
    for tz in /sys/class/thermal/thermal_zone*/temp; do
      t=$(cat "$tz" 2>/dev/null)
      [ -n "$t" ] && [ "$t" -gt 0 ] 2>/dev/null && { temp=$t; break; }
    done
    if [ -z "$temp" ]; then
      gw=$(ip route | awk '/default/ {print $3}')
      bat=$(ssh -p 8022 -i ~/.ssh/mainkey -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "$gw" cat /sys/class/power_supply/battery/temp 2>/dev/null)
      [ -n "$bat" ] && temp=$(( bat / 10 * 1000 ))
    fi
    temp_str=""; [ -n "$temp" ] && temp_str="  󰔏 ''${temp%???}°C"
    ct=$(docker ps -q 2>/dev/null | wc -l)
    echo "''${days}d  󰄧 $load   ''${used}/''${total}G''${temp_str}  󰡨 $ct"
  '';

  clockScript = pkgs.writeShellScript "dashboard-clock-darwin" ''
    tput civis
    trap 'tput cnorm' EXIT

    suffix() {
      case $1 in
        1|21|31) echo "st" ;;
        2|22)    echo "nd" ;;
        3|23)    echo "rd" ;;
        *)       echo "th" ;;
      esac
    }

    while true; do
      cols=$(tput cols)
      rows=$(tput lines)
      time_str=$(date +"%H:%M:%S")
      day=$(date +%-d)
      date_str="$(LC_TIME=en_US.UTF-8 date +"%B") ''${day}$(suffix "$day"), $(LC_TIME=en_US.UTF-8 date +%Y)"

      rendered=$(${pkgs.toilet}/bin/toilet -f mono9 -F metal "$time_str" | sed 's/\x1b\[0;1;30;90m/\x1b[0;34m/g')
      rwidth=$(echo "$rendered" | sed 's/\x1b\[[0-9;]*m//g' | wc -L)
      rheight=$(echo "$rendered" | wc -l)
      date_width=''${#date_str}

      pad_top=$(( (rows - rheight - 2) / 2 ))
      pad_left=$(( (cols - rwidth) / 2 ))
      date_pad=$(( (cols - date_width) / 2 ))
      [ "$pad_top" -lt 0 ] && pad_top=0
      [ "$pad_left" -lt 0 ] && pad_left=0
      [ "$date_pad" -lt 0 ] && date_pad=0

      hpad=$(printf '%*s' "$pad_left" "")
      dpad=$(printf '%*s' "$date_pad" "")

      buf=""
      for i in $(seq 1 "$pad_top"); do buf+="\n"; done
      while IFS= read -r line; do
        buf+="''${hpad}''${line}\n"
      done <<< "$rendered"
      buf+="\n\033[1;34m''${dpad}''${date_str}\033[0m\n"

      printf '\033[H\033[J%b' "$buf"
      sleep 1
    done
  '';

  dashboardInfoScript = pkgs.writeShellScript "dashboard-info-darwin" ''
    tput civis
    trap 'tput cnorm' EXIT

    cache_dir="/tmp/dashboard-cache"
    mkdir -p "$cache_dir"
    weather_last=0
    exchange_last=0
    servers_last=0

    while true; do
      now=$(date +%s)

      # ── Background fetches for slow data ──
      if [ $((now - weather_last)) -gt 1800 ]; then
        (curl -s --max-time 10 "wttr.in/?0" > "$cache_dir/weather" 2>/dev/null) &
        weather_last=$now
      fi
      if [ $((now - exchange_last)) -gt 1800 ]; then
        (
          ars=$(curl -s --max-time 10 "https://dolarapi.com/v1/dolares" 2>/dev/null | ${jq} -r '
            [.[] | select(.casa == "blue" or .casa == "oficial" or .casa == "bolsa")] |
            sort_by(if .casa == "blue" then 0 elif .casa == "oficial" then 1 else 2 end) |
            .[] | "\(if .casa == "oficial" then "Official" elif .casa == "blue" then "Blue" else "MEP" end): \(.compra | floor) / \(.venta | floor)"
          ')
          brl=$(curl -s --max-time 10 "https://raw.githubusercontent.com/syntheit/exchange-rates/refs/heads/main/rates.json" 2>/dev/null | ${jq} -r '.rates.BRL | . * 100 | round | . / 100 | tostring | "BRL: " + .')
          { [ -n "$ars" ] && echo "$ars"; [ -n "$brl" ] && echo "$brl"; } > "$cache_dir/exchange"
        ) &
        exchange_last=$now
      fi
      if [ $((now - servers_last)) -gt 1800 ]; then
        for srv in raven harbor; do
          (ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$srv" bash < ${serverHealthScript} > "$cache_dir/server_$srv" 2>/dev/null) &
        done
        servers_last=$now
      fi

      # ── Fast data ──

      # Spotify now playing
      now_playing=""
      spotify_running=$(osascript -e 'tell application "System Events" to (name of processes) contains "Spotify"' 2>/dev/null)
      if [ "$spotify_running" = "true" ]; then
        player_state=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null)
        if [ "$player_state" = "playing" ] || [ "$player_state" = "paused" ]; then
          title=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null)
          artist=$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null)
          icon="▶"; [ "$player_state" = "paused" ] && icon="⏸"
          now_playing="  $icon $title — $artist"
        fi
      fi

      # Volume
      vol_num=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
      vol_muted=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)
      vol_line=""
      if [ "$vol_muted" = "true" ]; then
        vol_line="  󰝟 Muted"
      elif [ -n "$vol_num" ]; then
        filled=$((vol_num / 5))
        bar=""
        for i in $(seq 1 20); do
          if [ "$i" -le "$filled" ]; then bar="''${bar}█"; else bar="''${bar}░"; fi
        done
        vol_line="  󰕾 ''${vol_num}%  ''${bar}"
      fi

      # Battery
      batt_pct=$(pmset -g batt | grep -o '[0-9]*%' | tr -d '%')
      batt_source=$(pmset -g batt | head -1)
      batt_line=""
      if [ -n "$batt_pct" ]; then
        if echo "$batt_source" | grep -q "AC Power"; then
          batt_line="  󰂄 ''${batt_pct}% (charging)"
        else
          remaining=$(pmset -g batt | grep -o '[0-9]*:[0-9]*' | head -1)
          batt_line="  󰁹 ''${batt_pct}%"
          [ -n "$remaining" ] && [ "$remaining" != "0:00" ] && batt_line="$batt_line ($remaining remaining)"
        fi
      fi

      # ── Read cached slow data ──
      exchange_cache=$(cat "$cache_dir/exchange" 2>/dev/null)
      raven_cache=$(cat "$cache_dir/server_raven" 2>/dev/null)
      harbor_cache=$(cat "$cache_dir/server_harbor" 2>/dev/null)
      weather_cache=$(cat "$cache_dir/weather" 2>/dev/null)

      # ── Render ──
      buf=""
      [ -n "$now_playing" ] && buf+="$now_playing\033[K\n\033[K\n"
      buf+="$vol_line\033[K\n"
      [ -n "$batt_line" ] && buf+="$batt_line\033[K\n"
      buf+="\033[K\n"
      if [ -n "$exchange_cache" ]; then
        while IFS= read -r eline; do buf+="$eline\033[K\n"; done <<< "$exchange_cache"
        buf+="\033[K\n"
      fi
      if [ -n "$raven_cache" ] || [ -n "$harbor_cache" ]; then
        [ -n "$raven_cache" ]  && buf+="$(printf '󱗆 %-8s %s' raven  "$raven_cache")\033[K\n"
        [ -n "$harbor_cache" ] && buf+="$(printf '󰒋 %-8s %s' harbor "$harbor_cache")\033[K\n"
        buf+="\033[K\n"
      fi
      if [ -n "$weather_cache" ]; then
        weather_title=$(echo "$weather_cache" | head -1 | sed 's/^ *//;s/ *$//')
        weather_body=$(echo "$weather_cache" | tail -n +2)
        buf+="$weather_title\033[K\n"
        while IFS= read -r wline; do buf+="$wline\033[K\n"; done <<< "$weather_body"
      fi

      printf '\033[H%b\033[J' "$buf"
      sleep 1
    done
  '';

  dashboardScript = pkgs.writeShellScript "dashboard-darwin" ''
    T="${pkgs.tmux}/bin/tmux"
    S="dashboard"

    if $T -L $S has-session -t $S 2>/dev/null; then
      exec $T -L $S attach -t $S
    fi

    $T -L $S new-session -d -s $S

    # Clean look: no status bar, invisible pane borders
    $T -L $S set status off
    $T -L $S set mouse on
    $T -L $S set pane-border-style "fg=black"
    $T -L $S set pane-active-border-style "fg=black"
    $T -L $S set set-titles off
    $T -L $S set allow-rename off

    # Layout: btop left (60%), clock/info/pipes stacked right (40%)
    $T -L $S split-window -h -l 40%
    $T -L $S split-window -v -l 90%
    $T -L $S split-window -v -l 40%

    $T -L $S send-keys -t 0 "btop" Enter
    $T -L $S send-keys -t 1 "${clockScript}" Enter
    $T -L $S send-keys -t 2 "${dashboardInfoScript}" Enter
    $T -L $S send-keys -t 3 "${pkgs.pipes}/bin/pipes.sh -t 0 -t 1 -p 2 -R -f 30 -r 3000 -c 1 -c 2 -c 3 -c 4 -c 5 -c 6 -c 7" Enter

    $T -L $S select-pane -t 2

    exec $T -L $S attach -t $S
  '';
in
{
  home.packages = with pkgs; [
    tmux
    toilet
    pipes
  ];

  # Toggle script at a fixed path so skhd can find it
  home.file.".local/bin/toggle-dashboard" = {
    executable = true;
    text = ''
      #!/bin/bash
      YABAI="/run/current-system/sw/bin/yabai"
      JQ="${pkgs.jq}/bin/jq"
      KITTY="/Applications/kitty.app/Contents/MacOS/kitty"
      SOCK="unix:/tmp/kitty-sock"

      # Find dashboard window by title
      DASHBOARD_WID=$($YABAI -m query --windows | $JQ -r '[.[] | select(.title == "dashboard")] | first | .id // empty')

      if [ -n "$DASHBOARD_WID" ]; then
        # Dashboard window exists — kill it (no background CPU waste)
        ${pkgs.tmux}/bin/tmux -L dashboard kill-server 2>/dev/null || true
        $YABAI -m window "$DASHBOARD_WID" --close 2>/dev/null || true
      else
        # No window — open dashboard in existing kitty instance (no extra process)
        $KITTY @ --to $SOCK launch --type=os-window --title dashboard -- ${dashboardScript} 2>/dev/null
        if [ $? -ne 0 ]; then
          # Kitty not running — start fresh instance
          $KITTY --title dashboard -e ${dashboardScript} &
        fi

        # Wait for window, set opacity, float above
        for i in $(seq 1 10); do
          sleep 0.3
          NEW_WID=$($YABAI -m query --windows | $JQ -r '[.[] | select(.title == "dashboard")] | first | .id // empty')
          if [ -n "$NEW_WID" ]; then
            $KITTY @ --to $SOCK set-background-opacity --match title:dashboard 1.0 2>/dev/null
            $YABAI -m window "$NEW_WID" --grid 1:1:0:0:1:1
            $YABAI -m window "$NEW_WID" --sub-layer above
            $YABAI -m window --focus "$NEW_WID"
            break
          fi
        done
      fi
    '';
  };

  # Kill dashboard tmux session on rebuild so it picks up script changes
  home.activation.restartDashboard = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.tmux}/bin/tmux -L dashboard kill-server 2>/dev/null || true
  '';
}
