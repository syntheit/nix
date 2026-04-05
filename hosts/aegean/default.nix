{
  pkgs,
  lib,
  vars,
  ...
}:

let
  menubarBlocker = pkgs.callPackage ../../packages/menubar-blocker { };
in
{
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
      "claude-code"
      "cursor"
      "dbeaver-community"
      "eqmac"
      "font-jetbrains-mono-nerd-font"
      "iina"
      "karabiner-elements"
      "kiro"
      "kitty"
      "lulu"
      "macwhisper"
      "nextcloud"
      "obsidian"
      "orbstack"
      "raycast"
      "spotify"
      "syncthing-app"
      "telegram"
      "thunderbird"
      "transmission"
      "visual-studio-code"
      "whatsapp"
      "windscribe"
      "zen"
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
      mouse_follows_focus = "on";
      focus_follows_mouse = "autoraise";
      active_window_opacity = "1.0";
      normal_window_opacity = "1.0";
    };
    extraConfig = ''
      # Load scripting addition (requires sudoers entry below)
      sudo yabai --load-sa
      yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"

      # Window rules
      yabai -m rule --add app="^System Preferences$" manage=off
      yabai -m rule --add app="^System Settings$" manage=off
      yabai -m rule --add app="^Calculator$" manage=off
      yabai -m rule --add app="^Raycast$" manage=off
      yabai -m rule --add app="^Archive Utility$" manage=off
      yabai -m rule --add app="^Finder$" title="(Copy|Move|Delete|Connect)" manage=off
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

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  users.users.${vars.user.name} = {
    name = vars.user.name;
    home = "/Users/${vars.user.name}";
    shell = pkgs.zsh;
  };

  system.activationScripts.postActivation.text = ''
    set_default() {
      sudo -u ${vars.user.name} defaults write "$@"
    }

    # Hide menu bar (per-user defaults, must use activation script)
    set_default NSGlobalDomain _HIHideMenuBar -bool true
    set_default NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false
    killall SystemUIServer || true
    killall Finder || true

    # Disable Spotlight shortcut (Cmd+Space) — complex nested dict not supported declaratively
    set_default com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "{enabled = 0; value = { parameters = (32, 49, 1048576); type = 'standard'; }; }"

    # === Privacy & Telemetry (system-level) ===

    # Disable Siri data sharing
    set_default com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2

    # Disable diagnostic data submission to Apple
    defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit -bool false 2>/dev/null || true
    defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" ThirdPartyDataSubmit -bool false 2>/dev/null || true

    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

    # Grant accessibility permissions (requires SIP disabled)
    YABAI_BIN=$(readlink -f ${pkgs.yabai}/bin/yabai)
    SKHD_BIN=$(readlink -f ${pkgs.skhd}/bin/skhd)
    MENUBAR_BIN=$(readlink -f ${menubarBlocker}/bin/menubar-blocker)
    TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
    for BIN in "$YABAI_BIN" "$SKHD_BIN" "$MENUBAR_BIN"; do
      sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceAccessibility', '$BIN', 1, 2, 4, 1);"
    done

    # Restart services after TCC permissions are granted to avoid race condition
    GUI_UID="$(id -u "${vars.user.name}")"
    launchctl bootout "gui/$GUI_UID/org.nixos.skhd" 2>/dev/null || true
    launchctl bootout "gui/$GUI_UID/org.nixos.yabai" 2>/dev/null || true
    launchctl bootout "gui/$GUI_UID/org.nixos.menubar-blocker" 2>/dev/null || true
    sleep 1
    launchctl bootstrap "gui/$GUI_UID" /Users/${vars.user.name}/Library/LaunchAgents/org.nixos.skhd.plist 2>/dev/null || true
    launchctl bootstrap "gui/$GUI_UID" /Users/${vars.user.name}/Library/LaunchAgents/org.nixos.yabai.plist 2>/dev/null || true
    launchctl bootstrap "gui/$GUI_UID" /Users/${vars.user.name}/Library/LaunchAgents/org.nixos.menubar-blocker.plist 2>/dev/null || true

    # Disable Apple telemetry daemons (system-level)
    for daemon in \
      com.apple.analyticsd \
      com.apple.assistantd \
      com.apple.parsecd \
      com.apple.tipsd; do
      launchctl bootout system/"$daemon" 2>/dev/null || true
      launchctl disable system/"$daemon" 2>/dev/null || true
    done

    # Disable Apple telemetry agents (user-level)
    for agent in \
      com.apple.ReportCrash \
      com.apple.assistantd \
      com.apple.parsecd \
      com.apple.tipsd; do
      launchctl bootout "gui/$GUI_UID/$agent" 2>/dev/null || true
      launchctl disable "gui/$GUI_UID/$agent" 2>/dev/null || true
    done
  '';

  launchd.user.agents.menubar-blocker = {
    serviceConfig = {
      ProgramArguments = [ "${menubarBlocker}/bin/menubar-blocker" ];
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
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
    menubarBlocker
  ];

  system.stateVersion = 5;
}
