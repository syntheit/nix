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
    inputs.nix-index-database.hmModules.nix-index
    inputs.stylix.homeModules.stylix  # Load Stylix library
    ./modules/stylix.nix              # Load Stylix configuration
    ./modules/ssh.nix
    ./modules/git.nix
    ./modules/packages.nix
    ./modules/hyprland.nix
    ./modules/waybar.nix
    ./modules/rofi.nix
    ./modules/kitty.nix
    ./modules/thunderbird.nix
    ./modules/mime-apps.nix
    ./modules/services.nix
    ./modules/nextcloud.nix
    ./modules/zen.nix
    ./modules/dunst.nix
    ./modules/wallpaper.nix
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
