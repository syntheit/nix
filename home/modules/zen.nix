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
    CSS_FILE="${pkgs.writeText "userChrome.css" userChromeCss}"

    # Linux keeps profiles in ~/.zen, macOS in ~/Library/Application Support/zen/Profiles
    for ZEN_DIR in "$HOME/.zen" "$HOME/Library/Application Support/zen/Profiles"; do
      [ -d "$ZEN_DIR" ] || continue
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
user_pref("full-screen-api.macos-native-full-screen", false);
EOF
          else
            if grep -q "network.trr.mode" "$USER_JS"; then
              ${pkgs.gnused}/bin/sed -i 's/^user_pref("network.trr.mode".*$/user_pref("network.trr.mode", 5);/' "$USER_JS"
            else
              echo 'user_pref("network.trr.mode", 5);' >> "$USER_JS"
            fi
            if ! grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$USER_JS"; then
              echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$USER_JS"
            fi
            # macOS: fullscreen in place, not as a new Space at the end of the
            # desktop list (Firefox 124 made native the default).
            if ! grep -q "full-screen-api.macos-native-full-screen" "$USER_JS"; then
              echo 'user_pref("full-screen-api.macos-native-full-screen", false);' >> "$USER_JS"
            fi
          fi

          # Disk-write reduction (mantle: Zen wrote ~55 GB/day). Set or replace.
          set_pref() {
            if grep -q "^user_pref(\"$1\"" "$USER_JS"; then
              ${pkgs.gnused}/bin/sed -i "s|^user_pref(\"$1\".*$|user_pref(\"$1\", $2);|" "$USER_JS"
            else
              echo "user_pref(\"$1\", $2);" >> "$USER_JS"
            fi
          }
          # Session restore: save every 5 min instead of 15 s (the 3 MB
          # recovery file plus its backup copy was ~1/3 of Zen's writes). A
          # crash can lose up to 5 minutes of tab changes.
          set_pref browser.sessionstore.interval 300000
          # HTTP cache in RAM only (512 MB): no disk cache churn; the cache
          # starts empty after each restart.
          set_pref browser.cache.disk.enable false
          set_pref browser.cache.memory.enable true
          set_pref browser.cache.memory.capacity 524288

          echo "Updated Zen Browser config in $profile"
        fi
      done
    done
  '';
}
