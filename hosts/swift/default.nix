{
  pkgs,
  lib,
  vars,
  ...
}:

{
  nixpkgs.config.allowUnfree = true;

  system.primaryUser = vars.user.name;

  # Nix daemon managed by Determinate Systems installer
  nix.enable = false;

  nix-homebrew = {
    enable = true;
    user = vars.user.name;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    casks = [
      "affinity"
      "antigravity"
      "arc"
      "claude"

      "cursor"
      "dbeaver-community"
      "blackhole-2ch"
      "font-jetbrains-mono-nerd-font"
      "iina"
      "karabiner-elements"
      "kiro"
      "ghostty"
      "lulu"
      "marta"
      "macwhisper"
      "nextcloud"
      "notunes"
      "obsidian"
      "orbstack"
      "raycast"
      "seafile-client"
      "spotify"
      "syncthing-app"
      "tailscale-app"
      "telegram"
      "thunderbird"
      "transmission"
      "visual-studio-code"
      "whatsapp"
      "windscribe"
      "zen"
      "zed"
    ];
    brews = [
      "awscli-local"
      "mas"
      "ollama" # Kept in Homebrew for better macOS Metal/GPU integration
      "switchaudio-osx"
      "wifi-password"
      "yt-dlp"
    ];
  };

  system.defaults = {
    dock = {
      autohide = true;
      autohide-delay = 1000.0; # Effectively hide the dock permanently
      autohide-time-modifier = 0.0;
      static-only = true;
      show-recents = false;
      minimize-to-application = true;
      mineffect = "scale";
    };

    finder = {
      AppleShowAllFiles = true;
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # List view
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    NSGlobalDomain = {
      KeyRepeat = 2;
      InitialKeyRepeat = 10;
      ApplePressAndHoldEnabled = false;
      AppleInterfaceStyle = "Dark";
      AppleShowAllFiles = true;
      AppleShowAllExtensions = true;
      "com.apple.swipescrolldirection" = true;
    };

    loginwindow = {
      LoginwindowText = "Caspian/Ionian/Aegean";
      GuestEnabled = false;
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = false;
    };

    WindowManager = {
      EnableStandardClickToShowDesktop = false;
    };

    # Privacy & telemetry defaults
    CustomUserPreferences = {
      # Disable Mission Control three-finger swipe (overview app handles this gesture)
      "com.apple.AppleMultitouchTrackpad" = {
        TrackpadThreeFingerVertSwipeGesture = 0;
        TrackpadThreeFingerHorizSwipeGesture = 0;
        TrackpadFourFingerHorizSwipeGesture = 0;
      };
      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        TrackpadThreeFingerVertSwipeGesture = 0;
        TrackpadThreeFingerHorizSwipeGesture = 0;
        TrackpadFourFingerHorizSwipeGesture = 0;
      };
      # Disable personalized ads
      "com.apple.AdLib" = {
        allowApplePersonalizedAdvertising = false;
        allowIdentifierForAdvertising = false;
      };
      # Disable Siri
      "com.apple.assistant.support" = {
        "Assistant Enabled" = false;
      };
      "com.apple.Siri" = {
        StatusMenuVisible = false;
        UserHasDeclinedEnable = true;
        VoiceTriggerUserEnabled = false;
      };
      # Crash reporter — don't send to Apple
      "com.apple.CrashReporter" = {
        DialogType = "none";
      };
      # Disable Safari search suggestions (sends queries to Apple)
      "com.apple.Safari" = {
        UniversalSearchEnabled = false;
        SuppressSearchSuggestions = true;
        SendDoNotTrackHTTPHeader = true;
      };
      # Disable Siri/Spotlight suggestions
      "com.apple.lookup.shared" = {
        LookupSuggestionsDisabled = true;
      };
      # Disable Game Center
      "com.apple.gamed" = {
        Disabled = true;
      };
    };
  };

  # Firewall: block incoming, stealth mode (don't respond to probes)
  networking.applicationFirewall.enable = true;
  networking.applicationFirewall.enableStealthMode = true;

  networking.hostName = "swift";

  # SSH — Tailscale-only, key-only
  environment.etc."ssh/sshd_tailscale_config".text = ''
    Port 22
    ListenAddress 100.78.114.100
    AuthorizedKeysCommand /bin/cat /etc/ssh/nix_authorized_keys.d/%u
    AuthorizedKeysCommandUser _sshd
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    UsePAM no
    Subsystem sftp /usr/libexec/sftp-server
  '';


  launchd.daemons.sshd-tailscale = {
    serviceConfig = {
      Label = "org.nixos.sshd-tailscale";
      ProgramArguments = [ "/usr/sbin/sshd" "-D" "-f" "/etc/ssh/sshd_tailscale_config" ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  # Generic names for mDNS/Bonjour — hides real hostname from local network
  networking.computerName = "Mac";
  networking.localHostName = "Mac";

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = false;
    remapCapsLockToEscape = false;
  };

  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  services.yabai = {
    enable = true;
    package = pkgs.yabai;
    config = {
      layout = "bsp";
      window_gap = 0;
      top_padding = 1;
      bottom_padding = 0;
      left_padding = 0;
      right_padding = 0;
      window_shadow = "off";
      mouse_modifier = "fn";
      mouse_action1 = "move";
      mouse_action2 = "resize";
      mouse_drop_action = "swap";
      # Both off: with these on, the cursor sitting over a window in the
      # original space pulls focus back when programmatically switching to
      # an empty / less-active space (fn+N bounces back to current space).
      mouse_follows_focus = "off";
      focus_follows_mouse = "off";
      active_window_opacity = "1.0";
      normal_window_opacity = "1.0";
    };
    extraConfig = ''
      # Load scripting addition (requires sudoers entry below)
      sudo yabai --load-sa
      yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"

      # Notify overview daemon on space change (for composite cache)
      yabai -m signal --add event=space_changed action="pkill -SIGUSR2 -x overview"

      # Window rules
      yabai -m rule --add app="^System Preferences$" manage=off
      yabai -m rule --add app="^System Settings$" manage=off
      yabai -m rule --add app="^Calculator$" manage=off
      yabai -m rule --add app="^Raycast$" manage=off
      yabai -m rule --add app="^Archive Utility$" manage=off
      yabai -m rule --add app="^Finder$" title="(Copy|Move|Delete|Connect)" manage=off
      yabai -m rule --add title="^dashboard$" manage=off

      # Spotify → scratchpad (floating overlay, toggled with F4)
      yabai -m rule --add app="^Spotify$" scratchpad=spotify
    '';
  };

  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ./skhdrc;
  };

  environment.etc."sudoers.d/yabai".text = ''
    ${vars.user.name} ALL=(root) NOPASSWD: /run/current-system/sw/bin/yabai --load-sa
  '';

  environment.etc."sudoers.d/privacy".text = ''
    ${vars.user.name} ALL=(root) NOPASSWD: /usr/bin/killall VDCAssistant, /usr/bin/killall AppleCameraAssistant
  '';

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  users.users.${vars.user.name} = {
    name = vars.user.name;
    home = "/Users/${vars.user.name}";
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
  };

  system.activationScripts.postActivation.text = ''
    set_default() {
      sudo -u ${vars.user.name} defaults write "$@"
    }

    GUI_UID="$(id -u "${vars.user.name}")"

    # ================================================================
    # UI defaults (not animations — keep those)
    # ================================================================
    set_default NSGlobalDomain _HIHideMenuBar -bool true
    set_default NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false
    set_default NSGlobalDomain AppleReduceTransparency -bool true

    # Finder: quittable like a normal app, no desktop icons
    set_default com.apple.finder QuitMenuItem -bool true
    set_default com.apple.finder CreateDesktop -bool false

    # Don't write .DS_Store on network/USB volumes
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    # Don't reopen windows on login
    defaults write com.apple.loginwindow TALLogoutSavesState -bool false
    defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false

    # Disable Spotlight shortcut (Cmd+Space) — complex nested dict not supported declaratively
    set_default com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "{enabled = 0; value = { parameters = (32, 49, 1048576); type = 'standard'; }; }"

    killall Dock 2>/dev/null || true
    killall SystemUIServer 2>/dev/null || true
    killall Finder 2>/dev/null || true

    # ================================================================
    # Privacy & Telemetry defaults
    # ================================================================
    set_default com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2
    defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit -bool false 2>/dev/null || true
    defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" ThirdPartyDataSubmit -bool false 2>/dev/null || true
    defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool false

    # Disable software update auto-downloads
    defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false
    defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false
    defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -int 0
    defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -int 0
    defaults write /Library/Preferences/com.apple.SoftwareUpdate ScheduleFrequency -int 0
    defaults write com.apple.commerce AutoUpdate -bool false

    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

    # ================================================================
    # Power management: no powernap, no hibernation
    # ================================================================
    pmset -a powernap 0
    pmset -a hibernatemode 0
    pmset -a sms 0
    pmset -a lessbright 0
    rm -f /var/vm/sleepimage 2>/dev/null || true

    # ================================================================
    # TCC permissions (requires SIP disabled)
    # ================================================================
    YABAI_BIN=$(readlink -f ${pkgs.yabai}/bin/yabai)
    SKHD_BIN=$(readlink -f ${pkgs.skhd}/bin/skhd)
    OVERVIEW_BIN=$(readlink -f ${pkgs.overview}/bin/overview)
    BT_PANEL_BIN=$(readlink -f ${pkgs.bluetooth-panel}/bin/bluetooth-panel)
    WIFI_PANEL_BIN=$(readlink -f ${pkgs.wifi-panel}/bin/wifi-panel)
    EQ_BIN=$(readlink -f ${pkgs.eq}/bin/eq)
    MENUBAR_BLOCKER_BIN=$(readlink -f ${pkgs.menubar-blocker}/bin/menubar-blocker)
    TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
    for BIN in "$YABAI_BIN" "$SKHD_BIN" "$MENUBAR_BLOCKER_BIN"; do
      sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceAccessibility', '$BIN', 1, 2, 4, 1);"
    done
    # Screen capture permission for overview (window thumbnails via ScreenCaptureKit)
    sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceScreenCapture', '$OVERVIEW_BIN', 1, 2, 4, 1);"
    # Bluetooth permission for bluetooth-panel (IOBluetooth device management)
    sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceBluetoothAlways', '$BT_PANEL_BIN', 1, 2, 4, 1);"
    # Location permission for wifi-panel (CoreWLAN SSID access)
    sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceLocation', '$WIFI_PANEL_BIN', 1, 2, 4, 1);"
    # Microphone permission for eq daemon (AVAudioEngine reads from BlackHole input)
    sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceMicrophone', '$EQ_BIN', 1, 2, 4, 1);"

    # Force tccd to reload from TCC.db — direct sqlite writes don't invalidate
    # its in-memory cache, so yabai/skhd would otherwise launch without
    # effective accessibility until tccd is restarted.
    killall tccd 2>/dev/null || true

    # Restart nix-managed services after TCC grants
    launchctl bootout "gui/$GUI_UID/org.nixos.skhd" 2>/dev/null || true
    launchctl bootout "gui/$GUI_UID/org.nixos.yabai" 2>/dev/null || true
    sleep 1
    launchctl bootstrap "gui/$GUI_UID" /Users/${vars.user.name}/Library/LaunchAgents/org.nixos.skhd.plist 2>/dev/null || true
    launchctl bootstrap "gui/$GUI_UID" /Users/${vars.user.name}/Library/LaunchAgents/org.nixos.yabai.plist 2>/dev/null || true

    # ================================================================
    # SYSTEM DAEMONS TO DISABLE
    # ================================================================
    for daemon in \
      com.apple.adid \
      com.apple.AssetCache.builtin \
      com.apple.AssetCacheLocatorService \
      com.apple.AssetCacheTetheratorService \
      com.apple.AssetCacheManagerService \
      com.apple.AirPlayXPCHelper \
      com.apple.analyticsd \
      com.apple.assistantd \
      com.apple.parsecd \
      com.apple.tipsd \
      com.apple.cloudd \
      com.apple.icloud.findmydeviced \
      com.apple.icloud.searchpartyd \
      com.apple.findmymacd \
      com.apple.findmymacmessenger \
      com.apple.findmy.findmybeaconingd \
      com.apple.modelcatalogd \
      com.apple.modelmanagerd \
      com.apple.triald.system \
      com.apple.biomed \
      com.apple.coreduetd \
      com.apple.contextstored \
      com.apple.wifianalyticsd \
      com.apple.audioanalyticsd \
      com.apple.audiomxd \
      com.apple.ecosystemanalyticsd \
      com.apple.ecosystemd \
      com.apple.SubmitDiagInfo \
      com.apple.osanalytics.osanalyticshelper \
      com.apple.rtcreportingd \
      com.apple.rapportd \
      com.apple.netbiosd \
      com.apple.GameController.gamecontrollerd \
      com.apple.gamepolicyd \
      com.apple.backupd \
      com.apple.backupd-helper \
      com.apple.familycontrols \
      com.apple.softwareupdated \
      com.apple.mobile.softwareupdated \
      com.apple.ReportCrash.Root \
      com.apple.CrashReporterSupportHelper \
      com.apple.spindump \
      com.apple.tailspind \
      com.apple.siri.acousticsignature \
      com.apple.siri.morphunassetsupdaterd \
      com.apple.corespeechd.system \
      com.apple.ospredictiond \
      com.apple.uarpassetmanagerd \
      com.apple.bosreporter \
      com.apple.boswatcher \
      com.apple.betaenrollmentd \
      com.apple.logd_reporter \
      com.apple.signpost.signpost_reporter \
      com.apple.csrutil.report \
      com.apple.gkreport \
      com.apple.nfcd \
      com.apple.seld \
      com.apple.remotemanagementd \
      com.apple.screensharing; do
      launchctl bootout system/"$daemon" 2>/dev/null || true
      launchctl disable system/"$daemon" 2>/dev/null || true
    done

    # ================================================================
    # USER AGENTS TO DISABLE
    # ================================================================
    for agent in \
      com.apple.ReportCrash \
      com.apple.assistantd \
      com.apple.parsecd \
      com.apple.tipsd \
      com.apple.cloudd \
      com.apple.cloudphotod \
      com.apple.cloudphotosd \
      com.apple.CloudSettingsSyncAgent \
      com.apple.cloudsettingssyncagent \
      com.apple.iCloudNotificationAgent \
      com.apple.iCloudUserNotifications \
      com.apple.icloudmailagent \
      com.apple.itunescloudd \
      com.apple.iCloudHelper \
      com.apple.icloud.fmfd \
      com.apple.icloud.searchpartyuseragent \
      com.apple.findmy.findmylocateagent \
      com.apple.findmymacmessenger \
      com.apple.security.cloudkeychainproxy3 \
      com.apple.protectedcloudstorage.protectedcloudkeysyncing \
      com.apple.replicatord \
      com.apple.bird \
      com.apple.intelligenceplatformd \
      com.apple.intelligencetasksd \
      com.apple.intelligenceflowd \
      com.apple.intelligencecontextd \
      com.apple.generativeexperiencesd \
      com.apple.knowledgeconstructiond \
      com.apple.naturallanguaged \
      com.apple.knowledge-agent \
      com.apple.triald \
      com.apple.privatecloudcomputed \
      com.apple.ModelCatalogAgent \
      com.apple.mlruntimed \
      com.apple.mlhostd \
      com.apple.ciphermld \
      com.apple.translationd \
      com.apple.photoanalysisd \
      com.apple.mediaanalysisd \
      com.apple.photolibraryd \
      com.apple.mediastream.mstreamd \
      com.apple.videosubscriptionsd \
      com.apple.ap.adprivacyd \
      com.apple.ap.promotedcontentd \
      com.apple.geoanalyticsd \
      com.apple.inputanalyticsd \
      com.apple.analyticsagent \
      com.apple.BiomeAgent \
      com.apple.biomesyncd \
      com.apple.UsageTrackingAgent \
      com.apple.ScreenTimeAgent \
      com.apple.contextstored \
      com.apple.ContextStoreAgent \
      com.apple.routined \
      com.apple.duetexpertd \
      com.apple.proactived \
      com.apple.proactiveeventtrackerd \
      com.apple.rapportd \
      com.apple.sharingd \
      com.apple.avconferenced \
      com.apple.CommCenter \
      com.apple.imagent \
      com.apple.imcore.imtransferagent \
      com.apple.imautomatichistorydeletionagent \
      com.apple.imdpersistence.IMDPersistenceAgent \
      com.apple.telephonyutilities.callservicesd \
      com.apple.callhistoryd \
      com.apple.callintelligenced \
      com.apple.screensharing.agent \
      com.apple.screensharing.menuextra \
      com.apple.sidecar-hid-relay \
      com.apple.sidecar-relay \
      com.apple.GameController.gamecontrolleragentd \
      com.apple.GamePolicyAgent \
      com.apple.gamed \
      com.apple.gamesaved \
      com.apple.homed \
      com.apple.homeeventsd \
      com.apple.homeenergyd \
      com.apple.passd \
      com.apple.familycircled \
      com.apple.familycontrols.useragent \
      com.apple.familynotificationd \
      com.apple.financed \
      com.apple.remindd \
      com.apple.suggestd \
      com.apple.watchlistd \
      com.apple.weatherd \
      com.apple.chronod \
      com.apple.followupd \
      com.apple.progressd \
      com.apple.voicebankingd \
      com.apple.newsd \
      com.apple.helpd \
      com.apple.Maps.pushdaemon \
      com.apple.Maps.mapssyncd \
      com.apple.Maps.mapspushd \
      com.apple.maps.destinationd \
      com.apple.navd \
      com.apple.geod \
      com.apple.geodMachServiceBridge \
      com.apple.intelligentroutingd \
      com.apple.SoftwareUpdateNotificationManager \
      com.apple.softwareupdate_notify_agent \
      com.apple.spindump_agent \
      com.apple.diagnostics_agent \
      com.apple.diagnosticextensionsd \
      com.apple.betaenrollmentagent \
      com.apple.appleseed.seedusaged \
      com.apple.assistant_service \
      com.apple.assistant_cdmd \
      com.apple.Siri.agent \
      com.apple.siriactionsd \
      com.apple.siriinferenced \
      com.apple.sirittsd \
      com.apple.SiriTTSTrainingAgent \
      com.apple.siriknowledged \
      com.apple.corespeechd \
      com.apple.siri.context.service \
      com.apple.askpermissiond \
      com.apple.studentd \
      com.apple.shazamd \
      com.apple.AMPDeviceDiscoveryAgent \
      com.apple.amp.mediasharingd \
      com.apple.mediacontinuityd \
      com.apple.sociallayerd \
      com.apple.email.maild \
      com.apple.SafariBookmarksSyncAgent \
      com.apple.SafariNotificationAgent \
      com.apple.Safari.History \
      com.apple.Safari.SafeBrowsing.Service \
      com.apple.SafariLaunchAgent \
      com.apple.Safari.PasswordBreachAgent \
      com.apple.commerce \
      com.apple.appstoreagent \
      com.apple.amsondevicestoraged \
      com.apple.amsengagementd \
      com.apple.amsaccountsd \
      com.apple.storekitagent \
      com.apple.managedappdistributionagent \
      com.apple.WorkflowKit.ShortcutsViewService \
      com.apple.liveactivitiesd \
      com.apple.LinkedNotesUIService \
      com.apple.avatarsd \
      com.apple.contacts.donation-agent \
      com.apple.dprivacyd \
      com.apple.feedbackd \
      com.apple.lockdownmoded \
      com.apple.businessservicesd \
      com.apple.RemoteManagementAgent \
      com.apple.backgroundassets.user \
      com.apple.BTServer.cloudpairing \
      com.apple.webprivacyd \
      com.apple.powerchime \
      com.apple.accessibility.heard; do
      launchctl bootout "gui/$GUI_UID/$agent" 2>/dev/null || true
      launchctl disable "gui/$GUI_UID/$agent" 2>/dev/null || true
    done

    # ================================================================
    # Disable Adobe background services
    # ================================================================
    for f in /Library/LaunchAgents/com.adobe.*.plist; do
      sudo launchctl unload -w "$f" 2>/dev/null || true
    done
    for f in /Library/LaunchDaemons/com.adobe.*.plist; do
      sudo launchctl unload -w "$f" 2>/dev/null || true
    done
    for f in /Users/${vars.user.name}/Library/LaunchAgents/com.adobe.*.plist; do
      launchctl unload -w "$f" 2>/dev/null || true
    done
    killall "ACCFinderSync" "Core Sync" "Creative Cloud" "Adobe Desktop Service" "CCXProcess" 2>/dev/null || true
    # Disable Adobe Finder Sync extension (Finder re-spawns it after killall)
    pluginkit -e ignore -i com.adobe.accmac.ACCFinderSync 2>/dev/null || true

    # ================================================================
    # Disable Spotlight indexing
    # ================================================================
    mdutil -a -i off 2>/dev/null || true
    for daemon in \
      com.apple.metadata.mds \
      com.apple.metadata.mds.index \
      com.apple.metadata.mds.scan \
      com.apple.metadata.mds.spindump; do
      launchctl bootout system/"$daemon" 2>/dev/null || true
      launchctl disable system/"$daemon" 2>/dev/null || true
    done
    for agent in \
      com.apple.Spotlight \
      com.apple.corespotlightd \
      com.apple.corespotlightservice \
      com.apple.spotlightknowledged \
      com.apple.spotlightknowledged.importer \
      com.apple.spotlightknowledged.updater \
      com.apple.managedcorespotlightd; do
      launchctl bootout "gui/$GUI_UID/$agent" 2>/dev/null || true
      launchctl disable "gui/$GUI_UID/$agent" 2>/dev/null || true
    done

    # Lock Siri vocabulary folder
    rm -rf /Users/${vars.user.name}/Library/Assistant/SiriVocabulary 2>/dev/null || true
    mkdir -p /Users/${vars.user.name}/Library/Assistant/SiriVocabulary
    chflags uchg /Users/${vars.user.name}/Library/Assistant/SiriVocabulary

    # Kill Shortcuts
    rm -rf /Users/${vars.user.name}/Library/Shortcuts/ 2>/dev/null || true
    killall BackgroundShortcutRunner ShortcutsViewService ShortcutsMacHelper 2>/dev/null || true
  '';

  launchd.user.agents.notunes = {
    serviceConfig = {
      ProgramArguments = [ "/Applications/noTunes.app/Contents/MacOS/noTunes" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };


  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    inter
    dm-sans
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    yabai
    skhd
    sketchybar
    jq
    nixfmt
  ];

  system.stateVersion = 5;
}
