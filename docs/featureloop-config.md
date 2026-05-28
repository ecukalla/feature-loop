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
