{ pkgs, config, ... }:

{
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
      kb-cancel = "Escape,Super+space";
      modi = "window,run,ssh,emoji,calc,systemd";
      sort = true;
      drun-display-format = "{name}";
      prompt = "";
    };
    theme =
      let
        inherit (config.lib.formats.rasi) mkLiteral;
      in
      {
        "*" = {
          bg0 = mkLiteral "#212121F2";
          bg1 = mkLiteral "#2A2A2A";
          bg2 = mkLiteral "#3D3D3D80";
          bg3 = mkLiteral "#1A73E8F2";
          fg0 = mkLiteral "#E6E6E6";
          fg1 = mkLiteral "#FFFFFF";
          fg2 = mkLiteral "#969696";
          fg3 = mkLiteral "#3D3D3D";
          font = "JetBrains Mono Nerd Font 12";
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@fg0";
          margin = mkLiteral "0px";
          padding = mkLiteral "0px";
          spacing = mkLiteral "0px";
        };

        "window" = {
          location = mkLiteral "center";
          width = 864;
          height = 432;
          border-radius = mkLiteral "0px";
          background-color = mkLiteral "@bg0";
        };

        "mainbox" = {
          padding = mkLiteral "12px";
        };

        "inputbar" = {
          background-color = mkLiteral "@bg1";
          border-color = mkLiteral "@bg3";
          border = mkLiteral "2px";
          border-radius = mkLiteral "0px";
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "8px";
          children = map mkLiteral [
            "entry"
          ];
        };

        "prompt" = {
          text-color = mkLiteral "@fg2";
        };

        "entry" = {
          placeholder = "Search";
          placeholder-color = mkLiteral "@fg3";
        };

        "message" = {
          margin = mkLiteral "12px 0 0";
          border-radius = mkLiteral "0px";
          border-color = mkLiteral "@bg2";
          background-color = mkLiteral "@bg2";
        };

        "textbox" = {
          padding = mkLiteral "8px 24px";
        };

        "listview" = {
          background-color = mkLiteral "transparent";
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
          text-color = mkLiteral "@bg3";
        };

        "element selected normal, element selected active" = {
          background-color = mkLiteral "@bg3";
        };

        "element-icon" = {
          size = mkLiteral "1em";
          vertical-align = mkLiteral "0.5";
        };

        "element-text" = {
          text-color = mkLiteral "inherit";
        };


        "element selected.urgent" = {
          background-color = mkLiteral "@bg3";
        };

        "element-text selected" = {
          text-color = mkLiteral "@fg1";
        };

        "element-icon selected" = {
          text-color = mkLiteral "@fg1";
        };

        "element selected" = {
          background-color = mkLiteral "@bg3";
        };

        "element alternate.normal" = {
          background-color = mkLiteral "transparent";
        };

        "element alternate.active" = {
          background-color = mkLiteral "transparent";
        };

        "element alternate.urgent" = {
          background-color = mkLiteral "transparent";
        };

        "element alternate.selected.normal" = {
          background-color = mkLiteral "@bg3";
        };

        "element alternate.selected.active" = {
          background-color = mkLiteral "@bg3";
        };

        "element alternate.selected.urgent" = {
          background-color = mkLiteral "@bg3";
        };
      };
  };
}
