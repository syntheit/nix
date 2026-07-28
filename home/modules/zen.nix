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

          # DNS is handled at the resolver layer (system/default.nix), not
          # per-app: systemd-resolved sends public queries to NextDNS over DoT
          # (encrypted), while Tailscale's split-DNS routes tailnet names to
          # 100.100.100.100 (MagicDNS). So the browser just needs to use the
          # system resolver and it gets both. trr.mode=5 turns Zen's own DoH off
          # (and blocks the DoH rollout re-enabling it) -- that's what lets
          # tailnet names like harbor:4321 resolve. Encryption isn't lost; it's
          # at the systemd-resolved -> NextDNS hop.
          USER_JS="$profile/user.js"
          if [ ! -f "$USER_JS" ]; then
            cat > "$USER_JS" <<'EOF'
user_pref("network.trr.mode", 5);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
EOF
          else
            if grep -q "network.trr.mode" "$USER_JS"; then
              sed -i 's/^user_pref("network.trr.mode".*$/user_pref("network.trr.mode", 5);/' "$USER_JS"
            else
              echo 'user_pref("network.trr.mode", 5);' >> "$USER_JS"
            fi
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
