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
      if echo "$class" | grep -qEi "^(tui-network|tui-bluetooth|tui-speedtest|tui-btop|com.github.hluk.copyq)$"; then
        $hyprctl dispatch killactive
      fi
    fi
  '';
in
{
  # Hyprland configuration
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

      "$mod" = "SUPER";

      # Non-consuming bind for Escape (allows key to pass to apps like Vim)
      bindn = [
        ", escape, exec, ${handleEscapeScript}"
      ];

      bind = [
        "$mod, R, exec, rofi -show drun"
        "$mod, Space, exec, pkill -SIGUSR1 waybar"
        "CTRL $mod, Space, togglefloating"
        "$mod, T, exec, kitty"
        "$mod, B, exec, zen"
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
        # Screenshot keybindings (area goes through satty for annotation)
        "$mod SHIFT, S, exec, grimblast --freeze save area /tmp/screenshot-annotate.png && ${pkgs.satty}/bin/satty -f /tmp/screenshot-annotate.png"
        "$mod SHIFT, A, exec, grimblast --freeze copy screen"
        # Active window screenshots
        "$mod SHIFT, W, exec, grimblast copysave active"
        "$mod, W, exec, grimblast copy active"
        # Current monitor/output screenshots
        "$mod SHIFT, O, exec, grimblast copysave output"
        "$mod, O, exec, grimblast copy output"
        # Screen recording toggle
        "$mod SHIFT, R, exec, ${toggleRecording}"
        # Color picker (copies hex to clipboard)
        "$mod, P, exec, ${pkgs.hyprpicker}/bin/hyprpicker -a"
        # Picture-in-picture toggle
        "$mod SHIFT, P, exec, ${togglePip}"
        "$mod, V, exec, ${pkgs.copyq}/bin/copyq toggle"
        "$mod SHIFT, V, exec, ${pkgs.copyq}/bin/copyq menu"
        "$mod, S, togglespecialworkspace, spotify"
        # Relative workspace movement
        "$mod, period, workspace, +1"
        "$mod, comma, workspace, -1"
        "$mod SHIFT, period, movetoworkspace, +1"
        "$mod SHIFT, comma, movetoworkspace, -1"
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
      ++ lib.optionals (hostName == "ionian") [
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
      ++ lib.optionals (hostName == "ionian") [
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
        # Start waybar hidden (toggle with Super+Space)
        "${pkgs.bash}/bin/bash -c 'sleep 2 && pkill -SIGUSR1 waybar'"
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

        # Spotify → hidden special workspace (toggled with Super+S)
        "workspace special:spotify silent, match:class (?i)^spotify$"
      ];
      env = [
        "XDG_SESSION_TYPE,wayland"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "NIXOS_OZONE_WL,1"
        "QT_QPA_PLATFORMTHEME,qtct"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
      ]
      ++ lib.optionals (hostName == "caspian") [
        "LIBVA_DRIVER_NAME,nvidia"
        "GBM_BACKEND,nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "NVD_BACKEND,direct"
      ];
      cursor = {
        no_hardware_cursors = hostName == "caspian";
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
