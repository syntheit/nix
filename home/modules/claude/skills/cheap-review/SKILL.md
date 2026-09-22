---
name: cheap-review
description: Multi-model code review of the current changes on cheap non-Claude models - 3 to 5 reviewers with different lenses run in parallel, their findings are merged, and Claude verifies only the shortlist. Use before committing non-trivial changes, when the user asks for a review or second opinion, or wherever Codex reviews were used before.
---

# cheap-review

1. Scope: by default uncommitted changes (including untracked files), or the last commit if the tree is clean. `-b <ref>` reviews `git diff <ref>`, e.g. `-b main` for a branch. `-p <path>` (repeatable) limits it to your files; use it when unrelated changes are staged.
2. Run it. It takes about 5-8 minutes, so run it in the background if you have other work:
   `offload review [-n 3] [-b BASE] [-p PATH]... ["extra focus"]`
   - `-n 3` (default): correctness (GLM-5.2), security (Qwen3.8-max), integration (MiniMax M3).
   - `-n 5` adds edge cases (GLM-5.3) and simplification (Qwen3-Coder). Use it for large changes.
3. Verify every finding before reporting it: open the cited location and trace the failure scenario. Findings from two or more reviewers are more often real, but check them too. Cheap models produce false positives, and filtering them is your job.
4. Report only confirmed findings (location, problem, failure scenario) and one line saying how many you discarded. Fix only if the user asked.
5. Record the verdict so the user can see whether this is worth its cost: `offload note "review <scope>: N confirmed, M discarded"`.

The merged list prints to stdout. Per-reviewer files are in the printed directory if a finding is unclear. Code goes to third-party providers (OpenRouter); Daniel has approved that for his own and his company's repos.
