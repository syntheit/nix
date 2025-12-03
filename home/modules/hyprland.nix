{ pkgs, inputs, ... }:

{
  # Hyprland configuration
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    xwayland.enable = true;
    systemd.enable = true;
    systemd.enableXdgAutostart = true;

    settings = {
      general = {
        no_border_on_floating = true;
        gaps_in = 0;
        gaps_out = 0;
        border_size = 0;
        "col.active_border" = "rgba(00000000)";
        "col.inactive_border" = "rgba(00000000)";
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
      bind = [
        "$mod, R, exec, rofi -modes drun -show drun"
        "$mod, Space, togglefloating"
        "$mod, T, exec, kitty"
        "$mod, B, exec, zen"
        "$mod, E, exec, nemo"
        "$mod, C, exec, ${pkgs.copyq}/bin/copyq toggle"
        "$mod SHIFT, L, exec, hyprlock"
        "$mod, Q, killactive"
        "$mod, F, fullscreen"
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r"
        "$mod, j, movefocus, d"
        "$mod, k, movefocus, u"
        # Screenshot keybindings  
        "$mod SHIFT, S, exec, grimblast copy area"
        "$mod SHIFT, A, exec, grimblast --cursor copy screen"
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
        "hyprpaper"
        "nm-applet"
        "blueman-applet"
        "${pkgs.copyq}/bin/copyq --start-server"
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
      # Use nwg-displays to configure monitor settings
      # Will automatically reload from this file
      source = "~/.config/hypr/monitors.conf";
      windowrule = [
        "float,^(Rofi)$"
      ];
      # ### FLOATING WINDOW RULES ###
      windowrulev2 = [
        # Clipboard manager (CopyQ)
        "float,class:^(com.github.hluk.copyq)$"
        "center,class:^(com.github.hluk.copyq)$"
        "size 689 911,class:^(com.github.hluk.copyq)$"
        "dimaround,class:^(com.github.hluk.copyq)$"
        # Bluetooth manager (Blueman)
        "float,class:^(\\.blueman-manager-wrapped)$"
        "center,class:^(\\.blueman-manager-wrapped)$"
        "size 800 600,class:^(\\.blueman-manager-wrapped)$"
        "dimaround,class:^(\\.blueman-manager-wrapped)$"
        # Network manager (NetworkManager Connection Editor)
        "float,class:^(nm-connection-editor)$"
        "center,class:^(nm-connection-editor)$"
        "size 800 600,class:^(nm-connection-editor)$"
        "dimaround,class:^(nm-connection-editor)$"
        # Volume control (PulseAudio Volume Control)
        "float,class:^(org.pulseaudio.pavucontrol)$"
        "center,class:^(org.pulseaudio.pavucontrol)$"
        "size 800 600,class:^(org.pulseaudio.pavucontrol)$"
        "dimaround,class:^(org.pulseaudio.pavucontrol)$"
      ];
      env = [
        "LIBVA_DRIVER_NAME,nvidia"
        "XDG_SESSION_TYPE,wayland"
        "GBM_BACKEND,nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "NVD_BACKEND,direct"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "NIXOS_OZONE_WL,1"
      ];
      cursor = {
        no_hardware_cursors = true;
        warp_on_change_workspace = false;
        no_warps = true;
      };
    };
  };
}
