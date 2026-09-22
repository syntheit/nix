# offload — let Claude Code hand token-heavy work to cheap OpenRouter models.
#
# Installs the `offload` CLI (packages/offload) plus two Claude Code skills and a
# short global CLAUDE.md telling Claude to use them. Needs opencode.nix (headless
# `opencode run` with the `inspect` agent does the work).
#
# ~/.claude/CLAUDE.md becomes a read-only store symlink: edit it here, not with
# Claude's /memory.
{ pkgs, ... }:
{
  home.packages = [ pkgs.offload ];

  home.file = {
    ".claude/skills/offload/SKILL.md".source = ./claude/skills/offload/SKILL.md;
    ".claude/skills/cheap-review/SKILL.md".source = ./claude/skills/cheap-review/SKILL.md;
    ".claude/CLAUDE.md".source = ./claude/CLAUDE.md;
  };
}
