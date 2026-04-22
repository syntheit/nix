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
    prefix = "C-Space";

    extraConfig = ''
      # True color support
      set -as terminal-features ",xterm-256color:RGB"

      # OSC 52 clipboard — enables copy/paste between tmux and terminal (ghostty)
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

      # ── Prefix bindings (Ctrl-Space then key) ──
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # ── Direct Alt bindings (no prefix needed) ──
      # Pane navigation
      bind -n M-h select-pane -L
      bind -n M-j select-pane -D
      bind -n M-k select-pane -U
      bind -n M-l select-pane -R

      # Splits
      bind -n M-v split-window -h -c "#{pane_current_path}"
      bind -n M-- split-window -v -c "#{pane_current_path}"

      # Windows (tabs)
      bind -n M-t new-window -c "#{pane_current_path}"
      bind -n M-w kill-pane
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-n next-window
      bind -n M-p previous-window

      # Resize panes
      bind -n M-H resize-pane -L 5
      bind -n M-J resize-pane -D 5
      bind -n M-K resize-pane -U 5
      bind -n M-L resize-pane -R 5

      # Zoom (toggle fullscreen pane)
      bind -n M-f resize-pane -Z

      # Detach
      bind -n M-d detach-client
    '';
  };
}
