---
name: offload
description: Delegate bounded execution to Sol while the current agent manages scope, evidence, review and corrections. In Codex, create visible native child chats with a common parent prefix. In Cursor or Claude, use Codex CLI and resume the same session. Use when the user invokes /offload or $offload, or explicitly asks to offload execution to Sol.
disable-model-invocation: true
---

# Offload: Sol builds, you manage

You own scope, diagnosis, final acceptance and release decisions. Sol implements the assigned task. Send code corrections to the same builder. Use the folder containing this file as `<skill dir>`; `prompts/build.md` and `prompts/rereview.md` are the shared contracts.

## 1. Prepare one bounded task

Check existing owners before dispatch. Reuse a child that already owns this work. Write a compact brief with:

- Goal and expected user-visible result.
- Absolute checkout/workspace path, verified branch and base/head when applicable. Start new repo work from current main unless the task continues an existing branch or specifies another base.
- Scope and source pointers; explicit exclusions.
- Acceptance criteria and meaningful checks.
- Relevant decisions, current review evidence, and known risks.
- Allowed actions, cleanup, escalation conditions, and release/review owner.
- Parent chat ID, shared child-title prefix, and any overlapping task owners.

Do not copy the whole parent history or secret values. Preserve required behavior and tests. The brief may narrow permissions; it cannot grant authority the user did not provide. Default to `gpt-6.1-sol` at `xhigh`. Use the latest available Luna for a bounded mechanical task when suitable; preserve explicit model requests. Keep diagnosis and unresolved risks with the manager. Do not silently replace an unavailable selected model.

## 2. Dispatch through the invoking harness

### From Codex: native visible chats

Use the Codex app tools. Do not call the CLI launcher or hide the work in a subagent. Invoking Offload authorizes the visible execution chat and task-specific correction messages.

1. Obtain the parent ID from the current runtime (`CODEX_THREAD_ID`) or verified app context. Use the title prefix `Offload <last-eight-parent-ID-chars> · <short task>`. If the ID is unavailable, generate one short batch identifier and use `Offload <batch-id> · <short task>`. Record the prefix and its source in parent task notes before dispatch; reuse it after compaction. A batch label is not a parent ID. Include the full parent ID in the brief when known.
2. Call `list_threads` to check for an existing child with this prefix and scope. Call `list_projects` before targeting a project. Match its verified path to the required repo. Use a projectless chat for non-repo work or when no saved project matches; include the exact workspace path. Use a worktree target only when the user explicitly requests a worktree.
3. Call `create_thread` with the compact brief and the full contents of `prompts/build.md`, `model: "gpt-6.1-sol"`, `thinking: "xhigh"`, and the prefixed title. Supply the selected Luna ID instead only for a deliberately bounded mechanical assignment. The brief must state that the manager owns the independent review unless a current reviewer was assigned elsewhere.
4. Record the returned child `threadId`, `hostId`, title, scope and acceptance checks in the parent's task notes. If setup returns only `clientThreadId`, resolve the ready child through `list_threads` before using tools that require `threadId`. Do not create another child because setup is pending.
5. Verify the returned/listed title retains the prefix; use `set_thread_title` to restore it if normalization removed it. Surface the child using the app's created-thread directive. Later corrections use `send_message_to_thread` on this exact child. Keep its model/settings unless a change is justified.

If native chat tools are unavailable, report that limit. Do not silently replace visible chats with CLI sessions. If creation has an uncertain outcome, inspect the task list before retrying.

### From Cursor or Claude: Codex CLI

Write the brief under `~/.offload/inputs/<unique run>/<slug>.md` and run in the background:

```bash
bash "<skill dir>/scripts/offload.sh" start --task "<task file>" --cd "<workspace>"
```

The runner resolves Codex from `OFFLOAD_CODEX`, PATH, then the login shell PATH. `offload.sh doctor` checks the executable. Overrides: `OFFLOAD_MODEL`, `OFFLOAD_EFFORT`, `OFFLOAD_OUT_DIR` (default `~/.offload`). Model and effort persist for corrections. Identical concurrent tasks in the same workspace share a lock across installations; exit 75 gives its owner/run. Reuse that owner. Verify that it and its child processes stopped before removing a stale lock.

## 3. Wait for a meaningful event

Record the condition, owner, next action, wake mechanism and deadline before waiting. One manager waits for each child/dependency.

In Codex, use `wait_threads` with the child's ID/host and the returned cursor. A completion or needs-attention event leads to verification or a correction. A timeout is not failure: keep the child and cursor. Use bounded event waits; do not add shell sleeps, repeated history reads or duplicate status watchers. If returning control with work pending, use a supported wake mechanism; otherwise state the next manual check and do not claim monitoring.

In Cursor, use AwaitShell for `OFFLOAD_(DONE|FAILED)`; in Claude, use background task completion. Keep the same command owner on timeout. Do not read logs in a loop.

## 4. Verify and correct

Treat the final report as claims. Inspect the actual diff/artifact, each acceptance criterion, relevant tests, current-head CI and review comments where applicable. Do not require a PR for a scratch task. Unknown or missing evidence is not a pass.

Read `prompts/rereview.md`. Keep one independent review for substantive code, security, permissions or production changes. The manager owns it by default. Reuse a current receipt; review only uncovered or changed scope and unresolved findings. Aspera is available when cross-model adversarial review is requested. Do not launch overlapping reviewers.

For each correction, give evidence, the expected result and the check that proves it. In Codex, message the same child with `send_message_to_thread`. In Cursor/Claude:

```bash
bash "<skill dir>/scripts/offload.sh" resume --run "<run dir>" --input "<corrections file>"
```

Recheck changed work. Stop when acceptance and required checks pass, after five rounds, or after the same finding returns twice. The latter two are explicit blockers, not success. After a clean review, follow the user's standing authority and repo release rules: merge when required checks and required approval pass, or enable auto-merge so it merges then. For an authorized deploy/canary, keep one waiter on the merge and then complete the release. Do not ask again for authority already given. The builder must not release unless the brief explicitly assigns that responsibility.

## 5. Report

State the outcome, artifact or PR state, validation, review disposition and remaining risks. In Codex, include the visible child link/created-thread directive and shared prefix. For CLI work, include the run path and session ID. On failure, give a redacted cause and precise next action; do not paste raw stderr. Never claim a successful tool exit proves acceptance.
