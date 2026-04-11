{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    ../../home/shell.nix
    ../../home/modules/git.nix
    ../../home/modules/ssh.nix
  ];

  home.username = "matv";
  home.homeDirectory = "/home/matv";
  home.stateVersion = "25.05";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
  };

  home.packages = with pkgs; [
    btop
    fastfetch
    tmux
    lazygit
    ripgrep
    fd
    jq
    gh
    duf
    restic
  ];

  programs.starship.settings.hostname = {
    ssh_only = true;
    format = "[ 🔀 $hostname]($style)";
    style = "bold green";
  };

  programs.home-manager.enable = true;
}
