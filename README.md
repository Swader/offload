# Offload

Offload delegates bounded execution to Sol while your agent manages scope, verification, independent review and corrections.

| Invoking harness | Execution route |
| --- | --- |
| Codex | Native sidebar-visible Codex chat |
| Cursor or Claude Code | Codex CLI, with corrections in the same session |

Codex children share a title prefix, `Offload <parent-ID-suffix> · <task>`, and include the full parent ID in their brief. The manager checks existing owners, waits through native task tools and sends corrections to the same child. If native tools are unavailable, it reports the limit rather than hiding the work in a CLI session. See [SKILL.md](SKILL.md).

## Install once, link each harness

For a fresh installation:

```bash
git clone https://github.com/Swader/offload.git "$HOME/.cursor/skills/offload"
mkdir -p "$HOME/.claude/skills" "$HOME/.agents/skills"
ln -s "$HOME/.cursor/skills/offload" "$HOME/.claude/skills/offload"
ln -s "$HOME/.cursor/skills/offload" "$HOME/.agents/skills/offload"
```

Compare and save existing installations before replacing them with links. Keep one checkout; do not add another Codex copy in another discovery directory. Invoke `/offload` in Cursor or Claude, or `$offload` in Codex. Paths resolve relative to the installed skill, so the canonical checkout may live elsewhere.

Codex needs the native app chat tools and access to the chosen model. The CLI route needs Bash 3.2+, Git, and an authenticated Codex CLI. GitHub tasks also need authenticated `gh`.

## CLI route

```bash
bash /path/to/offload/scripts/offload.sh doctor
bash /path/to/offload/scripts/offload.sh start --task /path/to/task.md --cd /path/to/repo
bash /path/to/offload/scripts/offload.sh resume --run /path/to/run --input /path/to/corrections.md
```

| Variable | Default |
| --- | --- |
| `OFFLOAD_MODEL` | `gpt-6.1-sol` |
| `OFFLOAD_EFFORT` | `xhigh` |
| `OFFLOAD_OUT_DIR` | `~/.offload` |
| `OFFLOAD_CODEX` | PATH, then login shell PATH |

The model and effort persist across correction rounds. Each run saves the task, session ID, and per-round prompt, JSON log, stderr and report. Identical concurrent tasks in the same workspace share ownership across installations; a duplicate exits 75 with the owner's PID/run. Interrupts stop the CLI child before releasing the lock. Failed or empty reports are not success.

Native tasks use the model and effort selected in the app call; CLI environment overrides do not affect them. Sol is the normal builder. The manager may select the latest available Luna for a bounded mechanical assignment when the user has not specified a model.

The CLI builder has full file and network access. Its brief and the shared [build contract](prompts/build.md) define authorized work, cleanup and release ownership. The manager verifies the actual result, required checks and one current independent review for substantive changes. Small prose edits need direct verification. Critical unrelated findings are verified and filed in Linear, unless the task excludes external writes; they do not expand the patch. Reviews do not recurse.
