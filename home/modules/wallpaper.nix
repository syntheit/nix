{ pkgs, ... }:

let
  wallpaper-cycle = pkgs.writeShellApplication {
    name = "wallpaper-cycle";

    runtimeInputs = with pkgs; [
      swww
      jq
      findutils
      coreutils
      gawk
      hyprland
    ];

    text = ''
      WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
      STATE_FILE="$HOME/.cache/wallpaper_history"

      # Ensure swww-daemon is running
      if ! pgrep -x swww-daemon > /dev/null; then
        swww-daemon &
        sleep 1
      fi

      # Ensure wallpaper directory exists
      if [ ! -d "$WALLPAPER_DIR" ]; then
        echo "Error: Wallpaper directory $WALLPAPER_DIR not found."
        exit 1
      fi

      # Get list of ALL .jpg files (basenames only)
      # We use find to get just filenames (-printf "%f\n") and sort them for comm
      mapfile -t ALL_FILES < <(find "$WALLPAPER_DIR" -maxdepth 1 -name "*.jpg" -printf "%f\n" | sort)

      if [ ''${#ALL_FILES[@]} -eq 0 ]; then
        echo "Error: No .jpg files found in $WALLPAPER_DIR"
        exit 1
      fi

      # Create state file if it doesn't exist
      if [ ! -f "$STATE_FILE" ]; then
        touch "$STATE_FILE"
      fi

      # Get list of HISTORY from STATE_FILE
      # Ensure history is sorted for comm
      mapfile -t HISTORY < <(sort "$STATE_FILE")

      # Calculate REMAINING = ALL - HISTORY
      # comm -23 produces lines in file 1 (ALL) that are not in file 2 (HISTORY)
      REMAINING=$(comm -23 <(printf "%s\n" "''${ALL_FILES[@]}") <(printf "%s\n" "''${HISTORY[@]}"))

      # Reset Condition: If REMAINING is empty, clear STATE_FILE, and set REMAINING = ALL
      if [ -z "$REMAINING" ]; then
        echo "All wallpapers cycled. Resetting history."
        : > "$STATE_FILE"
        REMAINING=$(printf "%s\n" "''${ALL_FILES[@]}")
      fi

      # Selection: Randomly pick one file from REMAINING
      CHOSEN=$(echo "$REMAINING" | shuf -n 1)

      if [ -z "$CHOSEN" ]; then
        echo "Error: Failed to select a wallpaper."
        exit 1
      fi

      echo "Selected: $CHOSEN"

      # Apply: Use hyprctl monitors -j to loop through active monitors and apply the image
      FULL_PATH="$WALLPAPER_DIR/$CHOSEN"
      
      # Get monitor names
      MONITORS=$(hyprctl monitors -j | jq -r '.[].name')

      for MON in $MONITORS; do
        swww img -o "$MON" "$FULL_PATH" --transition-type grow
      done

      # Update State: Append the chosen filename to STATE_FILE
      echo "$CHOSEN" >> "$STATE_FILE"
    '';
  };
in
{
  home.packages = [ wallpaper-cycle ];

  systemd.user.services.wallpaper-cycle = {
    Unit = {
      Description = "Smart Shuffle Wallpaper Cycle";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaper-cycle}/bin/wallpaper-cycle";
    };
  };

  systemd.user.timers.wallpaper-cycle = {
    Unit = {
      Description = "Cycle wallpaper daily and on login";
    };
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      OnBootSec = "1m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}

