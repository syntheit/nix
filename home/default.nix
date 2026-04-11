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
    inputs.nix-index-database.homeModules.nix-index
    inputs.stylix.homeModules.stylix  # Load Stylix library
    ./modules/stylix.nix              # Load Stylix configuration
    ./modules/ssh.nix
    ./modules/git.nix
    ./modules/packages.nix
    ./modules/hyprland.nix
    ./modules/rofi.nix
    ./modules/kitty.nix
    ./modules/thunderbird.nix
    ./modules/mime-apps.nix
    ./modules/services.nix
    ./modules/nextcloud.nix
    ./modules/zen.nix
    ./modules/dunst.nix
    ./modules/copyq.nix
    ./modules/wallpaper.nix
    ./modules/zed.nix
    ./modules/spotify.nix
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
    deploy-conduit = "nixos-rebuild switch --flake ~/nix#conduit --target-host conduit --use-remote-sudo";
  };

  programs.home-manager.enable = true;
}
