{
  lib,
  pkgs,
  inputs,
  vars,
  extraLibs,
  config,
  ...
}:
{
  imports = [
    ./modules/ssh.nix
    ./modules/git.nix
    ./modules/packages
    ./modules/hyprland.nix
    ./modules/waybar.nix
    ./modules/rofi.nix
    ./modules/kitty.nix
    ./modules/thunderbird.nix
    ./modules/gtk.nix
    ./modules/mime-apps.nix
    ./modules/services.nix
    ./modules/files.nix
    ./shell.nix
  ];

  home.username = "${vars.user.name}";
  home.homeDirectory = "/home/${vars.user.name}";

  home.stateVersion = "24.11";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    hms = "home-manager switch";
    k = "kubectl";
    highlight = "grep --color=always -e \"^\"";
  };

  programs.home-manager.enable = true;
}
