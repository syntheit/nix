# offload — run token-heavy, easy-to-verify work on cheap OpenRouter models
# (via headless opencode) so Claude Code only spends its own quota on the short
# result. Answers go to stdout; cost lines go to stderr; every run is kept under
# ~/.cache/offload/<timestamp>/.

# Costs are printed with printf %f, which follows LC_NUMERIC (es_AR uses a comma).
export LC_NUMERIC=C

usage() {
  cat <<'EOF'
usage:
  offload ask [-m MODEL] [-w | -e] [-i] [-f FILE]... PROMPT
      One headless task. Default: reads the repo in the current directory, no
      shell, no web. -w: web research instead, with no repo access. -e: edits +
      shell allowed (git repo required).
      -i attaches stdin:  nix build 2>&1 | offload ask -i "why did this fail?"
  offload review [-n 1-5] [-b BASE] [-H REF] [-P PR] [-p PATH]... [FOCUS]
      Parallel review of a diff by N different models, each with its own lens,
      merged into one deduplicated list. Diff: `gh pr diff PR` with -P, else
      `git diff BASE...REF` with -b and -H, else `git diff BASE` with -b, else
      uncommitted changes (incl. untracked), else the last commit.
      -p limits the review to those paths (repeatable).
      Writes merged.md and the per-reviewer files to the run dir it prints.
  offload log [N]        Last N runs (default 20): when, model, what for, cost.
  offload stats [DAYS]   Totals for the last DAYS (default 7), by model and kind.
  offload note TEXT      Record a quality note (Claude logs review verdicts here).
  offload models
      List model aliases.

env: OFFLOAD_TIMEOUT (seconds per run, default 600)
log: $XDG_STATE_HOME/offload/log.tsv (default ~/.local/state/offload/log.tsv)
EOF
}

declare -A MODELS=(
  [glm]=z-ai/glm-5.2
  [glm53]=z-ai/glm-5.3
  [kimi]=moonshotai/kimi-k3
  [deepseek]=deepseek/deepseek-v4.1-flash
  [qwen]=qwen/qwen3.8-max-0902
  [coder]=qwen/qwen3-coder-next
  [mimo]=xiaomi/mimo-v2.6-pro
  [minimax]=minimax/minimax-m3
  [flash]=z-ai/glm-4.7-flash
)

