# Offload

Offload is an agent skill. Your agent becomes the manager: it writes a task, hands the coding to Sol through the [Codex CLI](https://github.com/openai/codex), checks the report, diff, PR and CI, runs an adversarial re-review, and sends corrections into the same Sol session until nothing actionable is left.

## Requirements

- `bash` 3.2 or later, and `git`.
- Codex CLI, logged in (`codex login`), with access to the build model. The default model is `gpt-6.1-sol`. Set `OFFLOAD_MODEL` to use another one.
- `gh`, logged in, for the PR and CI checks.

The prompts in `prompts/` name the author's review skills (be-thorough, audit-code, thermo-nuclear-code-quality-review). Without them, Sol and the manager follow the plain instructions.

## Install

Clone the repo into your agent's skills folder, in a folder named `offload`. Then run `doctor`.

| Agent | Folder |
| --- | --- |
| Cursor | `~/.cursor/skills/offload` |
| Codex | `~/.codex/skills/offload` |
| Claude Code | `~/.claude/skills/offload` |

```bash
gh repo clone Swader/offload ~/.cursor/skills/offload
bash ~/.cursor/skills/offload/scripts/offload.sh doctor
```

You do not need to edit any paths. `doctor` prints the codex and gh it found. The script looks for codex in `OFFLOAD_CODEX`, then on `PATH`, then on your login shell's `PATH`, so Homebrew, npm and nvm installs work without setup. If it finds nothing, set `OFFLOAD_CODEX` to the full path of the binary.

## Use

Invoke the skill (`/offload` in Cursor and Claude Code) and say what to build. Sol builds at `xhigh` effort, so a round can take 30 to 120 minutes.

Each run gets its own folder under `~/.offload/`, with the task and one `round-<n>/` folder per build or correction (input, Codex JSON log, stderr, report). You can continue a session by hand with `codex exec resume <session id>`.

| Variable | Default |
| --- | --- |
| `OFFLOAD_MODEL` | `gpt-6.1-sol` |
| `OFFLOAD_EFFORT` | `xhigh` |
| `OFFLOAD_OUT_DIR` | `~/.offload` |
| `OFFLOAD_CODEX` | codex on `PATH`, then on the login shell's `PATH` |

A run keeps its model and effort for later rounds unless you set them again. Only one round of a run can be active at a time; a second one exits with code 75.

## Safety

The script runs Codex with `danger-full-access`, which gives it full file and network access. `prompts/build.md` lets Sol use credentials from `~/.codex/local.env`, the logged-in browser and computer control, and tells it not to pause for logins or approvals. If you do not want this, edit the prompts before you use the skill.
