{ pkgs, lib, ... }:

{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    mouse = true;
    escapeTime = 10; # Low escape-time for responsive neovim mode switching
    historyLimit = 50000;
    baseIndex = 1;
    keyMode = "vi";

    extraConfig = ''
      # True color support
      set -as terminal-features ",xterm-256color:RGB"

      # OSC 52 clipboard — enables copy/paste between tmux and kitty
      set -g set-clipboard on
      set -g allow-passthrough on
      # Force tmux to use the 'c' (clipboard) selection for OSC 52.
      # Mosh 1.4.0 only accepts "52;c;" — other selection types are silently dropped.
      set -ag terminal-overrides ",xterm-256color:Ms=\\E]52;c;%p2%s\\7"

      # Renumber windows when one is closed
      set -g renumber-windows on

      # Status bar — minimal, just session name and window list
      set -g status-style "bg=default,fg=white"
      set -g status-left "#[bold blue]#S #[default]"
      set -g status-left-length 20
      set -g status-right ""
      set -g window-status-current-style "bold"
      set -g window-status-format "#[dim]#I:#W"
      set -g window-status-current-format "#I:#W"

      # Pane borders
      set -g pane-border-style "fg=brightblack"
      set -g pane-active-border-style "fg=blue"

      # Intuitive splits (| and -)
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # New windows inherit current directory
      bind c new-window -c "#{pane_current_path}"

      # Vim-style pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Pane resizing (repeatable)
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5
    '';
  };
}
