{ pkgs, ... }:
{
  home.username = "daniel";
  home.homeDirectory = "/home/daniel";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    bat
    btop
    fastfetch
    fd
    jq
    ripgrep
    tree
  ];
}