resolve_model() {
  local m=${1#openrouter/}
  if [[ $m == */* ]]; then
    echo "$m"
  elif [[ -n ${MODELS[$m]:-} ]]; then
    echo "${MODELS[$m]}"
  else
    echo "offload: unknown model '$1' (see: offload models)" >&2
    exit 2
  fi
}

new_run_dir() {
  local dir
  dir="${XDG_CACHE_HOME:-$HOME/.cache}/offload/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$dir"
  echo "$dir"
}

# run_one OUT.jsonl MODEL AGENT PROMPT [FILE...]
# Never fails: a broken run leaves an empty answer that callers report.
run_one() {
  local out=$1 model=$2 agent=$3 prompt=$4
  shift 4
  local files=()
  local f
  for f in "$@"; do files+=(-f "$f"); done
  # Snapshots (opencode's undo) only matter when the run can edit.
  local cfg='{"snapshot":false}'
  if [[ $agent == build ]]; then cfg='{}'; fi
  local t0=$SECONDS
  # Skills off: opencode would otherwise load ~/.claude/skills — including the
  # offload skill itself.
  OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 \
    OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
    OPENCODE_CONFIG_CONTENT=$cfg \
    timeout "${OFFLOAD_TIMEOUT:-600}" \
    opencode run --format json --agent "$agent" -m "openrouter/$model" "$prompt" "${files[@]}" \
    >"$out" 2>"${out%.jsonl}.err" || true
  echo $((SECONDS - t0)) >"${out%.jsonl}.secs"
}

# JSON event lines only: opencode also prints warnings, and a run killed by the
# timeout can leave a truncated last line. Empty output is fine.
events() { grep '^{' "$1" | jq -c -R 'fromjson? // empty' || true; }

# Final text of a run that finished. A run killed by the timeout also has text
# parts, but its last one is mid-task narration, not an answer.
answer_of() {
  events "$1" | jq -rs '
    if any(.[]; .type == "step_finish" and .part.reason == "stop")
    then [.[] | select(.type == "text") | .part.text] | last // ""
    else "" end'
}

cost_of() {
  events "$1" | jq -rs '[.[] | select(.type == "step_finish") | .part.cost // 0] | add // 0'
}

# One tab-separated line per run, so `offload log`/`stats` can show what ran,
# on which model, for what, at what cost — and `offload note` records whether it
# was any good.
LOG=${XDG_STATE_HOME:-$HOME/.local/state}/offload/log.tsv

# log_row KIND MODEL COST TOKENS SECS STATUS DIR SUMMARY
log_row() {
  mkdir -p "${LOG%/*}"
  printf '%s\t%s\t%s\t%.4f\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Iseconds)" "$1" "$2" "$3" "$4" "$5" "$6" "$7" \
    "$(printf '%s' "$8" | tr '\t\n' '  ' | cut -c1-120)" >>"$LOG"
}

# report_run KIND MODEL OUT.jsonl SUMMARY — stderr line for the caller, row for the log.
report_run() {
  local kind=$1 model=$2 out=$3 summary=$4 cost tokens secs status=ok
  cost=$(cost_of "$out")
  tokens=$(events "$out" | jq -rs '[.[] | select(.type == "step_finish") | .part.tokens.total // 0] | add // 0')
  secs=$(cat "${out%.jsonl}.secs" 2>/dev/null || echo 0)
  [[ -n $(answer_of "$out") ]] || status=failed
  printf 'offload: %-28s $%.4f  %sk tok  %ss\n' "$kind ($model)" "$cost" "$((tokens / 1000))" "$secs" >&2
  log_row "$kind" "$model" "$cost" "$tokens" "$secs" "$status" "${out%/*}" "$summary"
}

fail_hint() {
  echo "offload: $1 returned no answer. stderr tail:" >&2
  tail -n 5 "${2%.jsonl}.err" >&2 || true
}

# Why a run produced no answer, in one line. opencode reports some failures in
# the event stream (a rejected model id), others on stderr, and a run killed by
# the timeout leaves neither.
run_error() {
  local msg
  msg=$(grep -oE '"message":"[^"]+"' "$1" 2>/dev/null | tail -1 | cut -d'"' -f4)
  [[ -n $msg ]] || msg=$(grep -oE '"message":"[^"]+"' "${1%.jsonl}.err" 2>/dev/null | tail -1 | cut -d'"' -f4)
  [[ -n $msg ]] || msg=$(tr '\n' ' ' <"${1%.jsonl}.err" 2>/dev/null | tail -c 160)
  [[ -n $msg ]] || msg="no answer (timed out?)"
  # Provider stderr can carry ANSI escapes, and this string is printed and
  # written into merged.md.
  printf '%.160s' "$(printf '%s' "$msg" | tr -cd '[:print:]')"
}

cmd_ask() {
  local model=glm agent=inspect stdin=0 files=() opt
  OPTIND=1
  while getopts "m:weif:h" opt; do
    case $opt in
      m) model=$OPTARG ;;
      w) agent=browse ;;
      e) agent=build ;;
      i) stdin=1 ;;
      f) files+=("$(realpath "$OPTARG")") ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  if [[ $# -eq 0 ]]; then usage; exit 2; fi
  model=$(resolve_model "$model")

  if [[ $agent == build ]]; then
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      echo "offload: -e needs a git repo, so its changes show up in git diff" >&2
      exit 2
    fi
    if ! git diff --quiet HEAD || [[ -n $(git ls-files --others --exclude-standard) ]]; then
      echo "offload: warning: tree is dirty; git diff will mix its edits with yours" >&2
    fi
  fi

  local dir out
  dir=$(new_run_dir)
  if [[ $agent == browse ]]; then
    # An empty working dir: web pages can't steer it into the repo.
    mkdir "$dir/cwd"
    cd "$dir/cwd"
  fi
  if ((stdin)); then
    cat >"$dir/stdin.txt"
    files+=("$dir/stdin.txt")
  fi
  out="$dir/ask.jsonl"
  run_one "$out" "$model" "$agent" "$*" "${files[@]}"
  local answer
  answer=$(answer_of "$out")
  if [[ -z $answer ]]; then fail_hint "$model" "$out"; exit 1; fi
  printf '%s\n' "$answer"
  report_run "ask:$agent" "$model" "$out" "$*"
}

# Panel order = priority; -n N takes the first N. Measured 2026-09-22 on a
# ~300-line diff: GLM-5.2 5 min, Qwen3.8-max 7 min (found the real security
# holes), MiniMax M3 2 min. Kimi K3, DeepSeek V4.1-flash and MiMo v2.6 Pro hit
# the timeout, so they stay off the panel.
LENSES=(correctness security integration edge-cases simplify)
declare -A LENS_MODEL=(
  [correctness]=glm
  [security]=qwen
  [integration]=minimax
  [edge-cases]=glm53
  [simplify]=coder
)
declare -A LENS_TEXT=(
  [correctness]="Correctness: logic errors, wrong conditions, off-by-one, broken control flow, wrong API/option usage or types — anything that makes the change not do what it intends."
  [integration]="Integration and regressions: how the change interacts with the rest of the repo — callers, importers, config consumers, other hosts/platforms, build or evaluation breakage, behavior changes for existing users. Read the surrounding code, not just the diff."
  [edge-cases]="Edge cases and failure handling: empty/missing/null input, error paths, partial failure, timeouts, concurrency and ordering, resource cleanup, quoting and whitespace."
  [security]="Security and data safety: injection and unsafe shell quoting, secrets leaking (logs, world-readable files, the Nix store), permission/ownership mistakes, destructive operations, unvalidated input."
  [simplify]="Simplification: duplicated logic, dead code, needless complexity, existing helpers that should be reused, misleading names or comments. Only concrete changes with a location."
)

review_prompt() {
  cat <<EOF
Review the code change in the attached diff.patch. The repository is your working directory: read whatever you need for context (callers, definitions, configs that consume the changed code).

Your lens: ${LENS_TEXT[$1]}
${2:+Extra focus from the requester: $2
}
Rules:
- Report only real problems within your lens. No style nits, no praise, no summary of the change.
- Before reporting a finding, open the code around it and confirm it. If you cannot confirm it, set confidence: low.
- Be economical: open only what your lens needs. You have a limited number of tool rounds, so leave room to write your findings.
- At most 8 findings, most severe first, in exactly this format:

### <short title>
- severity: high | medium | low
- location: path:line
- problem: one or two sentences
- failure: concrete input or state -> wrong outcome
- confidence: high | medium | low

If you find nothing, output exactly: NO FINDINGS
EOF
}

AGG_PROMPT='The attached files are independent code reviews of the same change (diff.patch is attached too). Merge them into ONE deduplicated list.
- Two findings are duplicates if they describe the same underlying defect, even with different wording or nearby lines.
- Do not invent findings. Do not drop findings. You may tag one "[likely false positive: <reason>]" only when the diff plainly contradicts it.
- Order: findings reported by more reviewers first, then by severity.
Output exactly:

## Findings (<count>)
1. [<severity>] <path:line> — <title> (reviewers: <lens names>; confidence: <highest>)
   <problem> Failure: <failure>

If every review says NO FINDINGS, output: No findings.'

# opencode rejects a model id its models.dev cache doesn't know ("Model not
# found"), which is how a stale cache silently killed the security lens on
# harbor on 2026-09-22 — it failed in 1s and the merge still printed a
# confident-looking list. Listing models warms that cache AND creates
# opencode's sqlite state, so parallel reviewers don't race its first-run
# migration (the other failure in that report).
warm_opencode() {
  opencode models >"$1" 2>/dev/null || true
}

model_known() {
  # -F: ids contain dots, which as a regex would match near-miss ids too.
  [[ ! -s $2 ]] || grep -qxF "openrouter/$1" "$2"
}

# diff_to_review BASE HEAD PR [PATH...]
diff_to_review() {
  local base=$1 head=$2 pr=$3
  shift 3
  if [[ -n $pr ]]; then
    echo "PR #$pr" >&2
    gh pr diff "$pr"
  elif [[ -n $base && -n $head ]]; then
    echo "git diff $base...$head" >&2
    git diff "$base...$head" -- "$@"
  elif [[ -n $base ]]; then
    echo "git diff $base" >&2
    git diff "$base" -- "$@"
  elif ! git diff --quiet HEAD -- "$@" || [[ -n $(git ls-files --others --exclude-standard -- "$@") ]]; then
    echo "uncommitted changes (incl. untracked)" >&2
    git diff HEAD -- "$@"
    local f
    while IFS= read -r f; do
      git diff --no-index -- /dev/null "$f" || true
    done < <(git ls-files --others --exclude-standard -- "$@")
  else
    echo "last commit ($(git log -1 --format='%h %s'))" >&2
    git diff HEAD~1 HEAD -- "$@"
  fi
}

cmd_review() {
  local n=3 base="" head="" pr="" paths=() opt
  OPTIND=1
  while getopts "n:b:H:P:p:h" opt; do
    case $opt in
      n) n=$OPTARG ;;
      b) base=$OPTARG ;;
      H) head=$OPTARG ;;
      P) pr=$OPTARG ;;
      p) paths+=("$(realpath -m "$OPTARG")") ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  if ! [[ $n =~ ^[1-5]$ ]]; then echo "offload: -n must be 1-5" >&2; exit 2; fi
  # `gh pr diff` takes no pathspecs, so -p with -P would be silently ignored.
  if [[ -n $pr && ${#paths[@]} -gt 0 ]]; then
    echo "offload: -p cannot be combined with -P (gh pr diff takes no paths)" >&2
    exit 2
  fi
  if [[ -n $pr ]] && ! [[ $pr =~ ^[0-9]+$ ]]; then
    echo "offload: -P takes a PR number" >&2
    exit 2
  fi
  # A ref starting with '-' would be read as an option by git.
  local ref
  for ref in "$base" "$head"; do
    if [[ -n $ref ]] && ! git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      echo "offload: '$ref' is not a git ref this repo knows" >&2
      exit 2
    fi
  done
  local focus="$*"
  # A ref left as a positional would silently become focus text and review the
  # wrong thing; -H/-P are how you point at something you haven't checked out.
  if [[ -n $focus ]] && git rev-parse --verify --quiet "$focus" >/dev/null 2>&1; then
    echo "offload: '$focus' is a git ref, not focus text — use -H $focus (or -P for a PR)" >&2
    exit 2
  fi

  cd "$(git rev-parse --show-toplevel)"
  local dir
  dir=$(new_run_dir)
  echo "offload: run dir $dir"
  # diff_to_review describes the scope on stderr; keep it for the log.
  local scope
  scope=$(diff_to_review "$base" "$head" "$pr" "${paths[@]}" 2>&1 >"$dir/diff.patch")
  echo "offload: reviewing $scope" >&2
  if [[ ! -s $dir/diff.patch ]]; then echo "offload: empty diff ($scope), nothing to review" >&2; exit 1; fi

  warm_opencode "$dir/known-models.txt"

  local lens model i pids=() skipped=()
  for ((i = 0; i < n; i++)); do
    lens=${LENSES[$i]}
    model=$(resolve_model "${LENS_MODEL[$lens]}")
    if ! model_known "$model" "$dir/known-models.txt"; then
      skipped+=("$lens ($model): opencode does not know this model id")
      continue
    fi
    run_one "$dir/$lens.jsonl" "$model" inspect "$(review_prompt "$lens" "$focus")" "$dir/diff.patch" &
    pids+=($!)
  done
  if ((${#pids[@]} > 0)); then wait "${pids[@]}"; fi

  local reviews=() names=() answer total=0
  for ((i = 0; i < n; i++)); do
    lens=${LENSES[$i]}
    model=$(resolve_model "${LENS_MODEL[$lens]}")
    [[ -f $dir/$lens.jsonl ]] || continue
    report_run "review:$lens" "$model" "$dir/$lens.jsonl" "$scope${focus:+ — $focus}"
    total=$(jq -n "$total + $(cost_of "$dir/$lens.jsonl")")
    answer=$(answer_of "$dir/$lens.jsonl")
    if [[ -z $answer ]]; then
      skipped+=("$lens ($model): $(run_error "$dir/$lens.jsonl")")
      fail_hint "$lens ($model)" "$dir/$lens.jsonl"
      continue
    fi
    printf '# Review — lens: %s, model: %s\n\n%s\n' "$lens" "$model" "$answer" >"$dir/review-$lens.md"
    reviews+=("$dir/review-$lens.md")
    names+=("$lens")
  done

  # Always tell the caller how many lenses actually ran: a merged list from 1 of
  # 3 reviewers looks exactly like a complete review otherwise.
  local status="${#reviews[@]} of $n reviewers succeeded"
  if ((${#skipped[@]} > 0)); then
    status+=$'\n'"failed: $(printf '%s; ' "${skipped[@]}")"
  fi
  if ((${#reviews[@]} == 0)); then
    printf '%s\n' "$status"
    echo "offload: every reviewer failed" >&2
    exit 1
  fi

  run_one "$dir/merge.jsonl" "$(resolve_model glm)" inspect \
    "$AGG_PROMPT"$'\n\nReviews attached: '"$(printf '%s ' "${names[@]}")" "${reviews[@]}" "$dir/diff.patch"
  answer=$(answer_of "$dir/merge.jsonl")
  report_run "review:merge" "$(resolve_model glm)" "$dir/merge.jsonl" "$scope"
  total=$(jq -n "$total + $(cost_of "$dir/merge.jsonl")")
  if [[ -z $answer ]]; then
    fail_hint "merge" "$dir/merge.jsonl"
    echo "offload: falling back to raw reviews" >&2
    answer=$(cat "${reviews[@]}")
  fi
  printf '%s\n\n%s\n' "$status" "$answer" | tee "$dir/merged.md"
  printf '\nRaw reviews: %s/review-*.md\n' "$dir"
  printf 'offload: total $%.4f for %d reviewers + merge\n' "$total" "${#reviews[@]}" >&2
}

cmd_log() {
  if [[ ! -s $LOG ]]; then echo "offload: nothing logged yet ($LOG)"; return; fi
  {
    printf 'WHEN\tKIND\tMODEL\tCOST\tTOKENS\tSECS\tSTATUS\tWHAT\n'
    tail -n "${1:-20}" "$LOG" | cut -f1,2,3,4,5,6,7,9 | sed 's/\([0-9-]*\)T\([0-9:]*\)[-+][0-9:]*/\1 \2/'
  } | column -t -s $'\t'
}

cmd_stats() {
  if [[ ! -s $LOG ]]; then echo "offload: nothing logged yet ($LOG)"; return; fi
  local days=${1:-7} cutoff
  cutoff=$(date -Iseconds -d "$days days ago")
  awk -F'\t' -v cutoff="$cutoff" -v days="$days" '
    $1 < cutoff { next }
    $2 == "note" { notes = notes "  " $9 "\n"; next }
    {
      runs++; cost += $4; tokens += $5
      if ($7 != "ok") failed++
      model_runs[$3]++; model_cost[$3] += $4
      split($2, parts, ":"); kind[parts[1]]++
    }
    END {
      printf "last %s days: %d runs, $%.2f, %.0fk tokens, %d failed\n", days, runs, cost, tokens / 1000, failed
      printf "by kind:"; for (k in kind) printf " %s=%d", k, kind[k]; printf "\n"
      printf "by model:\n"
      for (m in model_runs) printf "  %-28s %3d runs  $%.3f\n", m, model_runs[m], model_cost[m]
      if (notes) printf "notes (quality):\n%s", notes
    }' "$LOG"
}

cmd_note() {
  if [[ $# -eq 0 ]]; then echo "usage: offload note TEXT" >&2; exit 2; fi
  log_row note - 0 0 0 ok - "$*"
}

cmd_models() {
  local k
  for k in "${!MODELS[@]}"; do printf '%-9s %s\n' "$k" "${MODELS[$k]}"; done | sort
}

case ${1:-} in
  ask) shift; cmd_ask "$@" ;;
  review) shift; cmd_review "$@" ;;
  log) shift; cmd_log "$@" ;;
  stats) shift; cmd_stats "$@" ;;
  note) shift; cmd_note "$@" ;;
  models) cmd_models ;;
  *) usage; exit 2 ;;
esac
