{
  pkgs,
  lib,
  vars,
  ...
}:

let
  menubarBlocker = pkgs.stdenv.mkDerivation {
    name = "menubar-blocker";
    src = pkgs.writeText "main.c" ''
      #include <ApplicationServices/ApplicationServices.h>

      CGEventRef callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
          CGPoint location = CGEventGetLocation(event);
          if (location.y <= 1.0) {
              location.y = 2.0; 
              CGEventSetLocation(event, location);
          }
          return event;
      }

      int main() {
          CFMachPortRef eventTap = CGEventTapCreate(
              kCGSessionEventTap, 
              kCGHeadInsertEventTap, 
              0, 
              CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventLeftMouseDragged), 
              callback, 
              NULL
          );
          
          if (!eventTap) {
              return 1;
          }
          
          CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
          CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
          CGEventTapEnable(eventTap, true);
          CFRunLoopRun();
          return 0;
      }
    '';

    # Dependencies
    buildInputs = [ ];

    unpackPhase = "true";
    buildPhase = "clang -framework ApplicationServices -O2 -o menubar-blocker $src";
    installPhase = "mkdir -p $out/bin; cp menubar-blocker $out/bin/";
  };
in
{
  system.primaryUser = vars.user.name;

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
      cleanup = "zap"; # Remove unlisted packages
      upgrade = true;
    };
    casks = [
      "kitty"
      "zen"
      "spotify"
      "raycast"
      "font-jetbrains-mono-nerd-font"
      "thunderbird"
      "cursor"
      "arc"
      "nextcloud"
      "syncthing-app"
      "visual-studio-code"
      "transmission"
      "whatsapp"
      "iina"
      "telegram"
      "affinity"
      "antigravity"
      "windscribe"
      "orbstack"
      "karabiner-elements"
      "eqmac"
      "macwhisper"
      "obsidian"
      "dbeaver-community"
      "kiro"
    ];
    brews = [
      "mas"
      "switchaudio-osx"
      "fastfetch"
      "blueutil"
      "wifi-password"
      "opencode"
    ];
  };

  system.defaults = {
    finder = {
      AppleShowAllFiles = true;
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # List view
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    NSGlobalDomain = {
      KeyRepeat = 2; # Slower key repeat
      InitialKeyRepeat = 10; # Short delay before repeat
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
      Clicking = true; # Tap to click
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = false;
    };

    WindowManager = {
      EnableStandardClickToShowDesktop = false;
    };
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = false;
    remapCapsLockToEscape = false;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

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
      mouse_follows_focus = "on";
      focus_follows_mouse = "autoraise";
      active_window_opacity = "1.0";
      normal_window_opacity = "1.0";
    };
    extraConfig = ''
      # Load scripting addition (requires sudoers config)
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
    skhdConfig = ''
      # Application launchers
      fn - return : open -na kitty
      fn - t : open -na kitty
      fn - r : open -a Raycast
      fn - c : open -g "raycast://extensions/raycast/clipboard-history/clipboard-history"
      cmd - space : open -a Raycast
      fn - b : open -a "Zen Browser"
      fn - e : open -a Finder

      # Window management
      fn - q : yabai -m window --close
      fn - f : yabai -m window --toggle zoom-fullscreen
      fn - space : yabai -m window --toggle float

      # Focus window (vim-style navigation)
      fn - h : yabai -m window --focus west
      fn - j : yabai -m window --focus south
      fn - k : yabai -m window --focus north
      fn - l : yabai -m window --focus east

      # Move window (with shift)
      shift + fn - h : yabai -m window --swap west
      shift + fn - j : yabai -m window --swap south
      shift + fn - k : yabai -m window --swap north
      shift + fn - l : yabai -m window --swap east

      # Resize window
      fn + alt - h : yabai -m window --resize left:-50:0
      fn + alt - j : yabai -m window --resize bottom:0:50
      fn + alt - k : yabai -m window --resize top:0:-50
      fn + alt - l : yabai -m window --resize right:50:0

      fn - 1 : yabai -m space --focus 1
      fn - 2 : yabai -m space --focus 2
      fn - 3 : yabai -m space --focus 3
      fn - 4 : yabai -m space --focus 4
      fn - 5 : yabai -m space --focus 5
      fn - 6 : yabai -m space --focus 6
      fn - 7 : yabai -m space --focus 7
      fn - 8 : yabai -m space --focus 8
      fn - 9 : yabai -m space --focus 9
      fn - 0 : yabai -m space --focus 10

      shift + fn - 1 : yabai -m window --space 1
      shift + fn - 2 : yabai -m window --space 2
      shift + fn - 3 : yabai -m window --space 3
      shift + fn - 4 : yabai -m window --space 4
      shift + fn - 5 : yabai -m window --space 5
      shift + fn - 6 : yabai -m window --space 6
      shift + fn - 7 : yabai -m window --space 7
      shift + fn - 8 : yabai -m window --space 8
      shift + fn - 9 : yabai -m window --space 9
      shift + fn - 0 : yabai -m window --space 10

      # Relative workspace movement
      fn - 0x2F : yabai -m space --focus next  # cmd + .
      fn - 0x2B : yabai -m space --focus prev  # cmd + ,
      shift + fn - 0x2F : yabai -m window --space next  # shift + cmd + .
      shift + fn - 0x2B : yabai -m window --space prev  # shift + cmd + ,

      # Screenshots
      shift + cmd - s : open -a Screenshot

      # Lock screen
      shift + fn - escape : pmset displaysleepnow

      # Toggle layout
      fn + alt - space : yabai -m space --layout $(yabai -m query --spaces --space | jq -r 'if .type == "bsp" then "float" else "bsp" end')

      # Balance windows
      fn + alt - b : yabai -m space --balance
    '';
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

    # Dock: Hide completely by setting a massive autohide delay
    set_default com.apple.dock autohide -bool true
    set_default com.apple.dock autohide-delay -float 1000
    set_default com.apple.dock autohide-time-modifier -float 0
    set_default com.apple.dock static-only -bool true
    set_default com.apple.dock show-recents -bool false
    killall Dock
    set_default NSGlobalDomain _HIHideMenuBar -bool true
    set_default NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false
    killall SystemUIServer || true
    killall Finder || true
    set_default com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "{enabled = 0; value = { parameters = (32, 49, 1048576); type = 'standard'; }; }"

    set_default com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
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
