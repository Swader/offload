---
name: offload
description: Delegates a coding task to Sol (Codex CLI, gpt-6.1-sol at xhigh effort) while this agent acts as its manager. Writes a detailed task, waits for the build, checks the report, diff, PR and CI, runs an adversarial persona re-review, and sends corrections to the same Sol session until no actionable findings remain. Use when the user invokes /offload or asks to offload coding to Sol.
disable-model-invocation: true
---

# Offload: Sol builds, you manage

You are the manager. Sol writes the code. You write the task, check the work, review it and send corrections. Do not edit the code yourself; send every fix, small ones too, to Sol.

Skill dir: the folder that holds this file. The runner is `<skill dir>/scripts/offload.sh`. `prompts/build.md` and `prompts/rereview.md` are the user's prompts. Never edit or paraphrase them. The script sends `build.md` to Sol and adds the task path and a report contract.

## 1. Write the task

Write `~/.offload/inputs/<YYYYmmdd-HHMMSS>/<slug>.md`. The slug is a short kebab-case name; it names the run dir. Use this shape:

```markdown
# <title>
Goal: <the outcome in 1-3 sentences, user-visible effect first>
Repo: <absolute checkout path>; origin/main at <sha> (git fetch, then git rev-parse origin/main)
Scope: <what to change, with file:line pointers you verified>
Out of scope: <what not to touch>
Acceptance: <numbered checks that prove it is done>
Context: <plan doc path, Linear, PR and Slack links, decisions already made, known traps>
Coordination: <active tasks, branches or worktrees on the same files; what to avoid>
```

Give facts and pointers, not chat history. Never include secret values.

## 2. Start Sol

Run in the background (in Cursor: Shell tool with `block_until_ms: 0`):

```bash
bash "<skill dir>/scripts/offload.sh" start --task "<input dir>/<slug>.md" --cd "<repo root>"
```

Tell the user in one sentence that Sol is building and that an xhigh build can take 30-120 minutes or more. Overrides: `OFFLOAD_MODEL` (default `gpt-6.1-sol`), `OFFLOAD_EFFORT` (default `xhigh`), `OFFLOAD_OUT_DIR` (default `~/.offload`), `OFFLOAD_CODEX` (path to the codex binary; default: `PATH`, then the user's login shell). A run keeps its model and effort for later rounds unless you override them again. `offload.sh doctor` prints the codex and gh it finds.

## 3. Wait without polling

Wait for the pattern `OFFLOAD_(DONE|FAILED)` with your harness's background wait (in Cursor: AwaitShell with that pattern and a long block time). If it times out, wait again. Do not read the log in a loop; after a timeout you may check the last `agent_message` in `codex.jsonl` once. Every resume runs in a new shell: wait on that shell.

## 4. Check the work

On `OFFLOAD_DONE round=<n> session=<id> report=<path>`, read the report. Treat it as claims and verify each one with `gh` (if it is not on `PATH`, use the path `doctor` prints):

- The PR exists, and its state and base are current main (`gh pr view`).
- The diff matches the task scope, with no scope creep (`gh pr diff`).
- CI state (`gh pr checks`), PR comments, and reviews by humans and bots.
- Every acceptance item, one by one.
- The Linear issues it says it filed.

## 5. Re-review

Run `prompts/rereview.md` yourself, word for word, on the PR or diff. Read the be-thorough skill first if it is installed. Use subagents with different personas, for example a blast-radius tracer, a scale and concurrency skeptic, a product user, and a test realist. Give each a compact brief: PR link, task file, acceptance list and its persona. Keep blocking findings; drop nits.

In that prompt, "fix" means: send the finding to Sol. Your review loop is the loop of steps 3 to 6.

## 6. Send corrections

If an actionable finding remains or an acceptance check fails, write `<run dir>/corrections-<n+1>.md`. Number each finding, with evidence (file:line, CI log or comment link), the expected result, and how you will verify it. Then:

```bash
bash "<skill dir>/scripts/offload.sh" resume --run "<run dir>" --input "<run dir>/corrections-<n+1>.md"
```

Go back to step 3.

Stop when no actionable findings remain, after 5 rounds, or when the same finding comes back twice. In the last two cases, report a blocker with evidence.

When the review is clean, turn on auto-merge yourself: `gh pr merge <PR URL> --auto --squash`, or the repo's usual merge method. Follow the repo's AGENTS.md merge rules. Sol never turns it on.

## 7. Report

Result first: PR links and state (auto-merge on or merged), what changed, the review rounds and what they fixed, open risks, Linear issues filed, and the run dir. Sol's session can be continued with `codex exec resume <session id>`.

On `OFFLOAD_FAILED round=<n> exit=<code> log=<path> err=<path> session=<id>`: read the last lines of `err` to find the cause, then give the user the exit code, the cause in your own words (codex not found, auth failure, unknown model, missing task) and the `err` path. Do not paste raw `err` lines; they can hold secret values. Exit 75 means another round of that run holds its lock: wait for that round. Delete the lock only when the pid in the message is gone and no codex process runs for that run dir. If the line has a session id, you can resume with a correction that says to continue.
