---
name: handoff
description: Write a handoff doc to /tmp and print a one-line prompt that starts a fresh agent on the same work. Use when the user says "handoff", "hand this off", "write a handoff", or wants to continue in a new session or with another agent.
argument-hint: "[what the next session should focus on]"
---

Write everything a fresh agent needs to continue this work into one markdown
file, then give the user a one-line prompt to paste into the new session.

The next agent starts with zero context: it has not seen this conversation,
and it may be a different model or tool (Claude Code or Codex). It runs on
this same machine, so it can read the file and the repo.

## 1. Write the file

Path: `/tmp/handoff-<slug>-<YYYYMMDD-HHMM>.md`, where `<slug>` is 2-4 words
naming the work (e.g. `harbor-couchdb-backup`). Never write it inside the
repo.

Sections, in this order. Omit a section only if it would be empty.

- **Goal** — what the user is ultimately trying to get, in 1-3 sentences. If
  the user passed arguments, they describe what the next session should focus
  on: put that first.
- **State** — what is done and verified (and how it was verified), what is
  done but unverified, what is in progress. Name the git branch and whether
  changes are committed, pushed, or only in the working tree.
- **Key files** — `path:line` for each file that matters, with one line on
  why.
- **Decisions** — choices already made and the reason for each, including
  options the user rejected, so the next agent does not reopen them.
- **Dead ends** — what was tried and failed, with the exact error, so it is
  not retried.
- **Next steps** — numbered. Step 1 is concrete enough to start immediately.
- **Verify** — the exact commands that prove the work is done.
- **Open questions** — anything waiting on the user.

Rules:

- Point to existing artifacts (commits, plans, specs, PRs, other files) by
  path or URL instead of copying them.
- Include exact commands, paths, hostnames, and error messages. Paraphrase
  nothing the next agent will need to run or grep for.
- Redact secrets: tokens, passwords, keys, and private personal data.
- Keep it as short as completeness allows. The next agent pays for every line.

## 2. Reply with the one-liner

The reply is only this, nothing before or after:

````
Handoff written: /tmp/handoff-<slug>-<YYYYMMDD-HHMM>.md

```
Read /tmp/handoff-<slug>-<YYYYMMDD-HHMM>.md and continue from "Next steps".
```
````

If the user named a focus, append it to the one-liner as a second sentence.
