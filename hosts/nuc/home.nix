{
  pkgs,
  inputs,
  vars,
  ...
}:
{
  # Headless server home profile (mirrors vista's) — no desktop, just the CLI
  # toolchain needed to administer the box over SSH.
  imports = [
    # ../../home/shell.nix sets programs.nix-index-database.comma, which only
    # exists once this module is imported (same as vista's home.nix).
    inputs.nix-index-database.homeModules.nix-index
    ../../home/modules/ssh.nix
    ../../home/modules/tmux.nix
    ../../home/modules/git.nix
    ../../home/shell.nix
  ];

  home.username = "${vars.user.name}";
  home.homeDirectory = "/home/${vars.user.name}";
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    btop
    fastfetch
    ripgrep
    fd
    jq
    wget
    tree
    tmux
    mosh
  ];

  programs.home-manager.enable = true;
}
