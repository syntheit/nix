{
  pkgs,
  lib,
  config,
  ...
}:

{
  home.activation.checkAppTitleBars = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "Checking App Aesthetics..."

    # VSCode Family Checks
    # We want: "window.titleBarStyle": "custom", "window.customTitleBarVisibility": "auto"
    APPS=(
      "$HOME/Library/Application Support/Code/User/settings.json"
      "$HOME/Library/Application Support/Cursor/User/settings.json"
      "$HOME/Library/Application Support/Antigravity/User/settings.json"
    )

    for SETTINGS_FILE in "''${APPS[@]}"; do
      if [ -f "$SETTINGS_FILE" ]; then
        if ! grep -q "window.titleBarStyle" "$SETTINGS_FILE"; then
          echo -e "\033[1;33m[WARN]\033[0m Title bar tweaks likely missing in: $SETTINGS_FILE"
          echo "       Please ensure settings.json contains:"
          echo "       \"window.titleBarStyle\": \"custom\","
          echo "       \"window.customTitleBarVisibility\": \"auto\""
        fi
      fi
    done

    # Zen Browser Reminder
    echo -e "\033[1;34m[INFO]\033[0m Zen Browser: Remember to Uncheck 'Title Bar' in View > Toolbars or Customize Toolbar for a borderless look."
  '';
}
