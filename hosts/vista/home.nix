{
  pkgs,
  inputs,
  vars,
  ...
}:
{
  # Headless server home profile. Deliberately does NOT import ../../home (the
  # full workstation profile) or any desktop/Hyprland module — vista has no GUI.
  # Just the CLI toolchain needed to administer the box over SSH.
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    ../../home/modules/ssh.nix
    ../../home/modules/tmux.nix
    ../../home/modules/git.nix
    ../../home/modules/neovim.nix
    ../../home/shell.nix
    ../../home/modules/opencode.nix
  ];

  home.username = "${vars.user.name}";
  home.homeDirectory = "/home/${vars.user.name}";
  home.stateVersion = "24.11";

  # Prompt path color = orange — vista's host tint. It's the one saturated hue
  # not used anywhere else in the prompt (blue=home boxes, cyan=raven,
  # yellow=conduit, salmon=harbor, purple stays git-branch-only).
  programs.starship.settings.directory = {
    style = "#FF8700";
    repo_root_style = "bold #FF8700";
    before_repo_root_style = "dimmed #FF8700";
  };

  home.shellAliases = {
    btw = "${pkgs.fastfetch}/bin/fastfetch";
    igrep = "grep -i";
    hms = "home-manager switch";
    highlight = "grep --color=always -e \"^\"";
  };

  home.packages = with pkgs; [
    # ── CLI essentials ──
    btop
    fastfetch
    ripgrep
    fd
    jq
    wget
    tree
    unzip
    tmux
    mosh
    yazi
    lazygit
    tldr
    gh
    claude-code
    nixfmt-rfc-style
    nix-output-monitor
    nodejs

    # ── Headless media/utility CLI ──
    yt-dlp
    ffmpeg-full

    # ── Secrets tooling — edit sops secrets from vista itself ──
    sops
    ssh-to-age
  ];

  programs.home-manager.enable = true;
}
