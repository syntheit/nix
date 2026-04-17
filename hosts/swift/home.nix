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
    ../../home/modules/kitty.nix
    ../../home/modules/git.nix
    ../../home/modules/ssh.nix
    ../../home/shell.nix

    # macOS-specific modules
    ../../home/modules/sketchybar.nix
    ../../home/modules/app-tweaks.nix
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
    ffmpeg-full
    findutils
    gawk
    gnugrep
    gnused
    go
    nodejs
    pnpm
    ripgrep
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
