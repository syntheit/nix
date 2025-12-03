{ pkgs, config, vars, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true; # Replaces compinit

    autosuggestion.enable = true;

    syntaxHighlighting.enable = true;

    # Shell aliases (cleaner than putting them in initExtra)
    shellAliases = {
      ls = "eza --icons";
      ll = "eza -l --icons";
      la = "eza -la --icons";
      locate = "plocate";
    };

    # History settings (Replaces HISTSIZE/SAVEHIST)
    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    # Keybindings (Emacs keymap)
    defaultKeymap = "emacs";

    # The "Transient Prompt" logic
    # Starship doesn't do this natively in Zsh yet, so we inject this snippet.
    initContent = ''
      # Set cursor to underline shape (blinking underline)
      # This overrides kitty's shell integration which sets it to beam
      echo -ne '\e[3 q'
      
      # Make the prompt transient (similar to p10k)
      setopt prompt_subst
      
      # Reset prompt before executing a command
      function zle-line-init() {
          zle reset-prompt
          # Re-apply blinking underline cursor after prompt reset
          echo -ne '\e[3 q'
      }
      zle -N zle-line-init
    '';
  };

  # Starship prompt - simple and clean
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = true;
      continuation_prompt = "> ";
      
      # Format: nix_shell, cmd_duration, jobs, directory, lang versions, git info, then prompt
      format = "$nix_shell$cmd_duration$jobs$directory$python$nodejs$rust$golang$git_branch$git_status$character";
      
      right_format = "";
      
      # Character prompt - white for success, red for errors
      character = {
        format = "$symbol ";
        success_symbol = "[>](white)";
        error_symbol = "[>](red)";
        vimcmd_symbol = "[>](white)";
        vimcmd_replace_one_symbol = ">";
        vimcmd_replace_symbol = ">";
        vimcmd_visual_symbol = ">";
      };
      
      # Directory - electric blue, no icons
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
      
      # Git branch - simple, no icons
      git_branch = {
        format = " [$branch(:$remote_branch)]($style)";
        style = "bright-blue";
        truncation_symbol = "";
        only_attached = true;
      };
      
      # Git status - simple text indicators, no icons
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
      
      # Nix shell - simple, no icons
      nix_shell = {
        style = "bright-blue";
        format = "[nix:$state]($style) ";
        impure_msg = "impure";
        pure_msg = "pure";
        unknown_msg = "unknown";
      };
      
      # Command duration - show if command took longer than threshold
      cmd_duration = {
        min_time = 1000; # Only show if command took 1+ seconds (1000ms)
        format = "[$duration]($style) ";
        style = "bright-blue";
      };
      
      # Jobs - show number of background jobs
      jobs = {
        format = "[$number]($style) ";
        style = "bright-blue";
      };
      
      # Python version
      python = {
        format = "[py $version]($style) ";
        style = "bright-blue";
        version_format = "v$${raw}";
      };
      
      # Node.js version
      nodejs = {
        format = "[node $version]($style) ";
        style = "bright-blue";
        version_format = "v$${raw}";
      };
      
      # Rust version
      rust = {
        format = "[rust $version]($style) ";
        style = "bright-blue";
        version_format = "v$${raw}";
      };
      
      # Go version
      golang = {
        format = "[go $version]($style) ";
        style = "bright-blue";
        version_format = "v$${raw}";
      };
      
      # Disable other modules to keep prompt clean
      git_metrics.disabled = true;
      localip.disabled = true;
      time.disabled = true;
      battery.disabled = true;
      username.disabled = true;
      sudo.disabled = true;
    };
  };

  # Modern "must-haves" for NixOS
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

  # Better 'cat'
  programs.bat.enable = true;
}
