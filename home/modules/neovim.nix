{ pkgs, lib, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true; # Sets $EDITOR=nvim (fixes yazi, git commit, sudoedit, etc.)
    viAlias = true; # vi -> nvim
    vimAlias = true; # vim -> nvim
    withRuby = false;
    withPython3 = false;
  };

  # Symlink lua config into ~/.config/nvim/
  xdg.configFile."nvim/init.lua".source = ../config/nvim/init.lua;

  # LSP servers, formatters, and tools (all on PATH for neovim to find)
  home.packages =
    with pkgs;
    [
      # LSP servers
      nil # Nix
      gopls # Go
      pyright # Python
      typescript-language-server # TypeScript / JavaScript
      lua-language-server # Lua (for editing neovim config)
      yaml-language-server # YAML
      vscode-langservers-extracted # HTML, CSS, JSON, ESLint
      bash-language-server # Bash / Zsh
      marksman # Markdown
      taplo # TOML
      tailwindcss-language-server # Tailwind CSS
      svelte-language-server # Svelte
      dockerfile-language-server # Dockerfile
      helm-ls # Helm charts

      # Formatters
      nixfmt # Nix
      stylua # Lua
      prettierd # JS/TS/CSS/HTML/JSON/YAML/Markdown
      gofumpt # Go (stricter gofmt)
      black # Python
      shfmt # Shell scripts

      # Tools needed by plugins
      ripgrep # telescope live grep
      fd # telescope file finder
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      gcc # telescope-fzf-native compilation
      gnumake
    ];
}
