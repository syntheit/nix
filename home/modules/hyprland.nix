{
  pkgs,
  inputs,
  lib,
  config,
  hostName,
  ...
}:
let
  # vista (HTPC) lid-aware display control: disable the internal panel only when
  # the lid is shut AND an external display (the TV) is connected; otherwise keep
  # it on. Reads actual lid + monitor state, so the same script is correct for
  # boot, lid-open, and lid-close. Referenced from monitor/bindl/exec-once below.
  vistaLidMonitor = pkgs.writeShellScript "vista-lid-monitor" ''
    hyprctl=${config.wayland.windowManager.hyprland.package}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq
    lid=$(cat /proc/acpi/button/lid/*/state 2>/dev/null)
    externals=$("$hyprctl" monitors all -j | "$jq" '[.[] | select(.name != "eDP-1")] | length')
    if echo "$lid" | grep -q closed && [ "''${externals:-0}" -ge 1 ]; then
      "$hyprctl" keyword monitor "eDP-1, disable"
    else
      "$hyprctl" keyword monitor "eDP-1, preferred, auto, 1.6"
    fi
  '';
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
      if echo "$class" | grep -qEi "^(telmo\.perf|com\.matv\.speedtest|com\.matv\.btop|com.github.hluk.copyq|org\.pulseaudio\.pavucontrol)$"; then
        $hyprctl dispatch killactive
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
 │    Super + R          Rofi launcher                     │
 │    Super + T          Terminal (Ghostty)                │
 │    Super + B          Bluetooth (telmo)                 │
 │    Super + N          Network (telmo)                   │
 │    Super + M          Sound (telmo)                     │
 │    Super + D          Display (telmo)                   │
 │    Super + U          Power (telmo)                     │
 │    Super + I          System monitor (btop)             │
 │    Super + E          File manager (Nautilus)           │
 │    Super + V          Clipboard (telmo)                 │
 │    Super + Shift + V  Clipboard menu                    │
 │    Super + C          Clipboard (CopyQ)                 │
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

  # Hyprland configuration
  wayland.windowManager.hyprland = {
    enable = true;
    # Keep the legacy hyprlang serialization for `settings` (the new default
    # is "lua" for stateVersion >= 26.05). Pin it explicitly to silence the
    # deprecation warning and preserve current behavior.
    configType = "hyprlang";
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
        "$mod, T, exec, ghostty"
        # Super+B/N/M: telmo popups, bound in home/modules/telmo.nix.
        "$mod, E, exec, nautilus"
        "$mod, C, exec, ${pkgs.copyq}/bin/copyq toggle"
        "$mod SHIFT, L, exec, ${pkgs.hyprlock}/bin/hyprlock"
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
        "$mod SHIFT, V, exec, ${pkgs.copyq}/bin/copyq menu"
        # Relative workspace movement
        "$mod, period, workspace, +1"
        "$mod, comma, workspace, -1"
        "$mod SHIFT, period, movetoworkspace, +1"
        "$mod SHIFT, comma, movetoworkspace, -1"
        # Hold Super + scroll wheel to cycle workspaces
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"

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
      ]
      ++ lib.optionals (hostName == "mantle") [
        ", XF86MonBrightnessUp, exec, ${ddcBrightness} + 10"
        ", XF86MonBrightnessDown, exec, ${ddcBrightness} - 10"
      ];
      bindl = [
        ", code:198, togglespecialworkspace, spotify" # MX Vertical top button (F20 via logid, evdev 190 + 8 = xkb 198)
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl --player=playerctld play-pause"
        ", XF86AudioNext, exec, playerctl --player=playerctld next"
        ", XF86AudioPrev, exec, playerctl --player=playerctld previous"
      ]
      ++ lib.optionals (hostName == "ledger") [
        ", switch:off:Lid Switch, exec, ${pkgs.hyprlock}/bin/hyprlock"
      ]
      ++ lib.optionals (hostName == "vista") [
        # Any lid event re-runs the lid-aware script (it reads real lid +
        # external-display state, so one script handles both open and close).
        ", switch:on:Lid Switch, exec, ${vistaLidMonitor}"
        ", switch:off:Lid Switch, exec, ${vistaLidMonitor}"
      ];
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      exec-once = [
        # Theme is baked directly into ~/.config/copyq/copyq.conf at
        # home-manager activation time now (see copyq.nix) — `copyq loadTheme`
        # against a running server was verified not to reliably apply/persist
        # the theme (CopyQ bug, not a startup race), so don't rely on it here.
        "${pkgs.copyq}/bin/copyq --start-server"
        "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"
        # Track most-recently-active MPRIS player so media keys follow it
        "${pkgs.playerctl}/bin/playerctld daemon"
        # hyprsunset is managed by systemd (see below)
      ]
      ++ lib.optionals (hostName == "vista") [
        # Apply lid-aware monitor setup at startup (handles booting with the lid
        # already shut on the TV, where no lid-switch event fires).
        "${pkgs.bash}/bin/bash -c 'sleep 2; ${vistaLidMonitor}'"
        # NOTE: kdeconnectd is NOT started here — it runs as a home-manager
        # systemd user service (see hosts/vista/home.nix) pinned to
        # QT_QPA_PLATFORM=wayland so its remote-input backend uses the
        # RemoteDesktop portal instead of XTest. Starting it bare here gave it
        # DISPLAY=:0 + the xcb Qt platform, which broke remote input.
        #
        # RemoteDesktop portal backend (hypr-kdeconnect-fix) so KDE Connect's
        # remote input (phone as mouse/keyboard) has something to inject through.
        "hypr-kdeconnect-portal"
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
        }
        # vista: Apple Force Touch trackpad — tap-to-click, 2-finger tap =
        # right-click (clickfinger, macOS-style), and tap-and-drag.
        // lib.optionalAttrs (hostName == "vista") {
          "tap-to-click" = true;
          clickfinger_behavior = true;
          "tap-and-drag" = true;
        };
        # Enable compose key on right Alt for typing accents
        kb_options = "compose:ralt";
      };
      # Trackpad gestures
      # vista: ONLY 3-finger left/right to switch workspaces (no special-swipe,
      # no 4-finger) — per request. Other hosts keep the fuller gesture set.
      gesture = [
        "3, horizontal, workspace"
      ]
      ++ lib.optionals (hostName != "vista") [
        "3, up, special"
        "4, horizontal, workspace"
      ];
      # vista (HTPC + occasional laptop): enable every connected output at its
      # preferred mode — the internal panel (eDP-1) when used open as a laptop,
      # and/or the TV over USB-C→HDMI (name may be DP-* or HDMI-*). The internal
      # panel is turned off ONLY when the lid is shut AND a TV is connected,
      # handled by vistaLidMonitor (lid-switch bindl + startup exec-once).
      monitor = lib.optionals (hostName == "vista") [
        # Internal retina panel at a clean 1.6x (3072x1920 → 1920x1200 effective).
        "eDP-1, preferred, auto, 1.6"
        # Any external output (the TV) at its native mode, auto scale.
        ", preferred, auto, auto"
      ];
      # Use nwg-displays to configure monitor settings
      # Will automatically reload from this file. Skipped on vista, which has no
      # nwg-displays-generated monitors.conf (it uses the declarative monitor
      # rules above) — sourcing a missing file is a Hyprland config error.
      source = lib.optional (hostName != "vista") "~/.config/hypr/monitors.conf";
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


        # Speedtest TUI
        "float 1, match:initial_class ^(com\.matv\.speedtest)$"
        "center 1, match:initial_class ^(com\.matv\.speedtest)$"
        "size 800 400, match:initial_class ^(com\.matv\.speedtest)$"
        "dim_around 1, match:initial_class ^(com\.matv\.speedtest)$"

        # Btop TUI
        "float 1, match:initial_class ^(com\.matv\.btop)$"
        "center 1, match:initial_class ^(com\.matv\.btop)$"
        "size 1200 800, match:initial_class ^(com\.matv\.btop)$"
        "dim_around 1, match:initial_class ^(com\.matv\.btop)$"

        # Windscribe VPN
        "float 1, match:class ^(Windscribe)$"
        "opaque on, match:class ^(Windscribe)$"
        "no_blur on, match:class ^(Windscribe)$"
        "no_shadow on, match:class ^(Windscribe)$"

        # Spotify → hidden special workspace
        "workspace special:spotify silent, match:class (?i)^spotify$"
      ];
      env = [
        "XDG_SESSION_TYPE,wayland"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "NIXOS_OZONE_WL,1"
        "QT_QPA_PLATFORMTHEME,qtct"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
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
        "GTK_IM_MODULE,simple"
      ]
      ++ lib.optionals (hostName == "mantle") [
        "LIBVA_DRIVER_NAME,nvidia"
        "GBM_BACKEND,nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "NVD_BACKEND,direct"
      ];
      cursor = {
        # vista: amdgpu hardware cursor renders invisible — use software cursor.
        no_hardware_cursors = hostName == "mantle" || hostName == "vista";
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
