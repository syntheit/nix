{ pkgs, lib, config, inputs, ... }:

let
  # The CSS content to apply the font
  userChromeCss = ''
    /* Set UI font to 0xProto Nerd Font */
    * {
      font-family: "0xProto Nerd Font" !important;
    }

    /* Reduce letter spacing in URL bar dropdown menu (Ctrl+T menu) */
    .urlbarView-row,
    .urlbarView-row-inner,
    .urlbarView-row-inner-box {
      letter-spacing: -0.02em !important;
    }

    /* Also apply to the title and URL text in dropdown items */
    .urlbarView-row-title,
    .urlbarView-row-url {
      letter-spacing: -0.02em !important;
    }

    /* Reduce letter spacing in new tab page quick access menu */
    @-moz-document url(about:newtab), url(about:home) {
      .top-site-outer,
      .top-site-button,
      .top-site-title {
        letter-spacing: -0.02em !important;
      }
    }
  '';
in
{
  # Activation script to find the profile and write the file
  home.activation.installZenUserChrome = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ZEN_DIR="$HOME/.zen"
    CSS_FILE="${pkgs.writeText "userChrome.css" userChromeCss}"

    if [ -d "$ZEN_DIR" ]; then
      for profile in "$ZEN_DIR"/*; do
        if [ -d "$profile" ] && [ -f "$profile/prefs.js" ]; then
          profile_name=$(basename "$profile")

          # Skip app-mode profiles (managed by their own modules)
          echo "$profile_name" | grep -q "\.Spotify$" && continue

          mkdir -p "$profile/chrome"
          ln -sf "$CSS_FILE" "$profile/chrome/userChrome.css"

          # Ensure toolkit.legacyUserProfileCustomizations.stylesheets is true in user.js
          USER_JS="$profile/user.js"
          if [ ! -f "$USER_JS" ]; then
            echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' > "$USER_JS"
          else
            if ! grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$USER_JS"; then
              echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$USER_JS"
            fi
          fi

          echo "Updated Zen Browser config in $profile"
        fi
      done
    fi
  '';
}
