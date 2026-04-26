{
  lib,
  pkgs,
  inputs,
  vars,
  config,
  ...
}:
{
  imports = [
    # Cross-platform modules (work on both Linux and Darwin)
    inputs.nix-index-database.homeModules.nix-index
    inputs.stylix.homeModules.stylix
    ../../home/modules/stylix.nix
    ../../home/modules/ghostty.nix
    ../../home/modules/git.nix
    ../../home/modules/neovim.nix
    ../../home/modules/ssh.nix
    ../../home/shell.nix

    # macOS-specific modules
    ../../home/modules/sketchybar.nix
    ../../home/modules/app-tweaks.nix
    ../../home/modules/dashboard-darwin.nix
    ../../home/modules/tmux.nix
    ../../home/modules/eq.nix
    ../../home/modules/overview.nix
    ../../home/modules/volume-panel.nix
    ../../home/modules/bluetooth-panel.nix
    ../../home/modules/wifi-panel.nix
    ../../home/modules/brightness-panel.nix
    ../../home/modules/search-panel.nix
    ../../home/modules/wallpaper-darwin.nix
    ../../home/modules/menubar-blocker.nix
    ../../home/modules/square-corners.nix
  ];

  home.username = vars.user.name;
  home.homeDirectory = "/Users/${vars.user.name}";

  home.stateVersion = "24.11";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    k = "kubectl";
    highlight = "grep --color=always -e \"^\"";
  };

  home.sessionPath = [
    # GNU coreutils unprefixed (override BSD tools with GNU versions)
    "${pkgs.coreutils}/libexec/gnubin"
    "${pkgs.findutils}/libexec/gnubin"
    "${pkgs.gnugrep}/libexec/gnubin"
    "${pkgs.gnused}/libexec/gnubin"
    "${pkgs.gawk}/libexec/gnubin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/run/current-system/sw/bin"
  ];

  home.packages = with pkgs; [
    awscli2
    aws-sam-cli
    btop
    claude-code
    coreutils
    sops
    ssh-to-age
    fastfetch
    fd
    ffmpeg
    findutils
    gawk
    gnugrep
    gnused
    go
    nodejs
    pnpm
    ripgrep
    foyer
    mosh
    spotify-player
  ];

  programs.yazi = {
    enable = true;
    shellWrapperName = "y";
    settings.mgr = {
      sort_by = "mtime";
      sort_reverse = true;
      sort_dir_first = false;
    };
  };

  # Screenshot to harbor — Shift+Cmd+X triggers interactive selection,
  # uploads to ~/screenshots/swift/ on harbor for Claude Code to read
  home.file.".local/bin/screenshot-to-harbor" = {
    executable = true;
    text = ''
      #!/bin/bash
      FILE="$(date +%Y%m%d-%H%M%S).png"
      LOCAL="/tmp/$FILE"
      REMOTE="screenshots/swift"

      # Interactive selection screenshot
      screencapture -i "$LOCAL" 2>/dev/null

      # User cancelled the selection
      [ ! -f "$LOCAL" ] && exit 0

      # Ensure remote dir exists and upload
      ssh harbor "mkdir -p ~/$REMOTE"
      scp -q "$LOCAL" "harbor:~/$REMOTE/$FILE"
      rm "$LOCAL"

      # Notification
      osascript -e "display notification \"$FILE uploaded to harbor\" with title \"Screenshot\""
    '';
  };

  # Suppress "Last login: ..." message in new terminal windows
  home.file.".hushlogin".text = "";

  programs.home-manager.enable = true;

  # Karabiner config managed declaratively — overwrites on each rebuild
  # fn_function_keys: converts F3/F4 from vendor keys to standard keycodes (skhd can catch these)
  # complex_modifications: caps_lock→fn
  home.activation.karabinerConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/karabiner"
    cat > "$HOME/.config/karabiner/karabiner.json" << 'KARABINER_EOF'
{
    "profiles": [
        {
            "name": "Default profile",
            "selected": true,
            "virtual_hid_keyboard": { "keyboard_type_v2": "ansi" },
            "fn_function_keys": [
                { "from": { "key_code": "f1" }, "to": [{ "consumer_key_code": "display_brightness_decrement" }] },
                { "from": { "key_code": "f2" }, "to": [{ "consumer_key_code": "display_brightness_increment" }] },
                { "from": { "key_code": "f3" }, "to": [{ "key_code": "f3" }] },
                { "from": { "key_code": "f4" }, "to": [{ "key_code": "f4" }] },
                { "from": { "key_code": "f5" }, "to": [{ "key_code": "f5" }] },
                { "from": { "key_code": "f6" }, "to": [{ "key_code": "f6" }] },
                { "from": { "key_code": "f7" }, "to": [{ "consumer_key_code": "rewind" }] },
                { "from": { "key_code": "f8" }, "to": [{ "consumer_key_code": "play_or_pause" }] },
                { "from": { "key_code": "f9" }, "to": [{ "consumer_key_code": "fast_forward" }] },
                { "from": { "key_code": "f10" }, "to": [{ "consumer_key_code": "mute" }] },
                { "from": { "key_code": "f11" }, "to": [{ "consumer_key_code": "volume_decrement" }] },
                { "from": { "key_code": "f12" }, "to": [{ "consumer_key_code": "volume_increment" }] }
            ],
            "complex_modifications": {
                "rules": [
                    {
                        "description": "Change caps_lock to fn",
                        "manipulators": [
                            {
                                "type": "basic",
                                "from": { "key_code": "caps_lock", "modifiers": { "optional": ["any"] } },
                                "to": [{ "key_code": "fn" }]
                            }
                        ]
                    }
                ]
            }
        }
    ]
}
KARABINER_EOF
  '';
}
