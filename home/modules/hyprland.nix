{
  pkgs,
  inputs,
  lib,
  config,
  hostName,
  ...
}:
let
  inherit (lib.generators) mkLuaInline;
  # A Nix string as a Lua string literal.
  lua = lib.generators.toLua { };

  # hl.bind(keys, dispatcher, opts) entries; `dispatcher` is Lua source. The
  # names follow hyprland.conf's bind flags (n, p, l, e, m).
  bindWith = opts: keys: dispatcher: {
    _args = [
      keys
      (mkLuaInline dispatcher)
    ]
    ++ lib.optional (opts != { }) opts;
  };
  bind = bindWith { };
  bindn = bindWith { non_consuming = true; };
  bindp = bindWith { dont_inhibit = true; };
  bindl = bindWith { locked = true; };
  bindel = bindWith {
    repeating = true;
    locked = true;
  };
  bindm = bindWith { mouse = true; };

  exec = command: "hl.dsp.exec_cmd(${lua command})";
  focusDirection = direction: "hl.dsp.focus({ direction = ${lua direction} })";
  focusWorkspace = workspace: "hl.dsp.focus({ workspace = ${lua workspace} })";
  moveToWorkspace = workspace: "hl.dsp.window.move({ workspace = ${lua workspace} })";

  # A centered floating window of `size` ("W H") that dims what's behind it.
  popupRule = matchKey: pattern: size: {
    match.${matchKey} = pattern;
    float = true;
    center = true;
    inherit size;
    dim_around = true;
  };

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
      $hyprctl dispatch 'hl.dsp.window.pin()'
      $hyprctl dispatch 'hl.dsp.window.float()'
    else
      is_floating=$(echo "$window" | $jq '.floating')
      if [ "$is_floating" = "false" ]; then
        $hyprctl dispatch 'hl.dsp.window.float()'
      fi

      monitor=$($hyprctl monitors -j | $jq '.[] | select(.focused)')
      width=$(echo "$monitor" | $jq '.width')
      height=$(echo "$monitor" | $jq '.height')
      scale=$(echo "$monitor" | $jq '.scale')

      pip_w=480
      pip_h=270
      x=$(${pkgs.gawk}/bin/awk "BEGIN {printf \"%.0f\", $width/$scale - $pip_w - 20}")
      y=$(${pkgs.gawk}/bin/awk "BEGIN {printf \"%.0f\", $height/$scale - $pip_h - 20}")

      $hyprctl --batch "dispatch hl.dsp.window.resize({ x = $pip_w, y = $pip_h }); dispatch hl.dsp.window.move({ x = $x, y = $y }); dispatch hl.dsp.window.pin()"
    fi
  '';

  # Script to handle Escape key behavior
  # 1. If active window is a TUI app, kill it
  # 2. Otherwise do nothing (and let bindn pass the key to the app)
  handleEscapeScript = pkgs.writeShellScript "handle-escape" ''
    # Get active window class
    hyprctl=${config.wayland.windowManager.hyprland.package}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq

    if active_window=$($hyprctl activewindow -j); then
      class=$(echo "$active_window" | $jq -r ".class")
      
      # Check if it matches our TUI list (case-insensitive)
      if echo "$class" | grep -qEi "^(telmo\.perf|com\.matv\.speedtest|com\.matv\.btop|org\.pulseaudio\.pavucontrol)$"; then
        $hyprctl dispatch 'hl.dsp.window.close()'
      fi
    fi
  '';
  # Steps every external monitor's brightness over DDC/CI: `ddc-brightness + 5`.
  # A press that arrives while the monitors are still answering is dropped, so
  # key repeat can't pile up writes. `ddcutil detect` takes seconds, so the
  # monitors' I2C buses are cached for the session and found again after a failure.
  ddcBrightness = pkgs.writeShellScript "ddc-brightness" ''
    ddcutil=${pkgs.ddcutil}/bin/ddcutil
    dir=''${XDG_RUNTIME_DIR:-/tmp}
    exec 9>"$dir/ddc-brightness.lock"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0
    buses="$dir/ddc-brightness.buses"
    if [ ! -s "$buses" ]; then
      $ddcutil detect --terse \
        | ${pkgs.gawk}/bin/awk '/^Display/ { ok = 1; next } /^[^ ]/ { ok = 0 } ok && /I2C bus:/ { sub(/.*i2c-/, ""); print }' \
        > "$buses"
    fi
    pids=()
    while read -r bus; do
      $ddcutil --bus "$bus" --noverify setvcp 10 "$1" "$2" &
      pids+=($!)
    done < "$buses"
    for pid in "''${pids[@]}"; do
      wait "$pid" || rm -f "$buses"
    done
  '';
  keybinds = pkgs.writeShellScriptBin "keybinds" ''
    cat <<'CHEATSHEET'
 ┌─────────────────────────────────────────────────────────┐
 │                      KEYBINDINGS                        │
 ├─────────────────────────────────────────────────────────┤
 │  Apps                                                   │
 │    Super + Space      Launcher (telmo)                  │
 │    Super + T          Terminal (Ghostty)                │
 │    Super + B          Bluetooth (telmo)                 │
 │    Super + N          Network (telmo)                   │
 │    Super + M          Sound (telmo)                     │
 │    Super + D          Display (telmo)                   │
 │    Super + U          Power (telmo)                     │
 │    Super + I          System monitor (btop)             │
 │    Super + E          File manager (Nautilus)           │
 │    Super + C          Clipboard (telmo)                 │
 │    Super + Z          Clock (telmo)                     │
 │    Super + X          System menu (telmo)               │
 │    Home               Dashboard (vestal)                │
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
 │    Super + Scroll     Cycle workspaces                  │
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
 │    Brightness keys    ±10% monitors (mantle)            │
 │    Mute key           Toggle mute                       │
 │    Play key           Play/pause                        │
 │    Next/Prev key      Next/previous track               │
 │    MX Vertical btn    Toggle Spotify                    │
 ├─────────────────────────────────────────────────────────┤
 │  Ghostty                                                │
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

  # Hyprland configuration, written as hyprland.lua: each `settings` entry
  # becomes an `hl.<name>(...)` call (https://wiki.hypr.land/Configuring/Start/).
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    xwayland.enable = true;
    # Enable systemd integration to ensure graphical-session.target is reached
    # This is required for Waybar and wallpaper services to start correctly.
    systemd.enable = true;

    settings = {
      config = {
        general = {
          gaps_in = 0;
          gaps_out = 0;
          # Borders stay invisible; col.active_border and col.inactive_border are managed by Stylix.
          border_size = 0;
        };

        decoration = {
          rounding = 0;
          inactive_opacity = 1.0;
        };

        binds.movefocus_cycles_fullscreen = true;

        misc = {
          disable_hyprland_logo = true;
        }
        # mantle: both M2763s do FreeSync 48-180 Hz. VRR only for fullscreen
        # games/video (3): always-on VRR on NVIDIA flickers on the desktop.
        // lib.optionalAttrs (hostName == "mantle") {
          vrr = 3;
        };

        input = {
          touchpad.natural_scroll = true;
          # Enable compose key on right Alt for typing accents
          kb_options = "compose:ralt";
        };

        cursor = {
          no_hardware_cursors = hostName == "mantle";
          warp_on_change_workspace = false;
          no_warps = true;
        };
      };

      animation =
        map (leaf: {
          inherit leaf;
          enabled = false;
        }) [ "specialWorkspace" "workspaces" "windowsMove" "fade" ]
        ++ map (leaf: {
          inherit leaf;
          enabled = true;
          speed = 3;
          bezier = "default";
        }) [ "fadeIn" "fadeOut" "fadeLayersIn" "fadeLayersOut" ];

      bind = [
        # Non-consuming bind for Escape (allows key to pass to apps like Vim)
        (bindn "escape" (exec "${handleEscapeScript}"))

        (bind "CTRL + SUPER + Space" "hl.dsp.window.float()")
        (bind "SUPER + T" (exec "ghostty"))
        # Super+B/N/M: telmo popups, bound in home/modules/telmo.nix.
        (bind "SUPER + E" (exec "nautilus"))
        (bind "SUPER + Q" "hl.dsp.window.close()")
        (bind "SUPER + F" "hl.dsp.window.fullscreen()")
        (bind "SUPER + h" (focusDirection "left"))
        (bind "SUPER + l" (focusDirection "right"))
        (bind "SUPER + j" (focusDirection "down"))
        (bind "SUPER + k" (focusDirection "up"))
        # Screenshot keybindings (area selections freeze screen via hyprpicker)
        (bind "SUPER + S" (exec "${pkgs.hyprpicker}/bin/hyprpicker -r -z & HPID=$!; trap 'kill $HPID 2>/dev/null' EXIT; sleep 0.2; ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy"))
        (bind "SUPER + SHIFT + S" (exec "${pkgs.hyprpicker}/bin/hyprpicker -r -z & HPID=$!; trap 'kill $HPID 2>/dev/null' EXIT; sleep 0.2; ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png"))
        (bind "SUPER + A" (exec "${pkgs.hyprpicker}/bin/hyprpicker -r -z & HPID=$!; trap 'kill $HPID 2>/dev/null' EXIT; sleep 0.2; ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" /tmp/screenshot-annotate.png && ${pkgs.satty}/bin/satty -f /tmp/screenshot-annotate.png"))
        (bind "SUPER + SHIFT + A" (exec "${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"))
        # Active window screenshots
        (bind "SUPER + W" (exec "${pkgs.grim}/bin/grim -g \"$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.at as [$x,$y] | .size as [$w,$h] | \"\\($x),\\($y) \\($w)x\\($h)\"')\" - | ${pkgs.wl-clipboard}/bin/wl-copy"))
        (bind "SUPER + SHIFT + W" (exec "${pkgs.grim}/bin/grim -g \"$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r '.at as [$x,$y] | .size as [$w,$h] | \"\\($x),\\($y) \\($w)x\\($h)\"')\" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png"))
        # Current monitor/output screenshots
        (bind "SUPER + O" (exec "${pkgs.grim}/bin/grim -o \"$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')\" - | ${pkgs.wl-clipboard}/bin/wl-copy"))
        (bind "SUPER + SHIFT + O" (exec "${pkgs.grim}/bin/grim -o \"$(hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')\" ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png"))
        # Screen recording toggles
        (bind "SUPER + SHIFT + R" (exec "${toggleRecording}"))
        (bind "SUPER + ALT + R" (exec "${toggleMonitorRecording}"))
        # Color picker (copies hex to clipboard)
        (bind "SUPER + P" (exec "${pkgs.hyprpicker}/bin/hyprpicker -a"))
        # Picture-in-picture toggle
        (bind "SUPER + SHIFT + P" (exec "${togglePip}"))
        # Hold Super + scroll wheel to cycle workspaces
        (bind "SUPER + mouse_down" (focusWorkspace "e+1"))
        (bind "SUPER + mouse_up" (focusWorkspace "e-1"))

        # Wallpaper cycling
        (bind "SUPER + ALT + period" (exec "wallpaper-cycle next"))
        (bind "SUPER + ALT + comma" (exec "wallpaper-cycle prev"))

        # Hold Super + drag: left button moves, right button resizes
        (bindm "SUPER + mouse:272" "hl.dsp.window.drag()")
        (bindm "SUPER + mouse:273" "hl.dsp.window.resize()")
      ]
      # `dont_inhibit` (bindp): these stay with mantle even while an app captures
      # the keyboard, e.g. the Mac mini window (mac-mini-desktop.nix), where
      # every other Super bind reaches the mac as Cmd.
      ++ [
        (bindp "SUPER + SHIFT + L" (exec "${pkgs.hyprlock}/bin/hyprlock"))
        # Relative workspace movement
        (bindp "SUPER + period" (focusWorkspace "+1"))
        (bindp "SUPER + comma" (focusWorkspace "-1"))
        (bindp "SUPER + SHIFT + period" (moveToWorkspace "+1"))
        (bindp "SUPER + SHIFT + comma" (moveToWorkspace "-1"))
      ]
      # Super + [Shift +] 1..0: [silently move the window to] workspace 1..10,
      # on the current monitor.
      ++ lib.concatMap (
        n:
        let
          key = toString (lib.mod n 10);
          ws = lua (toString n);
        in
        [
          (bindp "SUPER + ${key}" "hl.dsp.focus({ workspace = ${ws}, on_current_monitor = true })")
          (bindp "SUPER + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${ws}, follow = false })")
        ]
      ) (lib.range 1 10)
      # Media keys - using wpctl for Wayland-native volume control
      # -l 1.0 limits volume to 100% maximum
      ++ [
        (bindel "XF86AudioRaiseVolume" (exec "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"))
        (bindel "XF86AudioLowerVolume" (exec "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"))
      ]
      ++ lib.optionals (hostName == "ledger") [
        (bindel "XF86MonBrightnessUp" (exec "brightnessctl s 5%+"))
        (bindel "XF86MonBrightnessDown" (exec "brightnessctl s 5%-"))
      ]
      ++ lib.optionals (hostName == "mantle") [
        (bindel "XF86MonBrightnessUp" (exec "${ddcBrightness} + 10"))
        (bindel "XF86MonBrightnessDown" (exec "${ddcBrightness} - 10"))
      ]
      ++ [
        # MX Vertical top button (F20 via logid, evdev 190 + 8 = xkb 198)
        (bindl "code:198" "hl.dsp.workspace.toggle_special(\"spotify\")")
        (bindl "XF86AudioMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
        (bindl "XF86AudioPlay" (exec "playerctl --player=playerctld play-pause"))
        (bindl "XF86AudioNext" (exec "playerctl --player=playerctld next"))
        (bindl "XF86AudioPrev" (exec "playerctl --player=playerctld previous"))
      ]
      ++ lib.optionals (hostName == "ledger") [
        (bindl "switch:off:Lid Switch" (exec "${pkgs.hyprlock}/bin/hyprlock"))
      ];

      # Trackpad gestures
      gesture = [
        {
          fingers = 3;
          direction = "horizontal";
          action = "workspace";
        }
        {
          fingers = 3;
          direction = "up";
          action = "special";
        }
        {
          fingers = 4;
          direction = "horizontal";
          action = "workspace";
        }
      ];

      window_rule = [
        # Network Manager
        (popupRule "initial_class" "^(nm-connection-editor)$" "800 600")
        # PulseAudio Volume Control
        (popupRule "initial_class" "^(org.pulseaudio.pavucontrol)$" "800 600")
        # Speedtest TUI
        (popupRule "initial_class" "^(com.matv.speedtest)$" "800 400")
        # Btop TUI
        (popupRule "initial_class" "^(com.matv.btop)$" "1200 800")

        # Windscribe VPN
        {
          match.class = "^(Windscribe)$";
          float = true;
          opaque = true;
          no_blur = true;
          no_shadow = true;
        }

        # Spotify → hidden special workspace
        {
          match.class = "(?i)^spotify$";
          workspace = "special:spotify silent";
        }
      ];

      env =
        lib.mapAttrsToList (name: value: { _args = [ name value ]; }) {
          XDG_SESSION_TYPE = "wayland";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
          NIXOS_OZONE_WL = "1";
          QT_QPA_PLATFORMTHEME = "qtct";
          QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
          # Compose key (input.kb_options = compose:ralt) in GTK4 apps.
          # GTK 4.20 dropped GTK's own compose/dead-key handling on Wayland:
          # GtkIMContextWayland now defers to the compositor's text-input-v3 input
          # method, and Hyprland ships none — so Compose silently does nothing in
          # every GTK4 app, Ghostty included. (Accents kept working in GTK3/Qt/
          # Electron apps, which compose via xkbcommon or their own tables.)
          # "simple" pins GtkIMContextSimple, GTK's X11-style compose engine
          # (built-in sequence table + ~/.XCompose).
          # Safe here: no input method on these hosts (ibus is fajita-only). Drop
          # this if ibus/fcitx is ever added — it would make them unusable.
          GTK_IM_MODULE = "simple";
        }
        ++ lib.optionals (hostName == "mantle") (
          lib.mapAttrsToList (name: value: { _args = [ name value ]; }) {
            LIBVA_DRIVER_NAME = "nvidia";
            GBM_BACKEND = "nvidia-drm";
            __GLX_VENDOR_LIBRARY_NAME = "nvidia";
            NVD_BACKEND = "direct";
          }
        );
    };

    # Rendered after Home Manager's own startup hook (systemd session import).
    extraConfig = ''
      hl.on("hyprland.start", function()
        hl.exec_cmd(${lua "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"})
        -- Track most-recently-active MPRIS player so media keys follow it
        hl.exec_cmd(${lua "${pkgs.playerctl}/bin/playerctld daemon"})
        -- hyprsunset runs as a systemd user service (hyprland.nix)
      end)

      -- Monitor layout from nwg-displays, which writes ~/.config/hypr/monitors.lua
      -- and Hyprland reloads it on change. Last, so a missing file (a config
      -- error) can't stop the lines above.
      require("monitors")
    '';
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

  # Same compose-key fix for a Ghostty started by D-Bus activation instead of
  # by Hyprland: its .desktop is DBusActivatable, so a launcher can bring it up
  # via app-com.mitchellh.ghostty.service, which does not inherit Hyprland's
  # env (HM imports only DISPLAY/WAYLAND_DISPLAY/XDG_* into the user manager).
  systemd.user.sessionVariables.GTK_IM_MODULE = "simple";

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
