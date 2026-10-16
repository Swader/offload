#!/usr/bin/env bash
# Delegate a coding task to Sol (Codex CLI), then send corrections into the same session.
# Usage: offload.sh start --task <file> --cd <repo root>
#        offload.sh resume --run <run dir> --input <corrections file>
#        offload.sh doctor
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
out_root="${OFFLOAD_OUT_DIR:-$HOME/.offload}"
mode="${1:-}" round=0 run_dir="" log=none err=none sid="" lock="" child="" reported=""

contract="$(cat "$skill_dir/prompts/build.md")"

session_of() { grep -m 1 -o '"thread_id":"[^"]*"' "$run_dir/round-1/codex.jsonl" 2>/dev/null | cut -d'"' -f4 || true; }

tree_of() { local p; for p in $(pgrep -P "$1" 2>/dev/null); do tree_of "$p"; done; echo "$1"; }

stop_child() { # TERM codex and its descendants, give them 10s, then KILL; the lock stays until they are gone
  local pids
  pids="$(tree_of "$child")"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    # shellcheck disable=SC2086
    kill -0 $pids 2>/dev/null || break
    sleep 1
  done
  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null || true
  wait "$child" 2>/dev/null || true
}

finish() {
  local rc=$?
  trap '' HUP INT TERM
  if [[ -n "$child" ]]; then stop_child; fi
  if [[ -n "$lock" ]]; then rm -f "$lock/pid" "$lock/run"; rmdir "$lock"; fi
  if [[ $rc -ne 0 && -z "$reported" ]]; then
    if [[ -z "$sid" && -n "$run_dir" ]]; then sid="$(session_of)"; fi
    echo "OFFLOAD_FAILED round=$round exit=$rc log=$log err=$err session=${sid:-none}"
  fi
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { echo "$2" >&2; exit "$1"; }

acquire_lock() {
  local root="$1" key candidate
  key="$( { printf '%s\0' "$2"; cat "$3"; } | shasum -a 256 | cut -d' ' -f1)"
  mkdir -p "$root/.locks"
  candidate="$root/.locks/$key"
  if ! mkdir "$candidate" 2>/dev/null; then
    fail 75 "Task already owned: pid=$(cat "$candidate/pid" 2>/dev/null || echo starting) run=$(cat "$candidate/run" 2>/dev/null || echo starting). Reuse that owner."
  fi
  lock="$candidate"
  printf '%s\n' "$$" >"$lock/pid"
}

add_login_path() { # Agent shells often skip the user's profile, which is where PATH usually gets set.
  local p
  p="$("${SHELL:-/bin/sh}" -lic env </dev/null 2>/dev/null | sed -n 's/^PATH=//p' | tail -n 1)" || true
  if [[ -n "$p" ]]; then PATH="$PATH:$p"; fi
}

case "$mode" in
  start | resume | doctor) shift ;;
  *) fail 2 "Usage: offload.sh start --task <file> --cd <repo> | resume --run <dir> --input <file> | doctor" ;;
