# agent-kit

Skills and global rules for Claude Code on every host. This repo is
itself the plugin marketplace (`/.claude-plugin/marketplace.json`); Claude
Code fetches it from GitHub (`syntheit/nix`), so nothing here goes through a
Nix rebuild. `home/modules/agents.nix` points each host at the marketplace.

| Path | What |
|---|---|
| `skills/<name>/SKILL.md` | One skill per folder. Claude: `/handoff` (or `/kit:handoff`). |
| `rules.md` | Global rules, injected into every Claude session by `claude-hooks.json`. Max 10,000 characters. |
| `../.claude-plugin/marketplace.json` | Also lists third-party plugins (impeccable), pinned by `sha`. |

## Change something

1. Add or edit a skill folder, `rules.md`, or a marketplace entry.
2. Commit and push.
3. Run `kit-sync` (all hosts) or `kit-sync vista mini` (some). Open sessions
   need `/reload-plugins`.

## Vendored skills

Copied, not fetched; refresh by copying the upstream folder again.

| Skill | Upstream | Commit | License |
|---|---|---|---|
| humanizer | https://github.com/blader/humanizer | 225a6f39 | MIT |
| security-audit | https://github.com/cloudflare/security-audit-skill (`skills/security-audit`, tests dropped) | c1c8a8c1 | MIT |
| rules.md output style | https://github.com/ayghri/i-have-adhd | 839872f9 | MIT |
