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

      case "$ACTION" in
        up)   LEVEL=$((LEVEL + 6));;
        down) LEVEL=$((LEVEL - 6));;
      esac
      [ $LEVEL -gt 100 ] && LEVEL=100
      [ $LEVEL -lt 0 ] && LEVEL=0

      echo "LEVEL=$LEVEL" > "$STATE"

      # Stamp the cookie before triggering — any in-flight hide subshell
      # will see a new cookie and skip its trigger.
      echo $$ > "$COOKIE"

      "$SKETCHYBAR" --trigger brightness_change KIND="$KIND" LEVEL="$LEVEL" &

      if [ "$KIND" = "keyboard" ]; then
        [ "$ACTION" = "up" ] && CMD=kbup || CMD=kbdown
      else
        CMD="$ACTION"
      fi
      echo "$CMD" | /usr/bin/nc -U "$SOCK" >/dev/null 2>&1 &

      (
        sleep 1.5
        if [ "$(cat "$COOKIE" 2>/dev/null)" = "$$" ]; then
          "$SKETCHYBAR" --trigger brightness_hide
          rm -f "$COOKIE"
        fi
      ) &
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
