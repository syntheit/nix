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
| Docs, changelogs, web research | `offload ask -w "... Cite a URL for every claim."` | Spot-check a source before relying on it |
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
- Modes: default reads the repo in the current directory (no shell, no web); `-w` does web research with no repo access; `-e` can edit and run commands. Use `-e` only for bounded tasks in a clean git tree, so `git diff` shows exactly what it did.
- Cost and time print to stderr. Run independent asks in parallel (background Bash) when useful.

## Backends and cost

`offload mode` shows which backend runs the work; `offload mode <auto|codex|openrouter|claude>` switches it. Default is `auto`: Codex first, OpenRouter if Codex fails.

- **Codex is flat-rate** — no per-run cost, so prefer it and don't ration it.
- **OpenRouter is metered.** An ask is $0.001–0.05. A 3-model review of a large diff is $0.20–0.45, and a day of heavy reviewing ran to $9. On this backend: scope the diff with `-p`, use `-n 2` for changes under ~200 lines, don't re-review unchanged code, and prefer `glm`/`minimax` over `qwen` (the priciest).
- **`claude` mode** makes offload refuse with exit 3. That is the user telling you to do the work yourself — do it, don't work around it.
- If the user says OpenRouter credit is running low, suggest `offload mode codex`. Check spend with `offload stats 1`.
- Code is sent to third-party model providers (OpenRouter). Daniel has approved this for his own and his company's repos. Ask first only for someone else's code, e.g. a client's private repo.
- If a run fails or answers nonsense, retry at most once, then do the task yourself, and record it: `offload note "ask <topic>: wrong answer, did it myself"`.
- Every run is logged to `~/.local/state/offload/log.tsv`. `offload log [N]` lists recent runs; `offload stats [DAYS]` totals cost by model and shows quality notes. Use them when the user asks whether this is working.
