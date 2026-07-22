# opencode — terminal AI coding + research agent, open models via OpenRouter.
#
# Declarative config → ~/.config/opencode/ (home-manager programs.opencode).
# The OpenRouter API key is never in Nix: opencode reads it at runtime from the
# sops-decrypted file via {file:...} (secret per-host in hosts/*/secrets.nix).
#
# Two gears:
#   `build`       — inline agent for quick work (auto-runs, with guardrails)
#   `orchestrate` — commander for big/long jobs: it CANNOT edit or run bash, so it
#                   must decompose the work and delegate plan→implement→review to
#                   subagents (in parallel), keeping its own context lean.
#
# Model tiers:
#   commander / plan / implement / review → GLM-5.2   ($0.93/$3)
#   broad research fan-out (`general`)    → GLM-4.7-Flash ($0.06/$0.40)
#   code recon (`explore`/`scout`)        → Qwen3-Coder-Next ($0.11/$0.80)
#   deep/trust-critical (`@research`)     → Kimi K3    ($3/$15), cites sources
#
# Web search: Exa via OPENCODE_ENABLE_EXA (free, no key), wrapped onto the binary.
{ pkgs, lib, ... }:
let
  commander = "openrouter/z-ai/glm-5.2";
  reader = "openrouter/z-ai/glm-4.7-flash";
  coder = "openrouter/qwen/qwen3-coder-next";
  researcher = "openrouter/moonshotai/kimi-k3";

  # Auto-run bash so the flow doesn't stall on every command, but still ASK before
  # anything irreversible or system-level. Last matching pattern wins.
  safeBash = {
    "*" = "allow";
    "rm *" = "ask";
    "rmdir *" = "ask";
    "sudo *" = "ask";
    "git push*" = "ask";
    "git reset --hard*" = "ask";
    "git clean*" = "ask";
    "nixos-rebuild*" = "ask";
    "home-manager*" = "ask";
    "dd *" = "ask";
    "mkfs*" = "ask";
    "chmod -R*" = "ask";
    "chown -R*" = "ask";
    "shutdown*" = "ask";
    "reboot*" = "ask";
  };
in
{
  programs.opencode = {
    enable = true;

    # Always launch with Exa websearch enabled (free, no API key).
    package = pkgs.symlinkJoin {
      name = "opencode-websearch";
      paths = [ pkgs.opencode ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/opencode --set-default OPENCODE_ENABLE_EXA 1
      '';
    };

    # Global rules — loaded into every agent, every session, every dir.
    context = ''
      # Operating rules for all agents

      ## Source-grounding (non-negotiable)
      For anything involving current facts, products, prices, people, libraries, or
      the outside world: use the `websearch` and `webfetch` tools and ground every
      claim in real sources. Do NOT answer factual or current-information questions
      from training memory. Cite the source URL after each claim. If you cannot find a
      source, say so plainly rather than guessing.

      ## Model routing — delegate to the cheapest tier that does the job well
      - Broad research / "learn a lot" / skim many sources  -> `general` subagent (cheap; parallel).
      - Reading or exploring a codebase                      -> `explore` / `scout`.
      - Deep, trust-critical research                        -> `research` subagent (`@research`).
      Prefer breadth on the cheap tier; escalate only when needed.
    '';

    settings = {
      autoupdate = false;
      model = commander;
      small_model = reader;

      # Linux hosts read the key from the sops-decrypted file. On darwin the
      # sops secrets path isn't wired yet, so omit apiKey there and let opencode
      # use `opencode auth login` (auth.json) until the darwin path is verified.
      provider.openrouter.options = lib.optionalAttrs pkgs.stdenv.isLinux {
        apiKey = "{file:/run/secrets/openrouter_key}";
      };

      agent = {
        # ── Primaries (Tab cycles between them) ──

        # Quick inline work — auto-runs with guardrails ("auto mode").
        build = {
          mode = "primary";
          model = commander;
          permission = {
            edit = "allow";
            bash = safeBash;
          };
        };

        # Read-only planning mode (its whole point).
        plan = {
          mode = "primary";
          model = commander;
          permission = {
            edit = "deny";
            bash = "deny";
          };
        };

        # THE ORCHESTRATOR — no edit/bash, so it MUST delegate. Talk to this for
        # big/long jobs; it keeps a lean context and runs the circus.
        orchestrate = {
          mode = "primary";
          model = commander;
          description = "Commander: decomposes work and delegates plan->implement->review to subagents, in parallel. Does not implement directly.";
          permission = {
            edit = "deny";
            bash = "deny";
            task = "allow";
          };
          prompt = ''
            You are an orchestrator, not an implementer. You have no edit or bash
            tools — you CANNOT write code or run commands, so you must delegate all
            execution.

            Break the user's request into independent tasks. For each task, delegate
            in order:
              1. `planner`     — design the approach
              2. `implementer` — build it per the plan
              3. `reviewer`    — check the result
            Run independent tasks in parallel when they don't depend on each other.
            Keep your own context on the task list, the plans, and each subagent's
            summary — do NOT pull raw file contents into your context; that's what the
            subagents' own context windows are for. Integrate their results and report
            back concisely, flagging anything the reviewer failed.
          '';
        };

        # ── Role subagents (used by the orchestrator) ──

        planner = {
          mode = "subagent";
          model = commander;
          description = "Designs the approach for a single task (no implementation).";
          permission = {
            edit = "deny";
            bash = "deny";
          };
          prompt = ''
            You design the approach for ONE task: the concrete steps, the files to
            touch, and the key decisions/tradeoffs. Do not implement — return a clear,
            actionable plan.
          '';
        };

        implementer = {
          mode = "subagent";
          model = commander;
          description = "Implements a single task per a plan (edits files, runs commands).";
          permission = {
            edit = "allow";
            bash = safeBash;
          };
          prompt = ''
            You implement ONE task per the plan you're given. Write/edit the code and
            run what you need (tests, builds). Return a concise summary of what you
            changed and why.
          '';
        };

        reviewer = {
          mode = "subagent";
          model = commander;
          description = "Reviews an implementation for correctness and quality (read-only).";
          permission = {
            edit = "deny";
            bash = "deny";
          };
          prompt = ''
            You review an implementation for correctness, bugs, and quality. Read-only
            — do not edit. Return specific findings and a clear pass/fail.
          '';
        };

        # ── Research / recon tiers ──

        general = {
          mode = "subagent";
          model = reader;
          description = "Cheap fast parallel worker for BROAD research: search, read, and summarize many web sources. Use for breadth/learning; run several in parallel.";
        };

        explore = {
          mode = "subagent";
          model = coder;
        };
        scout = {
          mode = "subagent";
          model = coder;
        };

        research = {
          mode = "subagent";
          model = researcher;
          description = "Deep, source-critical research. Use ONLY when depth and trustworthiness matter (important decisions, hard or ambiguous questions). Always websearch and cite sources.";
          prompt = ''
            You are a rigorous research agent. Use the websearch and webfetch tools to
            ground EVERY factual or current claim in real sources — never rely on
            training memory for facts. Read multiple sources, cross-check them, and cite
            the source URL after each claim. Synthesize a clear answer and explicitly
            flag anything uncertain or unverified.
          '';
        };
      };
    };
  };
}
