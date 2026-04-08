{ pkgs, lib, ... }:

let
  ublock = pkgs.nur.repos.rycee.firefox-addons.ublock-origin;

  chromeCss = ''
    /* Hide all browser chrome for app-mode experience */
    #navigator-toolbox,
    #nav-bar,
    #PersonalToolbar,
    #TabsToolbar,
    #titlebar,
    .browser-toolbar,
    #sidebar-header,
    #sidebar-box,
    .titlebar-buttonbox-container,
    #zen-sidebar-web-panel,
    #zen-sidebar-web-panel-wrapper,
    #zen-sidebar-top-buttons,
    #zen-sidebar-icons-wrapper,
    #zen-sidebar-splitter {
      display: none !important;
    }
    #main-window {
      background: #000 !important;
    }
  '';

  contentCss = ''
    @-moz-document domain(open.spotify.com) {
      a[href="/download"] {
        display: none !important;
      }
    }
  '';

  prefs = ''
    // Disable password/form saving
    user_pref("signon.rememberSignons", false);
    user_pref("signon.autofillForms", false);
    user_pref("signon.formlessCapture.enabled", false);
    user_pref("extensions.formautofill.addresses.enabled", false);
    user_pref("extensions.formautofill.creditCards.enabled", false);

    // Disable history
    user_pref("places.history.enabled", false);
    user_pref("browser.formfill.enable", false);
    user_pref("browser.search.suggest.enabled", false);
    user_pref("browser.urlbar.suggest.history", false);
    user_pref("browser.urlbar.suggest.bookmark", false);
    user_pref("browser.urlbar.suggest.openpage", false);
    user_pref("browser.urlbar.suggest.topsites", false);

    // Disable telemetry
    user_pref("datareporting.healthreport.uploadEnabled", false);
    user_pref("datareporting.policy.dataSubmissionEnabled", false);
    user_pref("toolkit.telemetry.enabled", false);
    user_pref("toolkit.telemetry.unified", false);
    user_pref("app.shield.optoutstudies.enabled", false);
    user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
    user_pref("breakpad.reportURL", "");

    // Disable unnecessary features
    user_pref("extensions.pocket.enabled", false);
    user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
    user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
    user_pref("browser.translations.automaticallyPopup", false);
    user_pref("layout.spellcheckDefault", 0);

    // Enable MPRIS (media keys + waybar integration)
    user_pref("media.hardwaremediakeys.enabled", true);

    // Auto-enable uBlock Origin (skip first-run page)
    user_pref("extensions.autoDisableScopes", 0);

    // Remove window padding/borders
    user_pref("zen.theme.content-element-separation", 0);

    // Enable custom stylesheets
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
  '';
in
{
  # Desktop entry for launching Spotify via Zen
  home.file.".local/share/applications/spotify-zen.desktop".text = ''
    [Desktop Entry]
    Name=Spotify Zen
    Exec=zen --no-remote -P Spotify https://open.spotify.com
    Icon=spotify
    Type=Application
    Categories=Audio;Music;
  '';

  # Configure the Spotify Zen profile
  home.activation.installSpotifyZenProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PROFILE_DIR="$HOME/.zen"
    SPOTIFY_PROFILE=""

    # Find the Spotify profile directory
    if [ -d "$PROFILE_DIR" ]; then
      for dir in "$PROFILE_DIR"/*; do
        if echo "$(basename "$dir")" | grep -q "\.Spotify$"; then
          SPOTIFY_PROFILE="$dir"
          break
        fi
      done
    fi

    if [ -n "$SPOTIFY_PROFILE" ]; then
      mkdir -p "$SPOTIFY_PROFILE/chrome"
      mkdir -p "$SPOTIFY_PROFILE/extensions"

      ln -sf "${pkgs.writeText "userChrome.css" chromeCss}" "$SPOTIFY_PROFILE/chrome/userChrome.css"
      ln -sf "${pkgs.writeText "userContent.css" contentCss}" "$SPOTIFY_PROFILE/chrome/userContent.css"
      ln -sf "${pkgs.writeText "user.js" prefs}" "$SPOTIFY_PROFILE/user.js"
      ln -sf "${ublock}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${ublock.addonId}.xpi" "$SPOTIFY_PROFILE/extensions/${ublock.addonId}.xpi"

      # Force zen.theme.content-element-separation into prefs.js (user.js gets overridden by Zen)
      if [ -f "$SPOTIFY_PROFILE/prefs.js" ]; then
        ${pkgs.gnused}/bin/sed -i '/zen\.theme\.content-element-separation/d' "$SPOTIFY_PROFILE/prefs.js"
        echo 'user_pref("zen.theme.content-element-separation", 0);' >> "$SPOTIFY_PROFILE/prefs.js"
      fi

      echo "Configured Spotify Zen profile"
    fi
  '';
}
