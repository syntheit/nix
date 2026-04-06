{ pkgs, ... }:

let
  wallpaper-cycle = pkgs.writeShellApplication {
    name = "wallpaper-cycle";

    runtimeInputs = with pkgs; [
      awww
      jq
      curl
      coreutils
      file
      hyprland
    ];

    text = ''
      CACHE_DIR="$HOME/.cache/wallpapers"
      STATE_FILE="$CACHE_DIR/current"
      LOCAL_DIR="$HOME/Pictures/Wallpapers"
      mkdir -p "$CACHE_DIR" "$LOCAL_DIR"

      save_state() {
        # Save current wallpaper info: path, source url (if any)
        local path="$1" url="''${2:-}"
        printf '%s\n%s\n' "$path" "$url" > "$STATE_FILE"
      }

      get_current_path() {
        [ -f "$STATE_FILE" ] && sed -n '1p' "$STATE_FILE"
      }

      get_current_url() {
        [ -f "$STATE_FILE" ] && sed -n '2p' "$STATE_FILE"
      }

      apply_wallpaper() {
        local wallpaper="$1"
        # Ensure awww-daemon is running
        if ! awww query &>/dev/null; then
          setsid awww-daemon &>/dev/null &
          disown
          sleep 1
        fi
        MONITORS=$(hyprctl monitors -j | jq -r '.[].name')
        for MON in $MONITORS; do
          awww img -o "$MON" "$wallpaper" --transition-type fade
        done
      }

      fetch_wallpaper() {
        local timestamp fetch_file api_response img_url page_url
        timestamp=$(date +%Y%m%d%H%M%S)

        # Query Wallhaven API for a random high-res wallpaper
        api_response=$(curl -sf --max-time 10 \
          "https://wallhaven.cc/api/v1/search?categories=100&purity=100&sorting=random&atleast=2560x1440&ratios=16x9,16x10&q=nature+landscape") || return 1

        img_url=$(echo "$api_response" | jq -r '.data[0].path // empty')
        page_url=$(echo "$api_response" | jq -r '.data[0].url // empty')

        if [ -z "$img_url" ]; then
          echo "Wallhaven returned no results" >&2
          return 1
        fi

        # Determine extension from URL
        local ext
        ext="''${img_url##*.}"
        fetch_file="$CACHE_DIR/wallhaven_$timestamp.$ext"

        if ! curl -sfL -o "$fetch_file" --max-time 20 "$img_url"; then
          rm -f "$fetch_file"
          return 1
        fi

        file_size=$(stat -c%s "$fetch_file" 2>/dev/null || echo 0)
        if [ "$file_size" -lt 50000 ]; then
          rm -f "$fetch_file"
          return 1
        fi

        # Clean up old cached wallpapers (keep last 10)
        find "$CACHE_DIR" -name "wallhaven_*" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true

        save_state "$fetch_file" "$page_url"
        echo "Fetched wallpaper from Wallhaven ($file_size bytes)"
        echo "$fetch_file"
      }

      pick_local() {
        local history_file="$CACHE_DIR/local_history"
        touch "$history_file"

        shopt -s nullglob
        local files=()
        for f in "$LOCAL_DIR"/*.{jpg,jpeg,png,webp}; do
          files+=("$(basename "$f")")
        done
        shopt -u nullglob

        if [ ''${#files[@]} -eq 0 ]; then
          echo "No local wallpapers in $LOCAL_DIR" >&2
          return 1
        fi

        mapfile -t history < <(sort "$history_file")
        remaining=$(comm -23 <(printf "%s\n" "''${files[@]}" | sort) <(printf "%s\n" "''${history[@]}"))

        if [ -z "$remaining" ]; then
          : > "$history_file"
          remaining=$(printf "%s\n" "''${files[@]}")
        fi

        chosen=$(echo "$remaining" | shuf -n 1)
        echo "$chosen" >> "$history_file"
        local full_path="$LOCAL_DIR/$chosen"
        save_state "$full_path" ""
        echo "Selected local wallpaper: $chosen"
        echo "$full_path"
      }

      cmd_next() {
        local wallpaper
        if wallpaper=$(fetch_wallpaper); then
          wallpaper=$(echo "$wallpaper" | tail -1)
        elif wallpaper=$(pick_local); then
          wallpaper=$(echo "$wallpaper" | tail -1)
        else
          echo "No wallpapers available (Wallhaven failed and no local files)" >&2
          exit 1
        fi
        apply_wallpaper "$wallpaper"
      }

      cmd_current() {
        local path url
        path=$(get_current_path)
        if [ -z "$path" ]; then
          echo "No wallpaper has been set yet"
          exit 1
        fi
        echo "$path"
      }

      cmd_info() {
        local path url
        path=$(get_current_path)
        url=$(get_current_url)
        if [ -z "$path" ]; then
          echo "No wallpaper has been set yet"
          exit 1
        fi
        echo "Path: $path"
        if [ -n "$url" ]; then
          echo "URL:  $url"
        else
          echo "URL:  (local file)"
        fi
        if [ -f "$path" ]; then
          echo "Size: $(du -h "$path" | cut -f1)"
          echo "Type: $(file --brief "$path")"
        else
          echo "(file no longer exists)"
        fi
      }

      cmd_open() {
        local url
        url=$(get_current_url)
        if [ -z "$url" ]; then
          local path
          path=$(get_current_path)
          if [ -z "$path" ]; then
            echo "No wallpaper has been set yet" >&2
            exit 1
          fi
          echo "Current wallpaper is a local file, opening in file manager"
          xdg-open "$(dirname "$path")" &
        else
          echo "Opening: $url"
          xdg-open "$url" &
        fi
      }

      cmd_help() {
        echo "Usage: wallpaper-cycle [command]"
        echo ""
        echo "Commands:"
        echo "  next     Fetch a new wallpaper and apply it (default)"
        echo "  current  Print the current wallpaper path"
        echo "  info     Show details (path, URL, size, type)"
        echo "  open     Open the source URL in the browser (or folder for local files)"
        echo "  help     Show this help"
      }

      case "''${1:-next}" in
        next)    cmd_next ;;
        current) cmd_current ;;
        info)    cmd_info ;;
        open)    cmd_open ;;
        help|-h|--help) cmd_help ;;
        *)
          echo "Unknown command: $1" >&2
          cmd_help >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  home.packages = [ wallpaper-cycle ];

  systemd.user.services.wallpaper-cycle = {
    Unit = {
      Description = "Wallpaper cycle (Wallhaven + local fallback)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaper-cycle}/bin/wallpaper-cycle next";
      TimeoutStartSec = 30;
    };
  };

  systemd.user.timers.wallpaper-cycle = {
    Unit = {
      Description = "Cycle wallpaper every 24 hours";
    };
    Timer = {
      OnUnitActiveSec = "24h";
      OnBootSec = "10s";
      Persistent = true;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
