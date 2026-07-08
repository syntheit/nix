{
  pkgs,
  config,
  vars,
  lib,
  hostName ? "unknown",
  ...
}:
let
  # Remote-dev session commands: one letter per host. Each opens/attaches a
  # tmux session on that host (default session "1"; an arg naming a dir under
  # ~/Projects auto-cds there; "nix" -> ~/nix).
  sessionHosts = {
    h = "harbor";
    m = "mantle";
    r = "raven";
    v = "vista";
  };

  # swift roams (cafe wifi) -> mosh; the LAN machines talk over plain ssh.
  # harbor is remote for everyone, so it is always mosh.
  transportFor = target: if hostName == "swift" || target == "harbor" then "mosh" else "ssh";

  mkSessionFn =
    letter: target:
    let
      launch = if transportFor target == "mosh" then "mosh ${target} -- bash -c" else "ssh -t ${target}";
    in
    ''
      ${letter}() {
        local name="''${1:-1}"
        ${launch} "
          case $name in
            nix) cd ~/nix ;;
            *)   [ -d ~/Projects/$name ] && cd ~/Projects/$name ;;
          esac
          exec tmux new-session -A -s $name
        "
      }
    '';

  # a command for every host except the one we are sitting on
  otherHosts = lib.filterAttrs (_letter: target: target != hostName) sessionHosts;
  sessionFns = lib.concatStringsSep "\n" (lib.mapAttrsToList mkSessionFn otherHosts);
  sessionCheat = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      letter: target: "  ${letter} / ${letter} work        ${target} session (${transportFor target})"
    ) otherHosts
  );
in
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

      # --- Remote dev shortcuts (generated per-host from sessionHosts) ---
      # <letter> [name] — open/attach tmux session <name> on that host.
      #   default session "1"; name = dir under ~/Projects auto-cds; "nix" -> ~/nix
      # Transport per host: swift uses mosh (it roams); LAN machines use ssh;
      # harbor is always mosh. No command is defined for the host you're on.
      ${sessionFns}

      cheat() {
        cat <<'CHEAT'
  ── Remote Dev (from ${hostName}) ───────────────────
${sessionCheat}
  <letter> [name]   default session "1"; name = dir in ~/Projects (auto-cd)
  Shift+Cmd+X       screenshot → harbor:~/screenshots/swift/

  ── Tmux (no prefix needed) ─────────────────────────
  Alt-h/j/k/l       navigate panes
  Alt-H/J/K/L       resize panes
  Alt-v             split vertical
  Alt--             split horizontal
  Alt-t             new window (tab)
  Alt-1..5          switch to window N
  Alt-n / Alt-p     next / prev window
  Alt-w             close pane
  Alt-f             toggle pane fullscreen
  Ctrl-Space [      scroll mode (q to exit)

  ── Dev Servers (from Air browser) ──────────────────
  http://harbor:PORT    any port, auto-exposed via Tailscale
  Dev servers must bind to 0.0.0.0 (not 127.0.0.1)

  ── Emergency ───────────────────────────────────────
  emergency-push              push all dirty repos
  emergency-push my-app       push one repo

  ── Project Setup ───────────────────────────────────
  echo "use flake" > .envrc && direnv allow
CHEAT
      }

      # --- Cursor shape (blinking underline) ---
      printf '\e[3 q'

      # --- Transient prompt ---
      # After pressing Enter, previous prompts collapse to a minimal ❯
      # Keeps scrollback clean: just commands and output, no prompt noise
      zle-line-init() {
        emulate -L zsh
        [[ $CONTEXT == start ]] || return 0

        printf '\e[3 q'

        while true; do
          zle .recursive-edit
          local -i ret=$?
          [[ $ret == 0 && $KEYS == $'\4' ]] || break
          [[ -o ignore_eof ]] || exit 0
        done

        local saved_prompt=$PROMPT
        local saved_rprompt=$RPROMPT
        PROMPT='%(?.%F{green}❯%f .%F{red}❯%f )'
        RPROMPT=""
        zle .reset-prompt
        PROMPT=$saved_prompt
        RPROMPT=$saved_rprompt

        if (( ret )); then
          zle .send-break
        else
          zle .accept-line
        fi
        return ret
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
      continuation_prompt = "[∙](dimmed white) ";

      format = "$nix_shell$directory$git_branch$git_status$character";
      right_format = "$jobs$cmd_duration";

      character = {
        format = "$symbol ";
        success_symbol = "[❯](green)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
        vimcmd_replace_one_symbol = "[❯](purple)";
        vimcmd_replace_symbol = "[❯](purple)";
        vimcmd_visual_symbol = "[❯](yellow)";
      };

      directory = {
        home_symbol = "~";
        truncation_length = 3;
        truncation_symbol = "…/";
        read_only = " 󰌾";
        use_os_path_sep = true;
        style = lib.mkDefault "blue";
        format = "[$path]($style)[$read_only](red) ";
        # Repo root pops in bold, parent path fades back
        repo_root_style = lib.mkDefault "bold blue";
        before_repo_root_style = lib.mkDefault "dimmed blue";
        repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)[$read_only](red) ";
      };

      git_branch = {
        format = "[$symbol$branch(:$remote_branch)]($style) ";
        symbol = "";
        style = "purple";
        truncation_symbol = "…";
        only_attached = true;
      };

      # Color-coded status: green=staged, yellow=modified, red=conflict/delete, dimmed=untracked
      git_status = {
        format = "([\\[$all_status$ahead_behind\\]](242) )";
        conflicted = "[=$count](red)";
        ahead = "[⇡$count](green)";
        behind = "[⇣$count](yellow)";
        diverged = "[⇡$ahead_count⇣$behind_count](red)";
        untracked = "[?$count](dimmed)";
        stashed = "[*$count](cyan)";
        modified = "[!$count](yellow)";
        staged = "[+$count](green)";
        renamed = "[»$count](cyan)";
        deleted = "[✕$count](red)";
      };

      nix_shell = {
        format = "[$symbol]($style) ";
        symbol = "";
        style = "cyan";
      };

      cmd_duration = {
        min_time = 1000;
        format = "[$duration]($style) ";
        style = "yellow";
      };

      jobs = {
        format = "[✦ $number]($style) ";
        style = "blue";
      };

      python.disabled = true;
      nodejs.disabled = true;
      rust.disabled = true;
      golang.disabled = true;

      git_metrics.disabled = true;
      localip.disabled = true;
      time.disabled = true;
      battery.disabled = true;
      username.disabled = true;
      hostname.disabled = true;
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
    NIX_BUILD_SHELL = toString (pkgs.writeShellScript "nix-shell-zsh" ''
      if [ "$1" = "--rcfile" ]; then
        source "$2"
        exec zsh
      fi
      exec zsh "$@"
    '');
  };

  # Extra completion definitions for hundreds of commands
  home.packages = [ pkgs.zsh-completions ];
}
