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
    ../../home/modules/neovim.nix
    ../../home/modules/tmux.nix
  ];

  home.username = "matv";
  home.homeDirectory = "/home/matv";
  home.stateVersion = "23.05";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    deploy-conduit = "nixos-rebuild switch --flake ~/nix#conduit --target-host conduit --sudo";
  };

  home.packages = with pkgs; [
    btop
    fastfetch
    wget
    tree
    ripgrep
    fd
    unzip
    jq
    gh
    duf
    dig
    openssl
    traceroute
    lsof
    python3
    claude-code
    restic
  ];

  programs.starship.settings.directory = {
    style = "purple";
    repo_root_style = "bold purple";
    before_repo_root_style = "dimmed purple";
  };

  programs.home-manager.enable = true;
}
