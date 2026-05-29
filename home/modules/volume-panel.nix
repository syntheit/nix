{
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.volume-panel ];

  # Thin wrapper: optimistic sketchybar update + fire-and-forget IPC to daemon.
  # Skhd invokes this directly — no Swift CLI cold start on the hot path.
  home.file.".local/bin/volume-key" = {
    executable = true;
    text = ''
      #!/bin/bash
      ACTION="$1"
      STATE=/tmp/volume-state
      SOCK="$HOME/.config/volume-panel/volume.sock"

      LEVEL=50
      MUTED=false
      [ -f "$STATE" ] && source "$STATE"

      case "$ACTION" in
        up)   LEVEL=$((LEVEL + 6));;
        down) LEVEL=$((LEVEL - 6));;
        mute) [ "$MUTED" = "true" ] && MUTED=false || MUTED=true;;
      esac
      [ $LEVEL -gt 100 ] && LEVEL=100
      [ $LEVEL -lt 0 ] && LEVEL=0

      printf 'LEVEL=%d\nMUTED=%s\n' "$LEVEL" "$MUTED" > "$STATE"

      ${pkgs.sketchybar}/bin/sketchybar --trigger volume_change LEVEL="$LEVEL" MUTED="$MUTED" &
      echo "$ACTION" | /usr/bin/nc -U "$SOCK" >/dev/null 2>&1 &
      disown -a
    '';
  };

  launchd.agents.volume-panel = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.volume-panel}/bin/volume-panel" "daemon" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        HOME = "${config.home.homeDirectory}";
        VOLUME_PANEL_NO_HUD = "1";
      };
    };
  };
}
