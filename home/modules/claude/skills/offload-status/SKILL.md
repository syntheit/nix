---
name: offload-status
description: Summarize how cheap-model offloading is going - how much work went to GLM/Qwen/MiniMax, what it cost, how often it failed, and whether the answers held up. Use when the user asks "is offload working", "how is it going", "what am I spending on AI", or asks to see the offload log.
---

# offload-status

Give a TLDR, not a table dump. Four numbers and a verdict.

1. Gather (all cheap, no model calls):
   - `offload stats 7` and `offload stats 1` — runs, spend, failures, by-model, quality notes
   - `offload log 15` — what the recent runs were actually for
   - OpenRouter balance: `curl -s https://openrouter.ai/api/v1/credits -H "Authorization: Bearer $(cat /run/secrets/openrouter_key)" | jq -r '.data | "$\(.total_credits - .total_usage)"'` (Linux; on macOS the key is in `~/.local/share/opencode/auth.json`). Skip it silently if the key isn't readable.
2. Report exactly this shape, one line each:
   - **Volume:** N runs in 7 days (M today), mostly <what for, from the log>
   - **Cost:** $X in 7 days, ≈$Y/day. Balance $Z (flag if under $5)
   - **Reliability:** N failed or timed out, on <model> (say "none" when clean)
   - **Quality:** from the notes — confirmed vs discarded findings, wrong answers. Say "no notes yet" rather than guessing.
   - **Verdict:** one sentence. Is this saving Claude usage or not?
3. Add at most one recommendation, and only if the data supports it: drop a model that keeps failing, run reviews more often, top up the balance, or nothing.

Rules:
- Zero runs means it isn't being used. Say so plainly rather than reporting a clean $0. Then say why, if you can tell: no eligible work, or Claude not reaching for the skills.
- Never guess at Claude-side savings. That number lives in `/usage`, which you cannot read. Say the user should compare it themselves.
- Keep the whole report under 10 lines. Offer details only if asked.
