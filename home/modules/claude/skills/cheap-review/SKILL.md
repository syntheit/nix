---
name: cheap-review
description: Multi-model code review of the current changes on cheap non-Claude models - 3 to 5 reviewers with different lenses run in parallel, their findings are merged, and Claude verifies only the shortlist. Use before committing non-trivial changes, when the user asks for a review or second opinion, or wherever Codex reviews were used before.
---

# cheap-review

1. Scope: by default uncommitted changes (including untracked files), or the last commit if the tree is clean. `-b <ref>` reviews `git diff <ref>`, e.g. `-b main` for a branch. `-p <path>` (repeatable) limits it to your files; use it when unrelated changes are staged.
2. Run it. It takes 1-5 minutes, so run it in the background if you have other work:
   `offload review [-n 3] [-b BASE] [-p PATH]... ["extra focus"]`
   - `-n 3` (default): correctness (GLM-5.2), integration (MiMo), edge cases (DeepSeek).
   - `-n 5` adds security (Qwen) and simplification (MiniMax). Use it for large or security-sensitive changes.
3. Verify every finding before reporting it: open the cited location and trace the failure scenario. Findings from two or more reviewers are more often real, but check them too. Cheap models produce false positives, and filtering them is your job.
4. Report only confirmed findings (location, problem, failure scenario) and one line saying how many you discarded. Fix only if the user asked.

The merged list prints to stdout. Per-reviewer files are in the printed directory if a finding is unclear. Code goes to third-party providers: do not run this on employer or client code unless the user has said that is allowed for that repo.
