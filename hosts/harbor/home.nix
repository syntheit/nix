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
  home.stateVersion = "23.05";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    deploy-conduit = "nixos-rebuild switch --flake ~/nix#conduit --target-host conduit --sudo";
  };

  home.packages = with pkgs; [
    btop
    fastfetch
    tmux
    lazygit
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

  programs.starship.settings.hostname = {
    ssh_only = true;
    format = "[󰒋 $hostname]($style)";
    style = "dimmed white";
  };

  programs.home-manager.enable = true;
}
