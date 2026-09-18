{ config, lib, pkgs, ... }:

let
  inherit (config.lib.stylix.colors) base00 base01 base03 base05 base0A base0D;
in
{
  xdg.configFile."copyq/themes/tokyodark.ini".text = ''
    [Theme]
    alt_bg=#${base01}
    alt_item_css=
    bg=#${base00}
    css=
    css_template_items=items
    css_template_main_window=main_window
    css_template_menu=menu
    css_template_notification=notification
    cur_item_css="\n    ;border: 0.1em solid ''${sel_bg}"
    edit_bg=#${base01}
    edit_fg=#${base05}
    edit_font=
    fg=#${base05}
    find_bg=#${base0A}
    find_fg=#${base00}
    find_font=
    font=
    font_antialiasing=true
    hover_item_css=
    icon_size=16
    item_css=
    item_spacing=
    menu_bar_css="\n    ;background: ''${bg}\n    ;color: ''${fg}"
    menu_bar_disabled_css="\n    ;color: ''${bg - #666}"
    menu_bar_selected_css="\n    ;background: ''${sel_bg}\n    ;color: ''${sel_fg}"
    menu_css="\n    ;border: 1px solid ''${sel_bg}\n    ;background: ''${bg}\n    ;color: ''${fg}"
    notes_bg=#${base01}
    notes_css=
    notes_fg=#${base05}
    notes_font=
    notification_bg=#${base01}
    notification_fg=#${base05}
    notification_font=
    num_fg=#${base03}
    num_font=
    num_margin=2
    num_sel_fg=
    search_bar="\n    ;background: ''${edit_bg}\n    ;color: ''${edit_fg}\n    ;border: 1px solid ''${alt_bg}\n    ;margin: 2px"
    search_bar_focused="\n    ;border: 1px solid ''${sel_bg}"
    sel_bg=#${base0D}
    sel_fg=#${base00}
    sel_item_css=
    show_number=true
    show_scrollbars=true
    style_main_window=true
    tab_bar_css="\n    ;background: ''${bg - #222}"
    tab_bar_item_counter="\n    ;color: ''${fg - #044 + #400}\n    ;font-size: 6pt"
    tab_bar_scroll_buttons_css="\n    ;background: ''${bg - #222}\n    ;color: ''${fg}\n    ;border: 0"
    tab_bar_sel_item_counter="\n    ;color: ''${sel_bg - #044 + #400}"
    tab_bar_tab_selected_css="\n    ;padding: 0.5em\n    ;background: ''${bg}\n    ;border: 0.05em solid ''${bg}\n    ;color: ''${fg}"
    tab_bar_tab_unselected_css="\n    ;border: 0.05em solid ''${bg}\n    ;padding: 0.5em\n    ;background: ''${bg - #222}\n    ;color: ''${fg - #333}"
    tab_tree_css="\n    ;color: ''${fg}\n    ;background-color: ''${bg}"
    tab_tree_item_counter="\n    ;color: ''${fg - #044 + #400}\n    ;font-size: 6pt"
    tab_tree_sel_item_counter="\n    ;color: ''${sel_fg - #044 + #400}"
    tab_tree_sel_item_css="\n    ;color: ''${sel_fg}\n    ;background-color: ''${sel_bg}\n    ;border-radius: 2px"
    tool_bar_css="\n    ;color: ''${fg}\n    ;background-color: ''${bg}\n    ;border: 0"
    tool_button_css="\n    ;color: ''${fg}\n    ;background: ''${bg}\n    ;border: 0\n    ;border-radius: 2px"
    tool_button_pressed_css="\n    ;background: ''${sel_bg}"
    tool_button_selected_css="\n    ;background: ''${sel_bg - #222}\n    ;color: ''${sel_fg}\n    ;border: 1px solid ''${sel_bg}"
    use_system_icons=false
  '';

  # CopyQ has no stylix target, so the theme above has to be applied by hand.
  # The obvious way to do that -- `copyq loadTheme <path>` sent to a running
  # `copyq --start-server` via Hyprland's exec-once -- does not work. Verified
  # empirically (live system, 2026-08-08): running `copyq loadTheme
  # ~/.config/copyq/themes/tokyodark.ini` against the live server returns
  # success (exit 0) but never updates the [Theme] section of
  # ~/.config/copyq/copyq.conf -- it stays on the default/light values
  # (bg=default_bg, fg=default_text, style_main_window=false) no matter how
  # long you wait or whether `copyq hide` follows it, and the visible window
  # stays undyed (confirmed by the user, who saw a white window). This isn't
  # the "sleep 1" race condition it looks like -- calling loadTheme by hand,
  # seconds after the server has been up, behaves identically. CopyQ's own
  # MainWindow::loadTheme() is supposed to persist via a fresh QSettings
  # write, but in practice on this build/version it doesn't stick.
  #
  # CopyQ *does* read the [Theme] section of copyq.conf reliably at server
  # startup, and doesn't otherwise touch that section during normal use,
  # so instead of fighting the runtime RPC, splice the theme directly into
  # copyq.conf before the server ever starts.
  home.activation.copyqTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    THEME_SRC="$HOME/.config/copyq/themes/tokyodark.ini"
    COPYQ_CONF="$HOME/.config/copyq/copyq.conf"

    if [ -f "$THEME_SRC" ]; then
      mkdir -p "$(dirname "$COPYQ_CONF")"
      if [ -f "$COPYQ_CONF" ]; then
        ${pkgs.gawk}/bin/awk -v themefile="$THEME_SRC" '
          BEGIN {
            while ((getline line < themefile) > 0) theme = theme line "\n"
          }
          /^\[Theme\]/ {
            printf "%s", theme
            found = 1
            skipping = 1
            next
          }
          /^\[/ && skipping { skipping = 0 }
          skipping { next }
          { print }
          END {
            if (!found) printf "%s", theme
          }
        ' "$COPYQ_CONF" > "$COPYQ_CONF.new" && mv "$COPYQ_CONF.new" "$COPYQ_CONF"
      else
        cp "$THEME_SRC" "$COPYQ_CONF"
      fi
    fi
  '';
}
