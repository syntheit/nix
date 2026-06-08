{
  pkgs,
  lib,
  vars,
  config,
  hostName,
  ...
}:

let
  daemons = import ./disabled-daemons.nix;

  # Generates a bash for-loop that bootouts + disables every listed launchd
  # job. `scope` is the launchctl domain prefix (e.g. "system" for daemons,
  # "gui/$GUI_UID" for user agents — note the embedded $-var is bash's, not
  # Nix's). The whole target is wrapped in one bash word "${scope}/$entry"
  # so shellcheck stays quiet about word-splitting on $GUI_UID.
  mkDisableLoop = scope: items: ''
    for entry in ${lib.concatStringsSep " " items}; do
      launchctl bootout "${scope}/$entry" 2>/dev/null || true
      launchctl disable "${scope}/$entry" 2>/dev/null || true
    done
  '';

  # Per-host Tailscale IP for the SSH listener. SSH listens only on the
  # Tailscale interface; openFirewall stays off on every other path. Each
  # host's address is the value Tailscale assigned when it joined the
  # tailnet — grab via `tailscale ip -4` after `tailscale up`.
  tailscaleIp = {
    swift = "100.78.114.100";
    mini = "100.75.241.25";
  }.${hostName};
in
{
  options.matv.darwin.tccGrants = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
    default = [ ];
    description = ''
      TCC.db grants written by the postActivation script. Each entry is an
      attrset with service/package/exec/reason fields. Hosts populate this
      from their own tcc-grants.nix.
    '';
  };

  config = {
    nixpkgs.config.allowUnfree = true;

    system.primaryUser = vars.user.name;

    # Nix daemon managed by Determinate Systems installer
    nix.enable = false;

    # ── Private GitHub flake inputs ─────────────────────────────────
    # The Determinate nix-daemon fetches git+ssh inputs as root, so it
    # reads /var/root/.ssh/{config,known_hosts,mainkey} — not your user
    # ~/.ssh. The activation script below writes config + known_hosts
    # declaratively. The key itself must be symlinked once per machine
    # (chicken-and-egg: needed for the first build that writes config):
    #
    #   sudo mkdir -p /var/root/.ssh
    #   sudo ln -sf /Users/daniel/.ssh/mainkey /var/root/.ssh/mainkey
    #
    # mainkey is a deploy key on syntheit/malli-deus and malli-nix.
    # Switched away from PAT+netrc because PATs expire silently; SSH
    # deploy keys don't. (See flake.nix:102-110 for the rationale.)

    # Determinate's /etc/nix/nix.conf has `!include nix.custom.conf`.
    # We use this to fast-fail flaky downloads from Determinate's own
    # cache (HTTP/2 framing errors) so nix falls through to
    # cache.nixos.org instead of retrying for minutes.
    environment.etc."nix/nix.custom.conf".text = ''
      connect-timeout = 5
      download-attempts = 2
      narinfo-cache-negative-ttl = 3600
    '';

    # Root SSH for daemon flake fetches. /var/root/.ssh isn't an /etc
    # path so environment.etc doesn't apply — keep the activation
    # script. mainkey itself must be symlinked once per machine:
    #   sudo mkdir -p /var/root/.ssh
    #   sudo ln -sf /Users/daniel/.ssh/mainkey /var/root/.ssh/mainkey
    system.activationScripts.preActivation.text = ''
      install -d -m 0700 /var/root/.ssh
      cat > /var/root/.ssh/config <<'SSHCFG'
      Host github-malli-deus
        User git
        HostName github.com
        IdentityFile /var/root/.ssh/mainkey
        IdentitiesOnly yes
      SSHCFG
      chmod 0600 /var/root/.ssh/config

      # Pre-populate github.com host key so the daemon never blocks on
      # an interactive "are you sure" prompt during a flake fetch.
      if ! grep -q '^github.com ' /var/root/.ssh/known_hosts 2>/dev/null; then
        ssh-keyscan -t ed25519,rsa github.com 2>/dev/null \
          >> /var/root/.ssh/known_hosts || true
        chmod 0644 /var/root/.ssh/known_hosts
      fi
    '';

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
        # Disable Mission Control vertical 3/4-finger swipe (overview app claims it).
        # Re-enable native horizontal 3/4-finger swipe-between-spaces.
        "com.apple.AppleMultitouchTrackpad" = {
          TrackpadThreeFingerVertSwipeGesture = 0;
          TrackpadThreeFingerHorizSwipeGesture = 2;
          TrackpadFourFingerHorizSwipeGesture = 2;
        };
        "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
          TrackpadThreeFingerVertSwipeGesture = 0;
          TrackpadThreeFingerHorizSwipeGesture = 2;
          TrackpadFourFingerHorizSwipeGesture = 2;
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

    # SSH — Tailscale-only, key-only
    environment.etc."ssh/sshd_tailscale_config".text = ''
      Port 22
      ListenAddress ${tailscaleIp}
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
        ProgramArguments = [
          "/usr/sbin/sshd"
          "-D"
          "-f"
          "/etc/ssh/sshd_tailscale_config"
        ];
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

    services.yabai = {
      enable = true;
      package = pkgs.yabai;
      config = {
        layout = "bsp";
        # external_bar reserves 38px at the top of every display for sketchybar
        # (matches sketchybar's `--bar height=38` in home/modules/sketchybar.nix).
        # Without this, managed windows extend underneath the sticky bar and
        # the bar visually overlays their top edge.
        external_bar = "all:38:0";
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
        yabai -m rule --add title="^vestal$" manage=off

        # Spotify → scratchpad (floating overlay)
        yabai -m rule --add app="^Spotify$" scratchpad=spotify
      '';
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

      # Finder: quittable like a normal app. Desktop stays enabled — its hidden
      # window anchors macOS focus on every space and prevents yabai's empty-space
      # bounce-back to space 1 (see commit 93813a6).
      set_default com.apple.finder QuitMenuItem -bool true

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
      # Power management: no powernap, no hibernation. sms/lessbright are
      # battery-specific — no-op on the mac mini, harmless to keep.
      # ================================================================
      pmset -a powernap 0
      pmset -a hibernatemode 0
      pmset -a sms 0
      pmset -a lessbright 0
      rm -f /var/vm/sleepimage 2>/dev/null || true

      # ================================================================
      # TCC permissions (requires SIP disabled)
      # ================================================================
      TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
      ${lib.concatMapStringsSep "\n" (g: ''
        # ${g.reason}
        sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('${g.service}', '$(readlink -f ${g.package}/bin/${g.exec})', 1, 2, 4, 1);"
      '') config.matv.darwin.tccGrants}

      # Force tccd to reload from TCC.db — direct sqlite writes don't invalidate
      # its in-memory cache, so yabai/skhd would otherwise launch without
      # effective accessibility until tccd is restarted.
      killall tccd 2>/dev/null || true

      # Bounce yabai/skhd only when their launchd plist actually changed.
      # Yabai keeps no on-disk bsp state, so each restart rebuilds the tree
      # from macOS's AX window enumeration — which doesn't preserve prior
      # geometry and reliably swaps two-window splits. Hashing the plist
      # catches both nixpkgs binary-path bumps and yabai/skhd config edits;
      # in the common no-op rebuild case, the running daemon is left alone.
      mkdir -p /var/db/nix-darwin
      RESTART_SVCS=()
      for svc in yabai skhd; do
        PLIST="/Users/${vars.user.name}/Library/LaunchAgents/org.nixos.$svc.plist"
        HASH_FILE="/var/db/nix-darwin/$svc.plist.sha"
        NEW_HASH=$(shasum "$PLIST" 2>/dev/null | awk '{print $1}')
        OLD_HASH=$(cat "$HASH_FILE" 2>/dev/null || true)
        if [ "$NEW_HASH" != "$OLD_HASH" ]; then
          RESTART_SVCS+=("$svc")
          echo "$NEW_HASH" > "$HASH_FILE"
        fi
      done

      if [ ''${#RESTART_SVCS[@]} -gt 0 ]; then
        for svc in "''${RESTART_SVCS[@]}"; do
          launchctl bootout "gui/$GUI_UID/org.nixos.$svc" 2>/dev/null || true
        done
        sleep 1
        for svc in "''${RESTART_SVCS[@]}"; do
          launchctl bootstrap "gui/$GUI_UID" "/Users/${vars.user.name}/Library/LaunchAgents/org.nixos.$svc.plist" 2>/dev/null || true
        done
      fi

      # Re-prime yabai without restarting it. The earlier Dock killall
      # unloads the scripting addition, so window_shadow=off etc. stop
      # applying; --load-sa re-injects it into the new Dock. rule --apply
      # re-evaluates rules against existing windows so Spotify reattaches
      # to its scratchpad without being relaunched.
      #
      # Two-step dance because:
      # - launchctl asuser puts us in daniel's Aqua session bootstrap
      #   (where Dock's mach port and /tmp/yabai_daniel.socket live), but
      #   leaves the process as root.
      # - sudo -u daniel drops to daniel's UID so the yabai socket is
      #   reachable and the inner sudo matches daniel's NOPASSWD entry
      #   from environment.etc."sudoers.d/yabai".
      if pgrep -qx yabai; then
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          pgrep -qx Dock && break
          sleep 1
        done
        sleep 1
        launchctl asuser "$GUI_UID" /usr/bin/sudo -u ${vars.user.name} /usr/bin/sudo -n /run/current-system/sw/bin/yabai --load-sa \
          || echo "[activation] yabai --load-sa failed (exit $?)"
        # Re-assert window_shadow. nix-darwin emits the config block BEFORE
        # extraConfig, so at yabai startup `window_shadow <val>` runs while
        # the SA isn't loaded yet and silently no-ops on existing windows.
        # Setting it again after --load-sa forces yabai to sweep every
        # managed window. Value is read from services.yabai.config so this
        # stays in sync if you ever flip it.
        launchctl asuser "$GUI_UID" /usr/bin/sudo -u ${vars.user.name} /run/current-system/sw/bin/yabai -m config window_shadow ${config.services.yabai.config.window_shadow} \
          || echo "[activation] yabai window_shadow refresh failed (exit $?)"
        launchctl asuser "$GUI_UID" /usr/bin/sudo -u ${vars.user.name} /run/current-system/sw/bin/yabai -m rule --apply \
          || echo "[activation] yabai rule --apply failed (exit $?)"
      fi

      # ================================================================
      # Re-enable daemons that were previously disabled but are required.
      # launchctl's disable override persists across reboots even after the
      # daemon is removed from the bootout loop below — so we explicitly
      # enable them here to undo any historical disable.
      #   - mediaremoted: routes media keys (F7/F8/F9) to Now Playing apps
      #   - rapportd: provides com.apple.CompanionLink XPC, which mediaremoted
      #     needs for event registration; without it mediaremoted's XPC server
      #     enters a degraded state where every client gets Code=1 errors
      # ================================================================
      for daemon in com.apple.mediaremoted com.apple.rapportd; do
        sudo launchctl enable system/"$daemon" 2>/dev/null || true
        sudo launchctl bootstrap system "/System/Library/LaunchDaemons/$daemon.plist" 2>/dev/null || true
      done
      # Kickstart rcd to flush stale Code=1 connection state to mediaremoted
      launchctl kickstart -k "gui/$GUI_UID/com.apple.rcd" 2>/dev/null || true

      # ================================================================
      # SYSTEM DAEMONS TO DISABLE
      # ================================================================
      ${mkDisableLoop "system" daemons.systemDaemons}

      # ================================================================
      # USER AGENTS TO DISABLE
      # ================================================================
      ${mkDisableLoop "gui/$GUI_UID" daemons.userAgents}

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
      ${mkDisableLoop "system" daemons.spotlightDaemons}
      ${mkDisableLoop "gui/$GUI_UID" daemons.spotlightAgents}

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
      sqlite
    ];

    system.stateVersion = 5;
  };
}
