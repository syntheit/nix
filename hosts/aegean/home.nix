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
    ../../home/modules/kitty.nix
    ../../home/modules/git.nix
    ../../home/shell.nix

    # macOS-specific modules
    ../../home/modules/sketchybar.nix
    ../../home/modules/app-tweaks.nix
  ];

  home.username = vars.user.name;
  home.homeDirectory = "/Users/${vars.user.name}";

  home.stateVersion = "24.11";

  # Common shell aliases
  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    k = "kubectl";
    highlight = "grep --color=always -e \"^\"";
  };

  # Ensure PATH includes Homebrew and Nix paths
  home.sessionPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/run/current-system/sw/bin"
  ];

  programs.home-manager.enable = true;

  xdg.configFile."karabiner/assets/complex_modifications/caps_lock_to_fn.json".text =
    builtins.toJSON
      {
        title = "Caps Lock to Fn";
        rules = [
          {
            description = "Change caps_lock to fn";
            manipulators = [
              {
                type = "basic";
                from = {
                  key_code = "caps_lock";
                  modifiers = {
                    optional = [ "any" ];
                  };
                };
                to = [
                  {
                    key_code = "fn";
                  }
                ];
              }
            ];
          }
        ];
      };
}
