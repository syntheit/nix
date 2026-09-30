{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.brightness-panel ];

  # Thin wrapper: optimistic sketchybar update + fire-and-forget IPC to daemon.
  # Owns the auto-hide timer via cookie-gated cancellation (no kill required).
  # Usage: brightness-key up|down display|keyboard
  home.file.".local/bin/brightness-key" = {
    executable = true;
    text = ''
      #!/bin/bash
      ACTION="$1"
      KIND="''${2:-display}"
      STATE="/tmp/brightness-state-$KIND"
      COOKIE=/tmp/brightness-cookie
      SOCK="$HOME/.config/brightness-panel/brightness.sock"
      SKETCHYBAR=${pkgs.sketchybar}/bin/sketchybar

      LEVEL=50
      [ -f "$STATE" ] && source "$STATE"

      # Serialise presses so triggers reach sketchybar in order (mkdir is atomic).
      LOCK=/tmp/brightness-lock
      for _ in $(seq 1 50); do
        mkdir "$LOCK" 2>/dev/null && break
        # Reap a lock left behind by a killed wrapper
        [ -n "$(find "$LOCK" -maxdepth 0 -mtime +10s 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
        sleep 0.02
      done
      trap 'rmdir "$LOCK" 2>/dev/null' EXIT

      if [ "$KIND" = "keyboard" ]; then
        [ "$ACTION" = "up" ] && CMD=kbup || CMD=kbdown
      else
        CMD="$ACTION"
      fi

      # Level guess if the daemon is unreachable (daemon steps are 1/16 = 6%)
      case "$ACTION" in
        up)   LEVEL=$((LEVEL + 6));;
        down) LEVEL=$((LEVEL - 6));;
      esac

      # The daemon owns the real level (and fades to it); its reply is the
      # target, so the bar never drifts from a stale guess.
      RESP=$(echo "$CMD" | /usr/bin/nc -w 1 -U "$SOCK" 2>/dev/null)
      R=''${RESP#*:}
      R=''${R%%\}*}
      case "$R" in
        "" | *[!0-9]*) ;;
        *) LEVEL=$R;;
      esac
      [ $LEVEL -gt 100 ] && LEVEL=100
      [ $LEVEL -lt 0 ] && LEVEL=0

      echo "LEVEL=$LEVEL" > "$STATE"

      # Cookie present means the overlay is currently shown.
      VISIBLE=0
      [ -f "$COOKIE" ] && VISIBLE=1

      # Stamp the cookie before triggering: any in-flight hide subshell (and
      # the hide plugin itself) sees a new cookie and stands down.
      echo $$ > "$COOKIE"

      "$SKETCHYBAR" --trigger brightness_change KIND="$KIND" LEVEL="$LEVEL" VISIBLE="$VISIBLE"

      (
        sleep 1.5
        if [ "$(cat "$COOKIE" 2>/dev/null)" = "$$" ]; then
          rm -f "$COOKIE"
          "$SKETCHYBAR" --trigger brightness_hide
        fi
      ) >/dev/null 2>&1 &
      disown -a
    '';
  };

  launchd.agents.brightness-panel = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.brightness-panel}/bin/brightness-panel" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/brightness-panel.log";
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
        BRIGHTNESS_PANEL_NO_HUD = "1";
      };
    };
  };
}
