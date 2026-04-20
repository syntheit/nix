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
    ripgrep
    fd
    jq
    gh
    duf
    restic
  ];

  programs.starship.settings.directory = {
    style = "yellow";
    repo_root_style = "bold yellow";
    before_repo_root_style = "dimmed yellow";
  };

  programs.home-manager.enable = true;
}
