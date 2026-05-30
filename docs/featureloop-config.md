# `.featureloop` configuration

`feature-loop` is generic; each repo describes itself in a `.featureloop` file at its
root. The file is sourced as shell. Copy [`examples/.featureloop`](../examples/.featureloop)
to start.

## Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `FL_GATES` | *(required)* | The authoritative pass/fail gate — your local mirror of CI. Runs in the worktree; first failing command stops the chain and writes `tasks/failures/pipeline.md`. |
| `FL_BASE_BRANCH` | `main` | Branch the worktree forks from. |
| `FL_MAX_ITERS` | `5` | Max build → verify → fix cycles before giving up. |
| `FL_PLAN_FILE` | `tasks/plan.md` | Where `/plan` wrote the plan. |
| `FL_WT_DIR` | `<repo>/.worktrees/<TICKET>` | Worktree location. |
| `FL_IMAGE` | *(unset)* | **Bring your own image** — an existing image to use as the base. |
| `FL_DOCKERFILE` | `.devcontainer/Dockerfile` | A Dockerfile to build as the base, if `FL_IMAGE` is unset. |
| `FL_BUILD_PROMPT` / `FL_TEST_PROMPT` / `FL_SECURITY_PROMPT` / `FL_SIMPLIFY_PROMPT` / `FL_RETROSPECTIVE_PROMPT` | sensible defaults | Override the prompt for any phase. |
| `FL_ARCHIVE_DIR` | `$HOME/.feature-loop` | Where each run is archived (`runs/<RUN_ID>/`). Read on the host; the docker runner bind-mounts this host path into the container at `/home/fluser/.feature-loop` and pins the engine's in-container `FL_ARCHIVE_DIR` to that target, so any value set here survives worktree teardown. Env wins over `.featureloop` for this var. |
| `FL_RETROSPECTIVE` | `1` | Set to `0` to skip the post-run Claude reflection (saves one API call per run). |
| `FL_PHASE_TIMEOUT` | `1200` | Per-phase wall-clock bound (seconds) for every token-spending `claude -p` call (build, the test/security gates, simplify, retrospective). A throttled or wedged call is killed at the limit so it can't hang the run; a timed-out gate is marked failed and retried, and a timed-out post-green simplify is skipped so the green tip still ships. Requires GNU `timeout` (present in the Docker base and on CI); absent it, calls run unbounded. |
| `FL_MAX_BUDGET_USD` | *(unset)* | Optional per-phase API-spend cap (USD), passed as `--max-budget-usd` to each `claude -p` call to bound a runaway agentic loop by cost. Opt-in — left unset there is no cap, so a guessed default can't silently truncate a legitimate multi-step phase. Complements `FL_PHASE_TIMEOUT` (wall-clock) with a cost ceiling. |
| `FL_HEARTBEAT_SECS` | `60` | Interval (seconds) for the off-TTY "still running (Nm)" progress tick during long phases, so a slow phase reads as progressing rather than hung in headless/piped logs. Set to `0` to disable. On an attached terminal the spinner already conveys liveness, so the tick is off there. |
| `FL_COMMIT_ATTRIBUTION` | `0` | Keep AI attribution out of commits/PRs (`0`) or restore the `Co-Authored-By: Claude` / "Generated with Claude Code" trailer (`1`). The engine passes the suppression to every `claude` call via `--settings` (highest non-managed precedence), so it holds on any base image; `1` omits the flag. |
| `NO_COLOR` | *(unset)* | Standard [no-color.org](https://no-color.org) convention — set to any value to drop ANSI color from the terminal output. The spinner and headers still render (uncolored). |
| `FL_NO_SPINNER` | *(unset)* | Set to `1` to drop the spinner animation and the live in-place gate display, leaving just the `==>` section headers and plain result lines. Color is unaffected. The spinner also auto-disables off-TTY and when `TERM` is empty/`dumb` or `CI` is set (see [Terminal output](#terminal-output)). Forwarded into Docker runs when set on the host. |
| `FL_ASCII` | *(unset)* | Set to `1` to use ASCII status marks (`[OK]`/`[XX]`) and ASCII spinner frames instead of the Unicode `✓`/`✗` + braille frames — for CJK "ambiguous-width" terminals or anywhere the single-cell glyphs misalign. |

## Terminal output

When stdout is an interactive terminal, the engine shows colored `==>` section
headers per phase, a spinner during the long build/simplify calls, and a live
in-place display of the three concurrent gates that resolves to `✓`/`✗` as each
finishes. Status is never conveyed by color alone — a glyph (`✓`/`✗`) and a word
(`pass`/`FAIL`) carry the meaning, so it stays legible under `NO_COLOR`, in piped
logs, and for red-green color vision deficiency.

When stdout is **not** a TTY (piped, headless, CI — including every Docker run that
isn't attached), color and animation are no-ops: the output is plain `==>` headers
and plain result lines with zero escape codes, so captured logs stay clean. To keep a
slow phase distinguishable from a hang there, long phases emit a plain
`… still running (Nm)` heartbeat every `FL_HEARTBEAT_SECS` (default 60), and STATUS.md
stamps each running phase with the time it started. Tune it with `NO_COLOR`,
`FL_NO_SPINNER`, `FL_ASCII`, and `FL_HEARTBEAT_SECS` above.

A bare TTY is necessary but not sufficient — a PTY can be a capture/relay (an IDE or
agent terminal, a CR-preserving log capture) that doesn't collapse the spinner's
carriage returns in place, flooding the screen with one line per frame. So the spinner
also stands down when `TERM` is empty or `dumb`, or when `CI` is non-empty, even on a
TTY. A genuine attached terminal exports a real `TERM`, so it still animates; if a
relay advertises a real `TERM` yet linearizes `\r`, set `FL_NO_SPINNER=1`.

For Docker runs, the runner forwards `FL_NO_SPINNER`, `NO_COLOR`, `FL_ASCII`, and `CI`
into the container whenever they are set in the host environment (so the opt-outs work
without editing `.featureloop`), plus `TERM` only when a PTY is attached.

## Per-run archive

After every run (success or failure), the engine copies its artefacts to a
date-stamped directory under `$FL_ARCHIVE_DIR/runs/`, and appends a row to a
cross-run `INDEX.md`. Layout:

```text
$HOME/.feature-loop/
├── INDEX.md                          # one row per run; quick "show me all my runs"
└── runs/
    └── <TICKET>-<UTC-timestamp>/
        ├── summary.json              # machine-readable: outcome, duration, iters
        ├── summary.md                # human-readable one-pager
        ├── STATUS.md                 # final state board (copied from the worktree)
        ├── retrospective.md          # what worked, what was fixed, what to improve
        ├── diff.stat                 # `git diff --stat origin/<base>..HEAD`
        ├── logs/                     # every build/test/gates/security/simplify log
        └── failures/                 # any failure markdown still present at exit
```

The retrospective is one extra Claude call at the end; set `FL_RETROSPECTIVE=0`
to skip it.

## Bring your own Docker

feature-loop never forces a base image on you. You name the base; it wraps that base
with a small **cached overlay** that injects only what the loop needs — the Claude CLI,
the agent-skills plugin, and the engine — and creates a non-root runtime user.

Base resolution, first match wins:

```text
feature-loop-docker --image REF …   # per-run flag
  └ FL_IMAGE        (.featureloop)   # an existing image, e.g. python:3.14-slim
     └ FL_DOCKERFILE (.featureloop)  # your Dockerfile, built as the base
        └ default                    # node:22-bookworm-slim (neutral, public)
```

The overlay is cached per base, so injection is a one-time cost. There is **no
dependency on any image I publish.**

### Contract for your base/Dockerfile

- **Debian/Ubuntu-family** (apt). The overlay's bootstrap uses apt + Node to add Claude.
  For non-apt bases, pre-bake Claude + the plugin yourself.
- **Install tools to system paths** (`/usr/local/bin`, not a user's `$HOME`). The loop
  runs as a non-root user the overlay creates, so per-user installs won't be visible.
  With `uv`, point its dirs at a shared location and make them readable:

  ```dockerfile
  ENV UV_INSTALL_DIR=/usr/local/bin \
      UV_TOOL_BIN_DIR=/usr/local/bin \
      UV_TOOL_DIR=/opt/uv/tools \
      UV_PYTHON_INSTALL_DIR=/opt/uv/python \
      UV_PYTHON_PREFERENCE=only-managed
  RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
   && uv python install 3.14 3.12 \
   && uv tool install --python 3.12 checkov \
   && uv tool install --python 3.12 semgrep \
   && uv tool install ruff \
   && chmod -R a+rX /opt/uv
  ```

### Optional: prebake for CI speed

Where there's no Docker cache (fresh CI runners), the overlay rebuilds each run. To skip
that, prebake an image with the bootstrap and point `FL_IMAGE` at it:

```dockerfile
FROM your-toolchain-image
COPY overlay-bootstrap.sh /tmp/b
RUN AGENT_SKILLS_SHA=<sha> bash /tmp/b
```

Publish it wherever you like (e.g. Docker Hub, public, so no login is needed). It's an
optimization — not required.

## How the gates are used

- `FL_GATES` is **deterministic** and authoritative — it runs your tests/lint/scan.
- `/test` (LLM) reviews **test adequacy/coverage** for the new code and complements it.
- The security audit (LLM) reasons about authn/input/secrets beyond static scanners.

All three run read-only in parallel; every fix is funneled back through `/build`, the
single writer.
