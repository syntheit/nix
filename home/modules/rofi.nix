{ pkgs, config, lib, ... }:

{
  home.file.".local/share/applications/lock.desktop".text = ''
    [Desktop Entry]
    Name=Lock
    Exec=${pkgs.hyprlock}/bin/hyprlock
    Icon=system-lock-screen
    Type=Application
    Categories=System;
  '';
  home.file.".local/share/applications/suspend.desktop".text = ''
    [Desktop Entry]
    Name=Suspend
    Exec=systemctl suspend
    Icon=system-suspend
    Type=Application
    Categories=System;
  '';
  home.file.".local/share/applications/reboot.desktop".text = ''
    [Desktop Entry]
    Name=Reboot
    Exec=systemctl reboot
    Icon=system-reboot
    Type=Application
    Categories=System;
  '';
  home.file.".local/share/applications/shutdown.desktop".text = ''
    [Desktop Entry]
    Name=Shutdown
    Exec=systemctl poweroff
    Icon=system-shutdown
    Type=Application
    Categories=System;
  '';

  programs.rofi = {
    enable = true;
    cycle = true;
    plugins = [
      pkgs.rofi-calc
      pkgs.rofi-emoji
      pkgs.rofi-systemd
    ];
    xoffset = 0;
    yoffset = -150;
    extraConfig = {
      show-icons = true;
      kb-cancel = "Escape";
      modi = "window,run,ssh,emoji,calc";
      sort = true;
      drun-display-format = "{name}";
      prompt = "";
    };
    theme =
      let
        inherit (config.lib.formats.rasi) mkLiteral;
        inherit (config.lib.stylix.colors) base00 base01 base02 base03 base04 base05 base07 base0D;
      in
      {
        "*" = {
          bg0 = mkLiteral "#${base00}F2";  # base00 with opacity
          bg1 = mkLiteral "#${base01}";    # Lighter background
          bg2 = mkLiteral "#${base02}80";  # Selection background with opacity
          bg3 = mkLiteral "#${base0D}F2";  # Accent color (functions/methods) with opacity
          bg4 = mkLiteral "#${base00}";    # Darkest selection background
          fg0 = mkLiteral "#${base05}";    # Default foreground
          fg1 = mkLiteral "#${base07}";    # Lightest foreground
          fg2 = mkLiteral "#${base04}";    # Darker foreground
          fg3 = mkLiteral "#${base03}";    # Darkest foreground
          fg4 = mkLiteral "#${base0D}";    # Accent color for selected text (no opacity)
          font = "JetBrains Mono Nerd Font 12";
          background-color = lib.mkForce (mkLiteral "transparent");
          text-color = lib.mkForce (mkLiteral "@fg0");
          margin = mkLiteral "0px";
          padding = mkLiteral "0px";
          spacing = mkLiteral "0px";
        };

        "window" = {
          location = mkLiteral "center";
          width = 864;
          height = 432;
          border-radius = mkLiteral "0px";
          background-color = lib.mkForce (mkLiteral "@bg0");
        };

        "mainbox" = {
          padding = mkLiteral "12px";
        };

        "inputbar" = {
          background-color = lib.mkForce (mkLiteral "@bg1");
          border-color = lib.mkForce (mkLiteral "@bg3");
          border = mkLiteral "2px";
          border-radius = mkLiteral "0px";
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "8px";
          children = map mkLiteral [
            "entry"
          ];
        };

        "prompt" = {
          text-color = lib.mkForce (mkLiteral "@fg2");
        };

        "entry" = {
          placeholder = "Search";
          placeholder-color = lib.mkForce (mkLiteral "@fg3");
        };

        "message" = {
          margin = mkLiteral "12px 0 0";
          border-radius = mkLiteral "0px";
          border-color = lib.mkForce (mkLiteral "@bg2");
          background-color = lib.mkForce (mkLiteral "@bg2");
        };

        "textbox" = {
          padding = mkLiteral "8px 24px";
        };

        "listview" = {
          background-color = lib.mkForce (mkLiteral "transparent");
          margin = mkLiteral "12px 0 0";
          lines = 8;
          columns = 1;
          fixed-height = false;
        };

        "element" = {
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "8px";
          border-radius = mkLiteral "0px";
        };

        "element normal active" = {
          text-color = lib.mkForce (mkLiteral "@bg3");
        };

        "element selected normal, element selected active" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element-icon" = {
          size = mkLiteral "1em";
          vertical-align = mkLiteral "0.5";
        };

        "element-text" = {
          text-color = lib.mkForce (mkLiteral "inherit");
        };


        "element selected.urgent" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element-text selected" = {
          text-color = lib.mkForce (mkLiteral "#FFFFFF");
        };

        "element-icon selected" = {
          text-color = lib.mkForce (mkLiteral "#FFFFFF");
        };

        "element selected" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element alternate.normal" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element alternate.active" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element alternate.urgent" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element alternate.selected.normal" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element alternate.selected.active" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };

        "element alternate.selected.urgent" = {
          background-color = lib.mkForce (mkLiteral "transparent");
        };
      };
  };
}