esac
task="" cd_dir="" input=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) var=task ;;
    --cd) var=cd_dir ;;
    --run) var=run_dir ;;
    --input) var=input ;;
    *) fail 2 "Unknown argument: $1" ;;
  esac
  [[ $# -ge 2 ]] || fail 2 "Missing value for $1"
  printf -v "$var" '%s' "$2"
  shift 2
done

if [[ -n "${OFFLOAD_CODEX:-}" ]]; then
  codex="$OFFLOAD_CODEX"
else
  command -v codex >/dev/null || add_login_path
  codex="$(command -v codex || true)"
fi
[[ -n "$codex" && -x "$codex" ]] || fail 127 "codex not found: put it on PATH or set OFFLOAD_CODEX"

if [[ "$mode" == doctor ]]; then
  version="$("$codex" --version | head -n 1)" || fail 127 "codex at $codex does not run; for npm installs, put node on PATH too"
  command -v gh >/dev/null || add_login_path
  echo "codex: $codex ($version)"
  echo "gh: $(command -v gh || echo "not found; the manager needs it for PR checks")"
  echo "runs: $out_root"
  reported=1
  exit 0
fi

if [[ "$mode" == start ]]; then
  [[ -f "$task" ]] || fail 2 "Task file missing: '$task'"
  [[ -d "$cd_dir" ]] || fail 2 "Repo directory missing: '$cd_dir' (pass --cd)"
  cd_dir="$(cd "$cd_dir" && pwd -P)"
  mkdir -p "$out_root"
  out_root="$(cd "$out_root" && pwd -P)"
  acquire_lock "$out_root" "$cd_dir" "$task"
  run_dir="$(mktemp -d "$out_root/$(date +%Y%m%d-%H%M%S)-$(basename "$task" .md).XXXXXX")"
else
  [[ -f "$run_dir/cwd" ]] || fail 2 "Not a run dir: '$run_dir'"
  [[ -f "$input" ]] || fail 2 "Corrections file missing: '$input'"
  [[ -f "$run_dir/task.md" ]] || fail 2 "Run has no task: '$run_dir'"
  run_dir="$(cd "$run_dir" && pwd -P)"
  cd_dir="$(cat "$run_dir/cwd")"
  [[ -d "$cd_dir" ]] || fail 2 "Repo directory missing: '$cd_dir'"
  acquire_lock "$(dirname "$run_dir")" "$cd_dir" "$run_dir/task.md"
fi
run_dir="$(cd "$run_dir" && pwd -P)"
printf '%s\n' "$run_dir" >"$lock/run"

if [[ "$mode" == start ]]; then
  cp "$task" "$run_dir/task.md"
  printf '%s\n' "$cd_dir" >"$run_dir/cwd"
else
  cd_dir="$(cat "$run_dir/cwd")"
  sid="$(session_of)"
  [[ -n "$sid" ]] || fail 2 "Run has no session to resume: $run_dir"
fi
model="${OFFLOAD_MODEL:-$(cat "$run_dir/model" 2>/dev/null || echo gpt-6.1-sol)}"
effort="${OFFLOAD_EFFORT:-$(cat "$run_dir/effort" 2>/dev/null || echo xhigh)}"
printf '%s\n' "$model" >"$run_dir/model"
printf '%s\n' "$effort" >"$run_dir/effort"

round=1
while [[ -e "$run_dir/round-$round" ]]; do round=$((round + 1)); done
out="$run_dir/round-$round"
mkdir "$out"
report="$out/report.md" log="$out/codex.jsonl" err="$out/codex.err"
if [[ "$mode" == start ]]; then
  printf 'Task: %s\nRead the task file first.\n' "$run_dir/task.md" >"$out/input.md"
  set -- exec
else
  cat "$input" >"$out/input.md"
  set -- exec resume "$sid"
fi
printf '\n%s\n' "$contract" >>"$out/input.md"
echo "OFFLOAD_STARTED run=$run_dir round=$round model=$model log=$log"

cd "$cd_dir"
"$codex" "$@" -m "$model" -c model_reasoning_effort="$effort" -c sandbox_mode='"danger-full-access"' \
  --skip-git-repo-check --json -o "$report" - <"$out/input.md" >"$log" 2>"$err" &
child=$!
rc=0
wait "$child" || rc=$?
child=""
[[ "$mode" == resume ]] || sid="$(session_of)"
if [[ -n "$sid" ]]; then printf '%s\n' "$sid" >"$run_dir/session_id"; fi

if [[ $rc -eq 0 ]] && { [[ ! -s "$report" ]] || ! LC_ALL=C grep -q '[^[:space:]]' "$report"; }; then
  echo "codex exited 0 but wrote no report" >>"$err"
  rc=1
fi
if [[ $rc -eq 0 && -z "$sid" ]]; then
  echo "codex exited 0 but returned no session id" >>"$err"
  rc=1
fi
[[ $rc -eq 0 ]] || exit "$rc"
reported=1
echo "OFFLOAD_DONE round=$round session=$sid report=$report"
