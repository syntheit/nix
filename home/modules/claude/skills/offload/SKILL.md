---
name: offload
description: Hand token-heavy, easy-to-verify work to cheap non-Claude models (GLM, Kimi, DeepSeek, Qwen via OpenRouter) with the `offload` CLI to save Claude usage. Use for codebase recon, docs/web research, build or test log triage, second opinions on a plan, and tightly specified mechanical edits. Also when the user says "offload", "cheap model", or names GLM/Kimi/DeepSeek/Qwen.
---

# offload

Claude usage is the scarce resource; OpenRouter tokens cost cents. Every file, page, or log you read stays in your context and is paid for again on every later turn. Delegate the reading, keep the judgment.

## Delegate when the answer is cheap to verify

| Work | Command | Then you |
|---|---|---|
| Recon: where is X handled, what calls Y | `offload ask "List file:line locations where ... One line each with a short reason."` | Read only the cited lines |
| Docs, changelogs, web research | `offload ask "... Cite a URL for every claim."` | Spot-check a source before relying on it |
| Build/test log triage | `cmd 2>&1 \| offload ask -i "Quote the first real error and its likely cause."` | Confirm against the quoted lines |
| Second opinion on a plan | `offload ask -m kimi -f plan.md "Find flaws in this plan ..."` | Weigh it; you decide |
| Mechanical edit with a precise spec | `offload ask -e "..."`, then `git diff` | Review the diff, run tests |
| Diff review | the `cheap-review` skill | Verify each finding |

## Keep on Claude

Design decisions, tricky debugging, security-sensitive changes, anything where checking the answer costs as much as producing it, and final verification.

## Rules

- Prompts must be self-contained: the model sees only the prompt, files attached with `-f`, and the repo in the current directory. Name files, symbols, and the exact output format. Ask for short output.
- Treat answers like a junior's report: verify what you act on, never relay them to the user as fact.
- Models (`offload models`): `glm` default, strongest open coder; `deepseek`, `mimo`, `minimax` cheap; `qwen` multilingual; `coder` cheap recon; `kimi` deep research only (slow, $0.20-0.50 per agentic run).
- Read-only unless `-e`. Use `-e` only for bounded tasks in a clean git tree, so `git diff` shows exactly what it did.
- Cost and time print to stderr: a typical ask is $0.001-0.05 and 10-120 s. Run independent asks in parallel (background Bash) when useful.
- Code is sent to third-party model providers. Do not offload employer or client code unless the user has said that is allowed for that repo.
- If a run fails or answers nonsense, retry at most once, then do the task yourself.
