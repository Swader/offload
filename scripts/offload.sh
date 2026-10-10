#!/usr/bin/env bash
# Delegate a coding task to Sol (Codex CLI), then send corrections into the same session.
# Usage: offload.sh start --task <file> --cd <repo root>
#        offload.sh resume --run <run dir> --input <corrections file>
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
model="${OFFLOAD_MODEL:-gpt-6.1-sol}"
effort="${OFFLOAD_EFFORT:-xhigh}"
round=0

fail() { # fail <code> <log> <message>
  echo "OFFLOAD_FAILED round=$round exit=$1 log=$2"
  echo "$3" >&2
  exit "$1"
}

abspath() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }

contract="$(cat <<'EOF'
Never print secret values. End your final message with a report for your manager:
- Status: done, or blocked with the blocker.
- PR links and state (draft, open, auto-merge on, merged), branch, and the main commit you started from.
- What changed and why, file by file in one line each.
- Blast radius: which other services and callers use the files you touched, and what you checked.
- Tests and checks you ran, with results. CI state.
- Linear issues you filed, with links.
- Open risks and anything you did not do.
EOF
)"

mode="${1:-}"
[[ $# -gt 0 ]] && shift
task="" cd_dir="" run_dir="" input=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    --cd) cd_dir="${2:-}"; shift 2 ;;
    --run) run_dir="${2:-}"; shift 2 ;;
    --input) input="${2:-}"; shift 2 ;;
    *) fail 2 none "Unknown argument: $1" ;;
  esac
done

command -v codex >/dev/null 2>&1 || fail 127 none "codex is not on PATH"

case "$mode" in
  start)
    [[ -n "$task" && -f "$task" ]] || fail 2 none "Task file missing: '$task'"
    [[ -n "$cd_dir" && -d "$cd_dir" ]] || fail 2 none "Repo directory missing: '$cd_dir' (pass --cd)"
    task="$(abspath "$task")"
    cd_dir="$(cd "$cd_dir" && pwd -P)"
    run_dir="${OFFLOAD_OUT_DIR:-$HOME/.cursor/offload}/$(date +%Y%m%d-%H%M%S)-$(basename "$task" .md)"
    round=1
    mkdir -p "$run_dir/round-1"
    cp "$task" "$run_dir/task.md"
    printf '%s\n' "$cd_dir" >"$run_dir/cwd"
    {
      cat "$skill_dir/prompts/build.md"
      printf '\nTask: %s\nRead the task file first.\n\n%s\n' "$run_dir/task.md" "$contract"
    } >"$run_dir/round-1/input.md"
    ;;
  resume)
    [[ -n "$run_dir" && -f "$run_dir/session_id" && -f "$run_dir/cwd" ]] || fail 2 none "Run dir has no session: '$run_dir'"
    [[ -n "$input" && -f "$input" ]] || fail 2 none "Corrections file missing: '$input'"
    run_dir="$(cd "$run_dir" && pwd -P)"
    cd_dir="$(cat "$run_dir/cwd")"
    round=$(($(find "$run_dir" -maxdepth 1 -type d -name 'round-*' | wc -l) + 1))
    mkdir -p "$run_dir/round-$round"
    { cat "$input"; printf '\n\n%s\n' "$contract"; } >"$run_dir/round-$round/input.md"
    ;;
  *) fail 2 none "Mode must be start or resume" ;;
esac

out="$run_dir/round-$round"
report="$out/report.md"
log="$out/codex.jsonl"
echo "OFFLOAD_STARTED run=$run_dir round=$round log=$log"

rc=0
if [[ "$mode" == start ]]; then
  codex exec -m "$model" -c model_reasoning_effort="$effort" -s danger-full-access -C "$cd_dir" \
    --skip-git-repo-check --json -o "$report" - <"$out/input.md" >"$log" 2>"$out/codex.err" || rc=$?
  sid="$(grep -o '"thread_id":"[^"]*"' "$log" | head -n 1 | cut -d'"' -f4 || true)"
  [[ -n "$sid" ]] && printf '%s\n' "$sid" >"$run_dir/session_id"
else
  sid="$(cat "$run_dir/session_id")"
  (cd "$cd_dir" && codex exec resume "$sid" -m "$model" -c model_reasoning_effort="$effort" \
    -c sandbox_mode='"danger-full-access"' --skip-git-repo-check --json -o "$report" - \
    <"$out/input.md" >"$log" 2>"$out/codex.err") || rc=$?
fi

if [[ $rc -eq 0 && ! -s "$report" ]]; then
  echo "codex exited 0 but wrote no report" >>"$out/codex.err"
  rc=1
fi
if [[ $rc -ne 0 ]]; then
  echo "OFFLOAD_FAILED round=$round exit=$rc log=$log session=${sid:-none}"
  tail -n 20 "$out/codex.err"
  exit "$rc"
fi
echo "OFFLOAD_DONE round=$round session=$sid report=$report"
