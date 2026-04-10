{
  pkgs,
  inputs,
  lib,
  config,
  hostName,
  ...
}:
let
  # Script to handle Escape key behavior
  # 1. If Rofi is running, kill it (handles layer surface case)
  # 2. If active window is a TUI app/CopyQ, kill it
  # 3. Otherwise do nothing (and let bindn pass the key to the app)
  toggleRecording = pkgs.writeShellScript "toggle-recording" ''
    if ${pkgs.procps}/bin/pgrep -x wf-recorder > /dev/null; then
      ${pkgs.procps}/bin/pkill -INT wf-recorder
      ${pkgs.libnotify}/bin/notify-send "Recording stopped" "Saved to ~/Videos/"
    else
      area=$(${pkgs.slurp}/bin/slurp)
      if [ -n "$area" ]; then
        ${pkgs.wf-recorder}/bin/wf-recorder -g "$area" -f "$HOME/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4" &
        ${pkgs.libnotify}/bin/notify-send "Recording started"
      fi
    fi
  '';

  toggleMonitorRecording = pkgs.writeShellScript "toggle-monitor-recording" ''
    if ${pkgs.procps}/bin/pgrep -x wf-recorder > /dev/null; then
      ${pkgs.procps}/bin/pkill -INT wf-recorder
      ${pkgs.libnotify}/bin/notify-send "Recording stopped" "Saved to ~/Videos/"
    else
      output=$(${config.wayland.windowManager.hyprland.package}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
      ${pkgs.wf-recorder}/bin/wf-recorder -o "$output" -f "$HOME/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4" &
      ${pkgs.libnotify}/bin/notify-send "Recording started" "$output"
    fi
  '';

  togglePip = pkgs.writeShellScript "toggle-pip" ''
    hyprctl=${config.wayland.windowManager.hyprland.package}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    window=$($hyprctl activewindow -j)
    is_pinned=$(echo "$window" | $jq '.pinned')

    if [ "$is_pinned" = "true" ]; then
      $hyprctl dispatch pin active
      $hyprctl dispatch togglefloating
    else
      is_floating=$(echo "$window" | $jq '.floating')
      if [ "$is_floating" = "false" ]; then
        $hyprctl dispatch togglefloating
      fi

      monitor=$($hyprctl monitors -j | $jq '.[] | select(.focused)')
      width=$(echo "$monitor" | $jq '.width')
      height=$(echo "$monitor" | $jq '.height')
      scale=$(echo "$monitor" | $jq '.scale')

      pip_w=480
      pip_h=270
      x=$(${pkgs.gawk}/bin/awk "BEGIN {printf \"%.0f\", $width/$scale - $pip_w - 20}")
      y=$(${pkgs.gawk}/bin/awk "BEGIN {printf \"%.0f\", $height/$scale - $pip_h - 20}")

      $hyprctl --batch "dispatch resizeactive exact $pip_w $pip_h; dispatch moveactive exact $x $y; dispatch pin active"
    fi
  '';

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
    # Fallback: grab Android host battery temp via gateway (for NixOS VMs on Android)
    if [ -z "$temp" ]; then
      gw=$(ip route | awk '/default/ {print $3}')
      bat=$(ssh -p 8022 -i ~/.ssh/mainkey -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "$gw" cat /sys/class/power_supply/battery/temp 2>/dev/null)
      [ -n "$bat" ] && temp=$(( bat / 10 * 1000 ))
    fi
    temp_str=""; [ -n "$temp" ] && temp_str="  󰔏 ''${temp%???}°C"
    ct=$(docker ps -q 2>/dev/null | wc -l)
    echo "''${days}d  󰄧 $load   ''${used}/''${total}G''${temp_str}  󰡨 $ct"
  '';

  clockScript = pkgs.writeShellScript "dashboard-clock" ''
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

      # Render time with metal gradient, replace dark gray with blue for readability
      rendered=$(${pkgs.toilet}/bin/toilet -f mono9 -F metal "$time_str" | sed 's/\x1b\[0;1;30;90m/\x1b[0;34m/g')
      # Visible width (strip ANSI escapes, measure widest line)
      rwidth=$(echo "$rendered" | sed 's/\x1b\[[0-9;]*m//g' | wc -L)
      rheight=$(echo "$rendered" | wc -l)
      date_width=''${#date_str}

      # Center vertically and horizontally
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

  dashboardInfoScript = pkgs.writeShellScript "dashboard-info" ''
    tput civis
    trap 'tput cnorm' EXIT

    # Slow data cached to files (fetched in background, never blocks render)
    cache_dir="/tmp/dashboard-cache"
    mkdir -p "$cache_dir"
    weather_last=0
    wallpaper_last=0
    capture_last=0
    exchange_last=0
    servers_last=0

    while true; do
      now=$(date +%s)

      # ── Background fetches for slow data ──
      if [ $((now - weather_last)) -gt 1800 ]; then
        (curl -s --max-time 10 "wttr.in/Buenos+Aires,Argentina?0" > "$cache_dir/weather" 2>/dev/null) &
        weather_last=$now
      fi
      if [ $((now - wallpaper_last)) -gt 300 ]; then
        (wallpaper-cycle info 2>/dev/null | sed -n 's/^URL:  *//p' > "$cache_dir/wallpaper") &
        wallpaper_last=$now
      fi
      if [ $((now - exchange_last)) -gt 1800 ]; then
        (
          ars=$(curl -s --max-time 10 "https://dolarapi.com/v1/dolares" 2>/dev/null | ${pkgs.jq}/bin/jq -r '
            [.[] | select(.casa == "blue" or .casa == "oficial" or .casa == "bolsa")] |
            sort_by(if .casa == "oficial" then 0 elif .casa == "blue" then 1 else 2 end) |
            .[] | "\(if .casa == "oficial" then "Official" elif .casa == "blue" then "Blue" else "MEP" end): \(.compra | floor) / \(.venta | floor)"
          ')
          brl=$(curl -s --max-time 10 "https://raw.githubusercontent.com/syntheit/exchange-rates/refs/heads/main/rates.json" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.rates.BRL | . * 100 | round | . / 100 | tostring | "BRL: " + .')
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
      if [ $((now - capture_last)) -gt 5 ]; then
        (pw-dump 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | select(.info.props["media.class"] == "Stream/Input/Audio") | .info.props["application.name"] // empty' > "$cache_dir/capture" 2>/dev/null) &
        capture_last=$now
      fi

      # ── Fast data (collected inline) ──
      player_status=$(${pkgs.playerctl}/bin/playerctl status 2>/dev/null)
      now_playing=""
      if [ "$player_status" = "Playing" ] || [ "$player_status" = "Paused" ]; then
        title=$(${pkgs.playerctl}/bin/playerctl metadata title 2>/dev/null)
        artist=$(${pkgs.playerctl}/bin/playerctl metadata artist 2>/dev/null)
        icon="▶"; [ "$player_status" = "Paused" ] && icon="⏸"
        now_playing="  $icon $title — $artist"
      fi

      vol_info=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
      vol_num=$(echo "$vol_info" | ${pkgs.gawk}/bin/awk '{printf "%.0f", $2 * 100}')
      vol_line=""
      if echo "$vol_info" | grep -q MUTED; then
        vol_line="  󰝟 Muted"
      else
        filled=$((vol_num / 5))
        bar=""
        for i in $(seq 1 20); do
          if [ "$i" -le "$filled" ]; then bar="''${bar}█"; else bar="''${bar}░"; fi
        done
        vol_line="  󰕾 ''${vol_num}%  ''${bar}"
      fi

      mic_json=$(usb-toggle mic waybar 2>/dev/null)
      cam_json=$(usb-toggle cam waybar 2>/dev/null)
      mic_icon=$(echo "$mic_json" | ${pkgs.jq}/bin/jq -r '.text // ""')
      cam_icon=$(echo "$cam_json" | ${pkgs.jq}/bin/jq -r '.text // ""')
      mic_tip=$(echo "$mic_json" | ${pkgs.jq}/bin/jq -r '.tooltip // ""')
      cam_tip=$(echo "$cam_json" | ${pkgs.jq}/bin/jq -r '.tooltip // ""')
      dev_line=""
      [ -n "$mic_icon" ] && dev_line="  $mic_icon $mic_tip  [m]"
      [ -n "$cam_icon" ] && dev_line="''${dev_line}    $cam_icon $cam_tip  [c]"

      # ── Read cached slow data from files ──
      capture_apps=$(cat "$cache_dir/capture" 2>/dev/null)
      exchange_cache=$(cat "$cache_dir/exchange" 2>/dev/null)
      raven_cache=$(cat "$cache_dir/server_raven" 2>/dev/null)
      harbor_cache=$(cat "$cache_dir/server_harbor" 2>/dev/null)
      weather_cache=$(cat "$cache_dir/weather" 2>/dev/null)
      wallpaper_cache=$(cat "$cache_dir/wallpaper" 2>/dev/null)

      # ── Render everything at once ──
      buf=""
      [ -n "$now_playing" ] && buf+="$now_playing\033[K\n\033[K\n"
      buf+="$vol_line\033[K\n\033[K\n"
      [ -n "$dev_line" ] && buf+="$dev_line\033[K\n"
      if [ -n "$capture_apps" ]; then
        buf+="\033[K\n  ⚠  Audio capture: $capture_apps\033[K\n"
      fi
      if [ -n "$exchange_cache" ]; then
        buf+="\033[K\n"
        while IFS= read -r eline; do buf+="$eline\033[K\n"; done <<< "$exchange_cache"
        buf+="\033[K\n"
      fi
      if [ -n "$raven_cache" ] || [ -n "$harbor_cache" ]; then
        [ -n "$raven_cache" ]  && buf+="$(printf '󱗆 %-8s %s' raven  "$raven_cache")\033[K\n"
        [ -n "$harbor_cache" ] && buf+="$(printf '󰒋 %-8s %s' harbor "$harbor_cache")\033[K\n"
        buf+="\033[K\n"
      fi
      if [ -n "$weather_cache" ]; then
        weather_body=$(echo "$weather_cache" | tail -n +2)
        buf+="Buenos Aires, Argentina\033[K\n"
        while IFS= read -r wline; do buf+="$wline\033[K\n"; done <<< "$weather_body"
        buf+="\033[K\n"
      fi
      if [ -n "$wallpaper_cache" ] && [ "$wallpaper_cache" != "(local file)" ]; then
        buf+="── Wallpaper [w] ──\033[K\n$wallpaper_cache\033[K\n"
      fi

      printf '\033[H%b\033[J' "$buf"

      read -rsn1 -t 1 key
      case $key in
        m|M) sudo usb-toggle mic toggle 2>/dev/null ;;
        c|C) sudo usb-toggle cam toggle 2>/dev/null ;;
        w|W) [ -n "$wallpaper_cache" ] && xdg-open "$wallpaper_cache" 2>/dev/null & ;;
      esac
    done
  '';

  dashboardScript = pkgs.writeShellScript "dashboard" ''
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

    # Escape hides dashboard
    $T -L $S bind -T root Escape run-shell "${config.wayland.windowManager.hyprland.package}/bin/hyprctl dispatch togglespecialworkspace dashboard"

    # Scroll anywhere adjusts volume
    $T -L $S bind -T root WheelUpPane run-shell -b "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
    $T -L $S bind -T root WheelDownPane run-shell -b "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"

    # Create all pane splits and sizing first, then launch programs.

    # pane 0 (left): btop
    $T -L $S split-window -h -l 40%          # pane 1 (right top)
    $T -L $S split-window -v -l 90%          # pane 2 (right middle)
    $T -L $S split-window -v -l 40%          # pane 3 (right bottom)

    # Now launch programs in each pane
    $T -L $S send-keys -t 0 "btop" Enter
    $T -L $S send-keys -t 1 "${clockScript}" Enter
    $T -L $S send-keys -t 2 "${dashboardInfoScript}" Enter
    $T -L $S send-keys -t 3 "pipes.sh -t 0 -t 1 -p 2 -R -f 30 -r 3000 -c 1 -c 2 -c 3 -c 4 -c 5 -c 6 -c 7" Enter

    # Focus status pane for mic/cam key toggles
    $T -L $S select-pane -t 2

    exec $T -L $S attach -t $S
  '';

  toggleDashboard = pkgs.writeShellScript "toggle-dashboard" ''
    hyprctl=${config.wayland.windowManager.hyprland.package}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    # Relaunch if dashboard window was closed
    if ! $hyprctl clients -j | $jq -e '.[] | select(.class == "dashboard")' > /dev/null 2>&1; then
      ${pkgs.kitty}/bin/kitty --class dashboard -e ${dashboardScript} &
    fi

    $hyprctl dispatch togglespecialworkspace dashboard
  '';

  handleEscapeScript = pkgs.writeShellScript "handle-escape" ''
    # Check if Rofi is running and kill it
    if ${pkgs.procps}/bin/pgrep -x rofi >/dev/null; then
      ${pkgs.procps}/bin/pkill -x rofi
      exit 0
    fi

    # Get active window class
    hyprctl=${config.wayland.windowManager.hyprland.package}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    if active_window=$($hyprctl activewindow -j); then
      class=$(echo "$active_window" | $jq -r ".class")
      
      # Check if it matches our TUI list (case-insensitive)
      if echo "$class" | grep -qEi "^(tui-network|tui-bluetooth|tui-speedtest|tui-btop|com.github.hluk.copyq)$"; then
        $hyprctl dispatch killactive
      fi
    fi
  '';
  keybinds = pkgs.writeShellScriptBin "keybinds" ''
    cat <<'CHEATSHEET'
 ┌─────────────────────────────────────────────────────────┐
 │                      KEYBINDINGS                        │
 ├─────────────────────────────────────────────────────────┤
 │  Apps                                                   │
 │    Super + R          Rofi launcher                     │
 │    Super + T          Terminal (Kitty)                  │
 │    Super + B          Bluetooth (bluetuith)             │
 │    Super + N          Network (nmtui)                   │
 │    Super + E          File manager (Nautilus)           │
 │    Super + V          Clipboard (CopyQ)                 │
 │    Super + Shift + V  Clipboard menu                    │
 │    Super + C          Clipboard (CopyQ)                 │
 │    Super + X          Power menu                        │
 │    Home               Dashboard                         │
 ├─────────────────────────────────────────────────────────┤
 │  Windows                                                │
 │    Super + Q          Kill window                       │
 │    Super + F          Fullscreen                        │
 │    Ctrl + Super + Space   Toggle floating               │
 │    Super + H/J/K/L    Focus left/down/up/right          │
 │    Super + Mouse L    Move window                       │
 │    Super + Mouse R    Resize window                     │
 │    Super + Shift + P  Picture-in-picture                │
 │    Super + Shift + L  Lock screen                       │
 ├─────────────────────────────────────────────────────────┤
 │  Workspaces                                             │
 │    Super + 1-0        Focus workspace 1-10              │
 │    Super + Shift + 1-0    Move to workspace 1-10        │
 │    Super + .          Next workspace                    │
 │    Super + ,          Previous workspace                │
 │    Super + Shift + .  Move window to next workspace     │
 │    Super + Shift + ,  Move window to prev workspace     │
 ├─────────────────────────────────────────────────────────┤
 │  Screenshots                                            │
 │    Super + S          Area → clipboard                  │
 │    Super + Shift + S  Area → ~/Pictures/Screenshots     │
 │    Super + A          Area → annotate (Satty)           │
 │    Super + Shift + A  Full monitor → clipboard          │
 │    Super + W          Active window → clipboard         │
 │    Super + Shift + W  Active window → file              │
 │    Super + O          Current monitor → clipboard       │
 │    Super + Shift + O  Current monitor → file            │
 │    Super + Shift + R  Record area (slurp)                │
 │    Super + Alt + R    Record active monitor              │
 │    Super + P          Color picker → clipboard          │
 ├─────────────────────────────────────────────────────────┤
 │  Wallpaper                                              │
 │    Super + Alt + .    Next wallpaper                    │
 │    Super + Alt + ,    Previous wallpaper                │
 ├─────────────────────────────────────────────────────────┤
 │  Media                                                  │
 │    Volume Up/Down     ±5% volume                        │
 │    Mute key           Toggle mute                       │
 │    Play key           Play/pause                        │
 │    Next/Prev key      Next/previous track               │
 │    MX Vertical btn    Toggle Spotify                    │
 ├─────────────────────────────────────────────────────────┤
 │  Kitty                                                  │
 │    Ctrl + Tab         Next tab                          │
 │    Ctrl + Shift + Tab Previous tab                      │
 │    Ctrl + Shift + T   New tab                           │
 │    Ctrl + Shift + W   Close tab                         │
 └─────────────────────────────────────────────────────────┘
CHEATSHEET
  '';
in
{
  home.packages = [ keybinds ];

  # Hyprland configuration
  # Kill dashboard tmux session on rebuild so it picks up changes on next toggle
  home.activation.restartDashboard = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.tmux}/bin/tmux -L dashboard kill-server 2>/dev/null || true
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    # Enable systemd integration to ensure graphical-session.target is reached
    # This is required for Waybar and wallpaper services to start correctly.
    systemd.enable = true;

    settings = {
      general = {
        gaps_in = 0;
        gaps_out = 0;
        # FORCE: Override Stylix's default border size (2) to keep borders invisible
        border_size = lib.mkForce 0;
        # col.active_border and col.inactive_border are managed by Stylix
      };

      decoration = {
        rounding = 0;
        inactive_opacity = 1.0;
      };

      animation = [
        "specialWorkspace, 0"
        "workspaces, 0"
        "windowsMove, 0"
        "fade, 0"
        "fadeIn, 1, 3, default"
        "fadeOut, 1, 3, default"
        "fadeLayersIn, 1, 3, default"
        "fadeLayersOut, 1, 3, default"
      ];

      "$mod" = "SUPER";

      # Non-consuming bind for Escape (allows key to pass to apps like Vim)
      bindn = [
        ", escape, exec, ${handleEscapeScript}"
      ];

      bind = [
        "$mod, R, exec, rofi -show drun"
        "CTRL $mod, Space, togglefloating"
        "$mod, T, exec, kitty"
        "$mod, B, exec, kitty --class tui-bluetooth --override confirm_os_window_close=0 -e bluetuith"
        "$mod, N, exec, kitty --class tui-network --override confirm_os_window_close=0 -e nmtui"
        "$mod, E, exec, nautilus"
        "$mod, C, exec, ${pkgs.copyq}/bin/copyq toggle"
        "$mod SHIFT, L, exec, ${pkgs.hyprlock}/bin/hyprlock"
        "$mod, X, exec, rofi -show powermenu -modi \"powermenu:rofi-power-menu --choices=suspend/reboot/shutdown --confirm=reboot/shutdown\""
        "$mod, Q, killactive"
        "$mod, F, fullscreen"
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r"
        "$mod, j, movefocus, d"
        "$mod, k, movefocus, u"
        # Screenshot keybindings (area selections freeze screen via hyprpicker)
        "$mod, S, exec, ${pkgs.hyprpicker}/bin/hyprpicker -r -z & HPID=$!; trap 'kill $HPID 2>/dev/null' EXIT; sleep 0.2; ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
        "$mod SHIFT, S, exec, ${pkgs.hyprpicker}/bin/hyprpicker -r -z & HPID=$!; trap 'kill $HPID 2>/dev/null' EXIT; sleep 0.2; ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png"
        "$mod, A, exec, ${pkgs.hyprpicker}/bin/hyprpicker -r -z & HPID=$!; trap 'kill $HPID 2>/dev/null' EXIT; sleep 0.2; ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" /tmp/screenshot-annotate.png && ${pkgs.satty}/bin/satty -f /tmp/screenshot-annotate.png"
        "$mod SHIFT, A, exec, ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"
        # Active window screenshots
        "$mod, W, exec, ${pkgs.grim}/bin/grim -g \"$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.at as [$x,$y] | .size as [$w,$h] | \"\\($x),\\($y) \\($w)x\\($h)\"')\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
        "$mod SHIFT, W, exec, ${pkgs.grim}/bin/grim -g \"$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.at as [$x,$y] | .size as [$w,$h] | \"\\($x),\\($y) \\($w)x\\($h)\"')\" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png"
        # Current monitor/output screenshots
        "$mod, O, exec, ${pkgs.grim}/bin/grim -o \"$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
        "$mod SHIFT, O, exec, ${pkgs.grim}/bin/grim -o \"$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')\" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png"
        # Screen recording toggles
        "$mod SHIFT, R, exec, ${toggleRecording}"
        "$mod ALT, R, exec, ${toggleMonitorRecording}"
        # Color picker (copies hex to clipboard)
        "$mod, P, exec, ${pkgs.hyprpicker}/bin/hyprpicker -a"
        # Picture-in-picture toggle
        "$mod SHIFT, P, exec, ${togglePip}"
        "$mod, V, exec, ${pkgs.copyq}/bin/copyq toggle"
        "$mod SHIFT, V, exec, ${pkgs.copyq}/bin/copyq menu"
        ", Home, exec, ${toggleDashboard}"
        # Relative workspace movement
        "$mod, period, workspace, +1"
        "$mod, comma, workspace, -1"
        "$mod SHIFT, period, movetoworkspace, +1"
        "$mod SHIFT, comma, movetoworkspace, -1"

        # Wallpaper cycling
        "$mod ALT, period, exec, wallpaper-cycle next"
        "$mod ALT, comma, exec, wallpaper-cycle prev"
      ]
      ++ (
        # workspaces
        # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
        builtins.concatLists (
          builtins.genList (
            x:
            let
              ws =
                let
                  c = (x + 1) / 10;
                in
                builtins.toString (x + 1 - (c * 10));
            in
            [
              "$mod, ${ws}, focusworkspaceoncurrentmonitor, ${toString (x + 1)}"
              "$mod SHIFT, ${ws}, movetoworkspacesilent, ${toString (x + 1)}"
            ]
          ) 10
        )
      );
      # Media keys - using wpctl for Wayland-native volume control
      # -l 1.0 limits volume to 100% maximum
      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"
      ]
      ++ lib.optionals (hostName == "ledger") [
        ", XF86MonBrightnessUp, exec, brightnessctl s 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl s 5%-"
      ];
      bindl = [
        ", code:198, togglespecialworkspace, spotify" # MX Vertical top button (F20 via logid, evdev 190 + 8 = xkb 198)
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ]
      ++ lib.optionals (hostName == "ledger") [
        ", switch:off:Lid Switch, exec, ${pkgs.hyprlock}/bin/hyprlock"
      ];
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      exec-once = [
        "${pkgs.copyq}/bin/copyq --start-server"
        "${pkgs.bash}/bin/bash -c 'sleep 1 && ${pkgs.copyq}/bin/copyq loadTheme ~/.config/copyq/themes/tokyodark.ini && ${pkgs.copyq}/bin/copyq hide'"
        "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"
        # Start dashboard in background
        "${pkgs.kitty}/bin/kitty --class dashboard -e ${dashboardScript}"
        # hyprsunset is managed by systemd (see below)
      ];
      binds = {
        movefocus_cycles_fullscreen = true;
      };
      misc = {
        disable_hyprland_logo = true;
      };
      input = {
        touchpad = {
          natural_scroll = true;
        };
        # Enable compose key on right Alt for typing accents
        kb_options = "compose:ralt";
      };
      # Trackpad gestures
      gesture = [
        "3, horizontal, workspace"
        "3, up, special"
        "4, horizontal, workspace"
      ];
      # Use nwg-displays to configure monitor settings
      # Will automatically reload from this file
      source = "~/.config/hypr/monitors.conf";
      windowrule = [
        "float 1, match:class ^(Rofi)$"

        # CopyQ
        "float 1, match:initial_class ^(com.github.hluk.copyq)$"
        "center 1, match:initial_class ^(com.github.hluk.copyq)$"
        "size 689 911, match:initial_class ^(com.github.hluk.copyq)$"
        "dim_around 1, match:initial_class ^(com.github.hluk.copyq)$"

        # Network Manager
        "float 1, match:initial_class ^(nm-connection-editor)$"
        "center 1, match:initial_class ^(nm-connection-editor)$"
        "size 800 600, match:initial_class ^(nm-connection-editor)$"
        "dim_around 1, match:initial_class ^(nm-connection-editor)$"

        # PulseAudio Volume Control
        "float 1, match:initial_class ^(org.pulseaudio.pavucontrol)$"
        "center 1, match:initial_class ^(org.pulseaudio.pavucontrol)$"
        "size 800 600, match:initial_class ^(org.pulseaudio.pavucontrol)$"
        "dim_around 1, match:initial_class ^(org.pulseaudio.pavucontrol)$"

        # Network Manager TUI
        "float 1, match:initial_class ^(tui-network)$"
        "center 1, match:initial_class ^(tui-network)$"
        "size 600 900, match:initial_class ^(tui-network)$"
        "dim_around 1, match:initial_class ^(tui-network)$"

        # Bluetooth TUI
        "float 1, match:initial_class ^(tui-bluetooth)$"
        "center 1, match:initial_class ^(tui-bluetooth)$"
        "size 1104 580, match:initial_class ^(tui-bluetooth)$"
        "dim_around 1, match:initial_class ^(tui-bluetooth)$"

        # Speedtest TUI
        "float 1, match:initial_class ^(tui-speedtest)$"
        "center 1, match:initial_class ^(tui-speedtest)$"
        "size 800 400, match:initial_class ^(tui-speedtest)$"
        "dim_around 1, match:initial_class ^(tui-speedtest)$"

        # Btop TUI
        "float 1, match:initial_class ^(tui-btop)$"
        "center 1, match:initial_class ^(tui-btop)$"
        "size 1200 800, match:initial_class ^(tui-btop)$"
        "dim_around 1, match:initial_class ^(tui-btop)$"

        # Windscribe VPN
        "float 1, match:class ^(Windscribe)$"
        "opaque on, match:class ^(Windscribe)$"
        "no_blur on, match:class ^(Windscribe)$"
        "no_shadow on, match:class ^(Windscribe)$"

        # Spotify → hidden special workspace
        "workspace special:spotify silent, match:class (?i)^spotify$"
        "workspace special:spotify silent, match:title ^Spotify.*Zen$"

        # Dashboard → hidden special workspace (toggled with Super+Home)
        "workspace special:dashboard silent, match:initial_class ^(dashboard)$"
      ];
      env = [
        "XDG_SESSION_TYPE,wayland"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "NIXOS_OZONE_WL,1"
        "QT_QPA_PLATFORMTHEME,qtct"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
      ]
      ++ lib.optionals (hostName == "mantle") [
        "LIBVA_DRIVER_NAME,nvidia"
        "GBM_BACKEND,nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "NVD_BACKEND,direct"
      ];
      cursor = {
        no_hardware_cursors = hostName == "mantle";
        warp_on_change_workspace = false;
        no_warps = true;
      };
    };
  };

  # Hyprsunset configuration
  # Blue light filter that turns on from 9:30pm to 5am
  xdg.configFile."hypr/hyprsunset.conf".text = ''
    max-gamma = 150

    # Night mode (Late night)
    profile {
        time = 0:00
        temperature = 5500
    }

    # Normal mode (Daytime)
    profile {
        time = 5:00
        identity = true
    }

    # Night mode (Evening)
    profile {
        time = 21:30
        temperature = 5500
    }
  '';

  # Hyprsunset systemd service with auto-restart on crash
  # TZ is needed to work around hyprwm/hyprsunset#83 (defaults to UTC on NixOS)
  systemd.user.services.hyprsunset = {
    Unit = {
      Description = "Hyprsunset blue light filter";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Environment = [ "TZ=America/Argentina/Buenos_Aires" ];
      ExecStart = "${pkgs.hyprsunset}/bin/hyprsunset";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
