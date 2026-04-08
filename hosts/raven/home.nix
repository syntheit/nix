{
  pkgs,
  vars,
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

  home.username = "droid";
  home.homeDirectory = "/home/droid";
  home.stateVersion = "26.05";

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
  };

  home.packages = with pkgs; [
    # CLI tools
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

    # Development
    python3
    go
    nodejs
    pnpm
    claude-code
    gnumake
  ];

  programs.home-manager.enable = true;
}
