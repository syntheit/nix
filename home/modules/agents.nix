# agents — Claude Code + Codex setup shared by every host.
#
# Skills and global rules live in ../../agent-kit, published as a plugin
# marketplace straight from this repo on GitHub (syntheit/nix; the manifests are
# /.claude-plugin/marketplace.json and /.agents/plugins/marketplace.json). Both
# tools fetch it themselves, so adding or editing a skill is commit + push +
# `kit-sync`, not a rebuild. This module only points them at the marketplace.
#
# settings.json and config.toml are runtime-owned (/model, /config, project
# trust and plugin state are written back to them), so they are merged, not
# linked: the keys below win, everything else is left alone.
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
    }
  );

  codexManaged = pkgs.writeText "codex-managed.json" (
    builtins.toJSON {
      marketplaces.syntheit = {
        source_type = "git";
        source = "https://github.com/${repo}";
        sparse_paths = [
          ".agents"
          "agent-kit"
        ];
      };
      plugins."kit@syntheit".enabled = true;
    }
  );

  # Deep-merge a JSON patch into a TOML file (patch wins), keeping mode 0600.
  mergeToml = pkgs.writers.writePython3 "merge-toml" { libraries = [ pkgs.python3Packages.tomli-w ]; } ''
    import json
    import os
    import sys
    import tomllib

    import tomli_w

    path, patch_path = sys.argv[1], sys.argv[2]


    def merge(a, b):
        for k, v in b.items():
            if isinstance(v, dict) and isinstance(a.get(k), dict):
                merge(a[k], v)
            else:
                a[k] = v
        return a


    cur = {}
    if os.path.exists(path):
        with open(path, "rb") as f:
            cur = tomllib.load(f)
    with open(patch_path) as f:
        merge(cur, json.load(f))
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with open(fd, "wb") as f:
        tomli_w.dump(cur, f)
    os.replace(tmp, path)
  '';

  # Pull the latest agent-kit on every host (and install it on Codex, which
  # needs one `plugin add` per machine). Hosts that are off or unreachable
  # are reported and skipped; rerun later.
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
      # both. Codex never installs from config.toml alone; `plugin add` is
      # idempotent and re-copies the upgraded snapshot. Expands on the target.
      # shellcheck disable=SC2016
      update='set -e
        claude plugin marketplace update syntheit >/dev/null 2>&1 ||
          claude plugin marketplace add ${repo} >/dev/null
        for p in kit impeccable; do
          claude plugin install "$p@syntheit" >/dev/null 2>&1 || true
          claude plugin update "$p@syntheit" >/dev/null
        done
        if command -v codex >/dev/null; then
          codex plugin marketplace upgrade syntheit >/dev/null
          codex plugin add kit@syntheit >/dev/null
        fi'
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

  # Codex skips plugin hooks until trusted on each machine, so its rules come
  # from a plain file instead of the kit's session-start hook.
  home.file.".codex/AGENTS.md".source = ../../agent-kit/AGENTS.md;

  home.activation.agentsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_settings="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude" "$HOME/.codex"
    [ -s "$claude_settings" ] || run sh -c "echo '{}' > \"$claude_settings\""
    # The i-have-adhd plugin is replaced by the kit's rules.md.
    run sh -c '${pkgs.jq}/bin/jq -s ".[0] * .[1]
        | del(.enabledPlugins[\"i-have-adhd@i-have-adhd\"], .extraKnownMarketplaces[\"i-have-adhd\"])" \
      "$1" ${claudeManaged} > "$1.tmp" && mv "$1.tmp" "$1"' _ "$claude_settings"
    run ${mergeToml} "$HOME/.codex/config.toml" ${codexManaged}
  '';
}
