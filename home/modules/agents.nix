# agents — Claude Code setup shared by every host.
#
# Skills and global rules live in ../../agent-kit, published as a plugin
# marketplace straight from this repo on GitHub (syntheit/nix; the manifest is
# /.claude-plugin/marketplace.json). Claude Code fetches it itself, so adding
# or editing a skill is commit + push + `kit-sync`, not a rebuild. This module
# only points it at the marketplace.
#
# settings.json is runtime-owned (/model, /config, project trust and plugin
# state are written back to it), so it is merged, not linked: the keys below
# win, everything else is left alone.
{
  lib,
  pkgs,
  ...
}:
let
  repo = "syntheit/nix";

  claudeManaged = pkgs.writeText "claude-managed.json" (
    builtins.toJSON {
      extraKnownMarketplaces.syntheit = {
        source = {
          source = "github";
          inherit repo;
        };
        autoUpdate = false; # kit-sync updates on demand
      };
      enabledPlugins = {
        "kit@syntheit" = true;
        "impeccable@syntheit" = true;
      };
      # No Claude attribution anywhere: no Co-Authored-By trailer in commits,
      # no "Generated with Claude Code" in PRs, no session link.
      attribution = {
        commit = "";
        pr = "";
        sessionUrl = false;
      };
    }
  );

  # Pull the latest agent-kit on every host. Hosts that are off or
  # unreachable are reported and skipped; rerun later.
  kitHosts = [
    "mantle"
    "ledger"
    "vista"
    "harbor"
    "swift"
    "mini"
    "raven"
    "fajita"
  ];
  kit-sync = pkgs.writeShellApplication {
    name = "kit-sync";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # install is a no-op once installed and update a failure before, so run
      # both. Expands on the target.
      # shellcheck disable=SC2016
      update='set -e
        claude plugin marketplace update syntheit >/dev/null 2>&1 ||
          claude plugin marketplace add ${repo} >/dev/null
        for p in kit impeccable; do
          claude plugin install "$p@syntheit" >/dev/null 2>&1 || true
          claude plugin update "$p@syntheit" >/dev/null
        done'
      hosts=("$@")
      [ ''${#hosts[@]} -gt 0 ] || hosts=(${lib.concatStringsSep " " kitHosts})
      out=$(mktemp -d)
      trap 'rm -rf "$out"' EXIT
      self=$(uname -n)
      self=''${self%%.*}
      for h in "''${hosts[@]}"; do
        if [ "$h" = "$self" ]; then
          ''${SHELL:-sh} -lc "$update" >"$out/$h" 2>&1 && touch "$out/$h.ok" &
        else
          ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" "exec \''${SHELL:-sh} -lc '$update'" \
            >"$out/$h" 2>&1 && touch "$out/$h.ok" &
        fi
      done
      wait
      fail=0
      for h in "''${hosts[@]}"; do
        if [ -e "$out/$h.ok" ]; then
          echo "✓ $h"
        else
          fail=1
          echo "✗ $h: $(tail -n 1 "$out/$h")"
        fi
      done
      echo "New sessions use the update; in an open session run /reload-plugins."
      exit "$fail"
    '';
  };
in
{
  home.packages = [ kit-sync ];

  home.activation.agentsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_settings="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude"
    [ -s "$claude_settings" ] || run sh -c "echo '{}' > \"$claude_settings\""
    # The i-have-adhd plugin is replaced by the kit's rules.md.
    run sh -c '${pkgs.jq}/bin/jq -s ".[0] * .[1]
        | del(.enabledPlugins[\"i-have-adhd@i-have-adhd\"], .extraKnownMarketplaces[\"i-have-adhd\"])" \
      "$1" ${claudeManaged} > "$1.tmp" && mv "$1.tmp" "$1"' _ "$claude_settings"
  '';
}
