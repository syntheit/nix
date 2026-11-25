# tmux-msg: type a one-line note into another Claude Code session's tmux pane, on any host.
# Packaged by agents.nix (writeShellApplication adds the shebang and strict mode).
usage() {
  cat <<'EOF'
tmux-msg <host|local> <to: chat title> <from: your chat title> <message...>
tmux-msg <host|local> --list          list chat titles on that host

Types a one-line message into another Claude Code session's tmux pane and presses Enter.
The receiver sees it as a user prompt, so it is stamped "[msg from <from>@<this host>]".
The pane is found by chat title (pane title minus the status glyph), not by id.
Refuses (exit 2) while the target shows a dialog, so the Enter can't answer it; retry later.

  tmux-msg raven Clothing Dpto "deploying construct now, hold PUTs ~5 min"
  tmux-msg harbor Dpto Clothing "scrape finished, harbor's Ad Library IP is yours"
EOF
}

[ $# -ge 2 ] || { usage; exit 1; }
host=$1 to=$2

run() {
  if [ "$host" = local ]; then
    bash -c "$1"
  else
    # shellcheck disable=SC2029  # expanded here on purpose; the command is quoted with %q
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" "bash -c $(printf %q "$1")"
  fi
}
titles() { awk -F'\t' '{t=$3; sub(/^[^ ]+ /, "", t); print t "\t" $1 "\t" $2}'; }

panes=$(run "tmux list-panes -a -F '#{pane_id}	#{pane_current_command}	#{pane_title}'")
if [ "$to" = --list ]; then
  printf '%s\n' "$panes" | titles | column -t -s $'\t'
  exit 0
fi

[ $# -ge 4 ] || { usage; exit 1; }
from=$3
shift 3
msg="[msg from $from@$(uname -n)] $*"
msg=${msg//$'\n'/ }

ids=$(printf '%s\n' "$panes" | titles | awk -F'\t' -v t="$to" '$1 == t {print $2}')
n=$(printf '%s' "$ids" | grep -c . || true)
if [ "$n" != 1 ]; then
  echo "tmux-msg: $n panes titled '$to' on $host; titles there:" >&2
  printf '%s\n' "$panes" | titles | cut -f1 | sed 's/^/  /' >&2
  exit 1
fi
pane=$ids

screen=$(run "tmux capture-pane -p -t $pane" | grep -v '^[[:space:]]*$' | tail -15)
if printf '%s' "$screen" | grep -Eq 'Do you want|Esc to cancel|Would you like|❯ 1\.'; then
  echo "tmux-msg: '$to' on $host has a dialog open; not sending. Retry in a minute." >&2
  exit 2
fi

run "tmux send-keys -t $pane -l $(printf %q "$msg") && sleep 0.5 && tmux send-keys -t $pane Enter"
echo "tmux-msg: sent to '$to' ($pane) on $host"
