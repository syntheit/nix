{
  pkgs,
  vars,
  inputs,
  ...
}:
let
  raven-status = pkgs.writeShellScriptBin "raven-status" ''
    set -euo pipefail

    GATEWAY=$(ip route | awk '/default/ {print $3}')
    SSH="ssh -p 8022 -i ~/.ssh/mainkey -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no $GATEWAY"

    # Colors
    R='\033[0m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    BLUE='\033[34m'
    CYAN='\033[36m'
    WHITE='\033[37m'

    color_temp() {
      local t=''${1:-0}
      if [ "$t" -ge 45 ]; then printf "''${RED}"; elif [ "$t" -ge 38 ]; then printf "''${YELLOW}"; else printf "''${GREEN}"; fi
    }

    bar() {
      local pct=''${1:-0}
      local width=''${2:-30}
      local filled=$(( pct * width / 100 ))
      local empty=$(( width - filled ))
      local color
      if [ "$pct" -ge 60 ]; then color="''${GREEN}"; elif [ "$pct" -ge 25 ]; then color="''${YELLOW}"; else color="''${RED}"; fi
      printf "''${color}"
      for i in $(seq 1 $filled); do printf "█"; done
      printf "''${DIM}"
      for i in $(seq 1 $empty); do printf "░"; done
      printf "''${R}"
    }

    fetch() {
      $SSH "
        echo \"::BAT::\"
        cat /sys/class/power_supply/battery/capacity
        cat /sys/class/power_supply/battery/status
        cat /sys/class/power_supply/battery/temp
        cat /sys/class/power_supply/battery/voltage_now
        cat /sys/class/power_supply/battery/current_now
        cat /sys/class/power_supply/battery/cycle_count
        cat /sys/class/power_supply/battery/charge_full 2>/dev/null || echo 0
        cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null || echo 0
        echo \"::THERMAL::\"
        cat /sys/class/thermal/thermal_zone*/type
        echo \"::TEMPS::\"
        cat /sys/class/thermal/thermal_zone*/temp
        echo \"::UPTIME::\"
        uptime -s 2>/dev/null || echo unknown
        echo \"::MEM::\"
        free -b | grep Mem
      " 2>/dev/null
    }

    render() {
      local data="$1"

      # Parse battery
      local bat_section=$(echo "$data" | sed -n '/::BAT::/,/::THERMAL::/p' | grep -v '::')
      local capacity=$(echo "$bat_section" | sed -n '1p')
      local status=$(echo "$bat_section" | sed -n '2p')
      local temp_raw=$(echo "$bat_section" | sed -n '3p')
      local voltage_raw=$(echo "$bat_section" | sed -n '4p')
      local current_raw=$(echo "$bat_section" | sed -n '5p')
      local cycles=$(echo "$bat_section" | sed -n '6p')
      local charge_full=$(echo "$bat_section" | sed -n '7p')
      local charge_design=$(echo "$bat_section" | sed -n '8p')

      local temp_c=$(( temp_raw / 10 ))
      local temp_d=$(( temp_raw % 10 ))
      local voltage=$(echo "$voltage_raw" | awk '{printf "%.2f", $1/1000000}')
      local current=$(echo "$current_raw" | awk '{printf "%.0f", ($1<0?-$1:$1)/1000}')

      local health_pct=""
      if [ "$charge_design" -gt 0 ] 2>/dev/null && [ "$charge_full" -gt 0 ] 2>/dev/null; then
        health_pct=$(( charge_full * 100 / charge_design ))
      fi

      # Parse thermals
      local types=$(echo "$data" | sed -n '/::THERMAL::/,/::TEMPS::/p' | grep -v '::')
      local temps=$(echo "$data" | sed -n '/::TEMPS::/,/::UPTIME::/p' | grep -v '::')

      # Parse uptime
      local up_since=$(echo "$data" | sed -n '/::UPTIME::/,/::MEM::/p' | grep -v '::' | head -1)

      # Parse memory
      local mem_line=$(echo "$data" | sed -n '/::MEM::/,//p' | grep -v '::' | head -1)
      local mem_total=$(echo "$mem_line" | awk '{print $2}')
      local mem_used=$(echo "$mem_line" | awk '{print $3}')
      local mem_pct=0
      if [ "$mem_total" -gt 0 ] 2>/dev/null; then
        mem_pct=$(( mem_used * 100 / mem_total ))
      fi
      local mem_total_mb=$(( mem_total / 1048576 ))
      local mem_used_mb=$(( mem_used / 1048576 ))

      # Status icon
      local status_color
      case "$status" in
        Charging)    status_color="''${GREEN}" ;;
        Discharging) status_color="''${YELLOW}" ;;
        Full)        status_color="''${CYAN}" ;;
        *)           status_color="''${WHITE}" ;;
      esac

      # Render
      printf "\n"
      printf "  ''${BOLD}''${CYAN}RAVEN''${R} ''${DIM}Pixel 6 Pro / Tensor GS101''${R}\n"
      printf "  ''${DIM}────────────────────────────────────────────''${R}\n"
      printf "\n"

      # Battery
      printf "  ''${BOLD}BATTERY''${R}\n"
      printf "  $(bar $capacity 30)  ''${BOLD}%s%%''${R}  ''${status_color}%s''${R}\n" "$capacity" "$status"
      printf "  ''${DIM}''${temp_c}.''${temp_d}°C   ''${voltage}V   ''${current}mA   ''${cycles} cycles"
      if [ -n "$health_pct" ]; then printf "   health ''${health_pct}%%"; fi
      printf "''${R}\n\n"

      # CPU Thermals
      printf "  ''${BOLD}CPU''${R}\n"

      local i=0
      local t_big=0 t_mid=0 t_lit=0 t_gpu=0 t_tpu=0 t_isp=0
      local t_disp=0 t_batt=0 t_usb=0 t_quiet=0 t_neutral=0
      while IFS= read -r ttype; do
        i=$((i+1))
        local tval=$(echo "$temps" | sed -n "''${i}p")
        [ -z "$tval" ] && continue
        local tdeg=$(( tval / 1000 ))
        case "$ttype" in
          BIG)           t_big=$tdeg ;;
          MID)           t_mid=$tdeg ;;
          LITTLE)        t_lit=$tdeg ;;
          G3D)           t_gpu=$tdeg ;;
          TPU)           t_tpu=$tdeg ;;
          ISP)           t_isp=$tdeg ;;
          disp_therm)    t_disp=$tdeg ;;
          battery)       t_batt=$tdeg ;;
          usb_pwr_therm) t_usb=$tdeg ;;
          quiet_therm)   t_quiet=$tdeg ;;
          neutral_therm) t_neutral=$tdeg ;;
        esac
      done <<< "$types"

      printf "  $(color_temp $t_big)BIG    %2s°C''${R}    $(color_temp $t_mid)MID    %2s°C''${R}    $(color_temp $t_lit)LITTLE %2s°C''${R}\n" "$t_big" "$t_mid" "$t_lit"
      printf "\n"

      # Other processors
      printf "  ''${BOLD}ACCEL''${R}\n"
      printf "  $(color_temp $t_gpu)GPU    %2s°C''${R}    $(color_temp $t_tpu)TPU    %2s°C''${R}    $(color_temp $t_isp)ISP    %2s°C''${R}\n" "$t_gpu" "$t_tpu" "$t_isp"
      printf "\n"

      # Board thermals
      printf "  ''${BOLD}BOARD''${R}\n"
      printf "  ''${DIM}Display ''${R}$(color_temp $t_disp)%2s°C''${R}    ''${DIM}USB    ''${R}$(color_temp $t_usb)%2s°C''${R}    ''${DIM}Battery''${R} $(color_temp $t_batt)%2s°C''${R}\n" "$t_disp" "$t_usb" "$t_batt"
      printf "\n"

      # Memory
      printf "  ''${BOLD}MEMORY''${R}\n"
      printf "  $(bar $mem_pct 30)  ''${BOLD}%s%%''${R}  %sMB / %sMB\n" "$mem_pct" "$mem_used_mb" "$mem_total_mb"
      printf "\n"

      # Uptime
      printf "  ''${DIM}up since %s''${R}\n" "$up_since"
      printf "\n"
    }

    live=false
    for arg in "$@"; do
      case "$arg" in
        -l|--live) live=true ;;
      esac
    done

    if $live; then
      while true; do
        data=$(fetch)
        if [ -z "$data" ]; then
          printf "\n  ''${RED}Connection failed''${R}\n\n"
          sleep 2
          continue
        fi
        clear
        render "$data"
        sleep 2
      done
    else
      data=$(fetch)
      if [ -z "$data" ]; then
        printf "\n  ''${RED}Connection to Android failed''${R}\n\n"
        exit 1
      fi
      render "$data"
    fi
  '';
in
{
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    ../../home/shell.nix
    ../../home/modules/git.nix
    ../../home/modules/ssh.nix
  ];

  home.username = "droid";
  home.homeDirectory = "/home/droid";
  home.stateVersion = "26.05";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    android = "ssh -p 8022 -i ~/.ssh/mainkey $(ip route | awk '/default/ {print $3}')";
  };

  home.packages = with pkgs; [
    # CLI tools
    btop
    fastfetch
    tmux
    lazygit
    wget
    tree
    ripgrep
    fd
    unzip
    jq
    gh
    duf
    dig
    openssl
    traceroute
    lsof

    # Development
    python3
    go
    nodejs
    pnpm
    claude-code
    gnumake

    # Android status
    raven-status
  ];

  programs.home-manager.enable = true;
}
