{
  pkgs,
  config,
  vars,
  lib,
  ...
}:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;

    shellAliases = {
      ls = "eza --icons";
      ll = "eza -l --icons";
      la = "eza -la --icons";
    }
    // lib.optionalAttrs pkgs.stdenv.isLinux {
      locate = "plocate";
    };

    history = {
      size = 50000;
      save = 50000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true; # Prefix a command with space to keep it out of history
      share = true;
      extended = true;
      expireDuplicatesFirst = true;
    };

    defaultKeymap = "emacs";

    # fzf-tab: replaces default tab completion with fzf-powered menu
    plugins = [
      {
        name = "fzf-tab";
        src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
      }
    ];

    initContent = ''
      # --- Options ---
      setopt auto_cd              # Type a directory name to cd into it
      setopt auto_pushd           # cd pushes onto directory stack
      setopt pushd_ignore_dups    # No duplicates in dir stack
      setopt pushd_silent         # Don't print dir stack after pushd/popd
      setopt interactive_comments # Allow comments in interactive shell
      setopt hist_ignore_all_dups # Remove older duplicates from history
      setopt prompt_subst

      # --- Completion styling ---
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
      zstyle ':completion:*:default' list-colors ''${(s.:.)LS_COLORS}
      zstyle ':completion:*' menu select
      zstyle ':completion:*' special-dirs true
      zstyle ':completion:*' squeeze-slashes true
      zstyle ':completion:*:descriptions' format '[%d]'
      zstyle ':completion:*' group-name ""
      zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
      zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

      # --- fzf-tab config ---
      zstyle ':fzf-tab:*' fzf-flags --height=40% --layout=reverse
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
      zstyle ':fzf-tab:complete:ls:*' fzf-preview 'eza -1 --color=always $realpath'

      # --- Keybindings ---
      # History substring search - up/down arrows
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down
      HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='none'
      HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='none'

      bindkey '^[[1;5C' forward-word      # Ctrl+Right
      bindkey '^[[1;5D' backward-word     # Ctrl+Left
      bindkey '^H' backward-kill-word     # Ctrl+Backspace

      # Sudo widget - double ESC to toggle sudo prefix
      sudo-command-line() {
        [[ -z $BUFFER ]] && zle up-history
        if [[ $BUFFER == sudo\ * ]]; then
          LBUFFER="''${LBUFFER#sudo }"
        else
          LBUFFER="sudo $LBUFFER"
        fi
      }
      zle -N sudo-command-line
      bindkey '\e\e' sudo-command-line

      # --- Cursor shape (blinking underline) ---
      echo -ne '\e[3 q'
      function zle-line-init() {
        zle reset-prompt
        echo -ne '\e[3 q'
      }
      zle -N zle-line-init
    '';
  };


  # nix-index for command-not-found package suggestions (uses pre-built database)
  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = true;
      continuation_prompt = "> ";

      format = "$nix_shell$cmd_duration$jobs$directory$python$nodejs$rust$golang$git_branch$git_status$character";
      right_format = "";

      character = {
        format = "$symbol ";
        success_symbol = "[>](white)";
        error_symbol = "[>](red)";
        vimcmd_symbol = "[>](white)";
        vimcmd_replace_one_symbol = ">";
        vimcmd_replace_symbol = ">";
        vimcmd_visual_symbol = ">";
      };

      directory = {
        home_symbol = "~";
        truncation_length = 3;
        truncation_symbol = "";
        read_only = "";
        use_os_path_sep = true;
        style = "bright-blue";
        format = "[$path]($style)";
        repo_root_style = "bright-blue";
        repo_root_format = "[$path]($style)";
      };

      git_branch = {
        format = " [$branch(:$remote_branch)]($style)";
        style = "bright-blue";
        truncation_symbol = "";
        only_attached = true;
      };

      git_status = {
        style = "bright-blue";
        format = "([$ahead_behind$staged$modified$untracked$renamed$deleted$conflicted$stashed](bright-blue))";
        conflicted = "!";
        ahead = "+$count";
        behind = "-$count";
        diverged = "+$ahead_count -$behind_count";
        untracked = "?";
        stashed = "$";
        modified = "*";
        staged = "+$count";
        renamed = ">";
        deleted = "x";
      };

      nix_shell = {
        style = "bright-blue";
        format = "[nix:$state]($style) ";
        impure_msg = "impure";
        pure_msg = "pure";
        unknown_msg = "unknown";
      };

      cmd_duration = {
        min_time = 1000;
        format = "[$duration]($style) ";
        style = "bright-blue";
      };

      jobs = {
        format = "[$number]($style) ";
        style = "bright-blue";
      };

      python = {
        format = "[py $version]($style) ";
        style = "bright-blue";
        version_format = "v\${raw}";
      };

      nodejs = {
        format = "[node $version]($style) ";
        style = "bright-blue";
        version_format = "v\${raw}";
      };

      rust = {
        format = "[rust $version]($style) ";
        style = "bright-blue";
        version_format = "v\${raw}";
      };

      golang = {
        format = "[go $version]($style) ";
        style = "bright-blue";
        version_format = "v\${raw}";
      };

      git_metrics.disabled = true;
      localip.disabled = true;
      time.disabled = true;
      battery.disabled = true;
      username.disabled = true;
      sudo.disabled = true;
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.bat.enable = true;

  # Colored man pages via bat
  home.sessionVariables = {
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };

  # Extra completion definitions for hundreds of commands
  home.packages = [ pkgs.zsh-completions ];
}
