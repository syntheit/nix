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
      if echo "$class" | grep -qEi "^(tui-network|tui-bluetooth|tui-speedtest|com.github.hluk.copyq)$"; then
        $hyprctl dispatch killactive
      fi
    fi
  '';
in
{
  # Hyprland configuration
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    xwayland.enable = true;
    # Disable systemd integration when using greetd to launch Hyprland directly
    # This prevents the "Hyprland was started without start-hyprland" warning
    systemd.enable = false;

    settings = {
      general = {
        gaps_in = 0;
        gaps_out = 0;
        # FORCE: Override Stylix's default border size (2) to keep borders invisible
        border_size = lib.mkForce 0;
        # col.active_border and col.inactive_border are managed by Stylix
      };

      dwindle = {
        # no_gaps_when_only = 2;
      };
      debug = {
        #damage_tracking = 0;
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
        "$mod, Space, togglefloating"
        "$mod, T, exec, kitty"
        "$mod, B, exec, zen"
        "$mod, E, exec, nautilus"
        "$mod, C, exec, ${pkgs.copyq}/bin/copyq toggle"
        "$mod SHIFT, L, exec, hyprlock"
        "$mod, Q, killactive"
        "$mod, F, fullscreen"
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r"
        "$mod, j, movefocus, d"
        "$mod, k, movefocus, u"
        # Screenshot keybindings
        "$mod SHIFT, S, exec, grimblast --freeze copy area"
        "$mod SHIFT, A, exec, grimblast --freeze copy screen"
        # Active window screenshots
        "$mod SHIFT, W, exec, grimblast copysave active"
        "$mod, W, exec, grimblast copy active"
        # Current monitor/output screenshots
        "$mod SHIFT, O, exec, grimblast copysave output"
        "$mod, O, exec, grimblast copy output"
        "$mod, V, exec, ${pkgs.copyq}/bin/copyq toggle"
        "$mod SHIFT, V, exec, ${pkgs.copyq}/bin/copyq menu"
        "$mod, mouse:272, setfloating"
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
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      exec-once = [
        "${pkgs.copyq}/bin/copyq --start-server"
        "systemctl --user start hyprpolkitagent"
        "hyprsunset"
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
      windowrulev2 = [
        "float, class:^(Rofi)$"

        # CopyQ
        "float, initialClass:^(com.github.hluk.copyq)$"
        "center, initialClass:^(com.github.hluk.copyq)$"
        "size 689 911, initialClass:^(com.github.hluk.copyq)$"
        "dimaround, initialClass:^(com.github.hluk.copyq)$"

        # Network Manager
        "float, initialClass:^(nm-connection-editor)$"
        "center, initialClass:^(nm-connection-editor)$"
        "size 800 600, initialClass:^(nm-connection-editor)$"
        "dimaround, initialClass:^(nm-connection-editor)$"

        # PulseAudio Volume Control
        "float, initialClass:^(org.pulseaudio.pavucontrol)$"
        "center, initialClass:^(org.pulseaudio.pavucontrol)$"
        "size 800 600, initialClass:^(org.pulseaudio.pavucontrol)$"
        "dimaround, initialClass:^(org.pulseaudio.pavucontrol)$"

        # Network Manager TUI
        "float, initialClass:^(tui-network)$"
        "center, initialClass:^(tui-network)$"
        "size 600 900, initialClass:^(tui-network)$"
        "dimaround, initialClass:^(tui-network)$"

        # Bluetooth TUI
        "float, initialClass:^(tui-bluetooth)$"
        "center, initialClass:^(tui-bluetooth)$"
        "size 1104 580, initialClass:^(tui-bluetooth)$"
        "dimaround, initialClass:^(tui-bluetooth)$"

        # Speedtest TUI
        "float, initialClass:^(tui-speedtest)$"
        "center, initialClass:^(tui-speedtest)$"
        "size 800 400, initialClass:^(tui-speedtest)$"
        "dimaround, initialClass:^(tui-speedtest)$"
      ];
      env = [
        "LIBVA_DRIVER_NAME,nvidia"
        "XDG_SESSION_TYPE,wayland"
        "GBM_BACKEND,nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "NVD_BACKEND,direct"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "NIXOS_OZONE_WL,1"
        "QT_QPA_PLATFORMTHEME,qtct"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
      ];
      cursor = {
        no_hardware_cursors = true;
        warp_on_change_workspace = false;
        no_warps = true;
      };
    };
  };

  # Hyprsunset configuration
  # Blue light filter that turns on from 9:30pm to 5am
  xdg.configFile."hypr/hyprsunset.conf".text = ''
    max-gamma = 150

    # Normal mode (daytime) - turns off blue light filter at 5am
    profile {
        time = 5:00
        identity = true
    }

    # Night mode - turns on blue light filter at 9:30pm
    profile {
        time = 21:30
        temperature = 5500
    }
  '';
}
