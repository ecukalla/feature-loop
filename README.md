# feature-loop

[![ci](https://github.com/ecukalla/feature-loop/actions/workflows/ci.yml/badge.svg)](https://github.com/ecukalla/feature-loop/actions/workflows/ci.yml)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://pre-commit.com/)
[![Conventional Commits](https://img.shields.io/badge/commits-conventional-fe5196?logo=conventionalcommits&logoColor=white)](https://www.conventionalcommits.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Autonomous **build → verify → fix** loop for any repo, on top of the
[`agent-skills`](https://github.com/addyosmani/agent-skills) plugin. Run `/spec`
and `/plan`, then one command takes the plan to a green feature branch with **no
approval prompts** — building, testing, running your CI gates, security-auditing,
and simplifying, looping fixes back into the build until everything passes.

The **engine is generic**; everything project-specific lives in a small
`.featureloop` file in the target repo.

## What it does

```text
/spec → SPEC.md     /plan → tasks/plan.md      (interactive, first)

feature-loop PROJ-123 add-rollup-metric
 ├ 1. worktree off origin/<base>  → feature/PROJ-123-add-rollup-metric
 ├ 2. /build         (the ONLY writer)  ← plan + tasks/failures/*.md
 ├ 3-5. parallel READ-ONLY gates:
 │      • /test                  → tasks/failures/test.md      (if gaps)
 │      • $FL_GATES (your CI)    → tasks/failures/pipeline.md  (if red)
 │      • security audit         → tasks/failures/security.md  (if any)
 │      any failures? ─► back to /build  (≤ FL_MAX_ITERS)
 ├ 6. /code-simplify → re-verify gates
 └ live state in <worktree>/tasks/STATUS.md
```

Gates 3–5 are read-only; `/build` is the only writer. That single-writer invariant
is what makes the parallelism safe.

## Install

**As a Claude plugin (interactive `/auto-feature`):**

```bash
claude plugin marketplace add ecukalla/feature-loop
claude plugin install feature-loop@feature-loop
# then, in any repo: /auto-feature PROJ-123 add-rollup-metric
```

**Headless / CLI:**

```bash
git clone https://github.com/ecukalla/feature-loop ~/tools/feature-loop
export PATH="$HOME/tools/feature-loop/bin:$PATH"
# then, in any repo (bring your own image):
ANTHROPIC_API_KEY=… feature-loop-docker PROJ-123 add-rollup-metric
ANTHROPIC_API_KEY=… feature-loop-docker --image python:3.14-slim PROJ-123 add-rollup-metric
```

**Bring your own Docker.** You name the base (an image, a Dockerfile, or `--image`);
feature-loop wraps it with a cached overlay that injects only the Claude CLI, the
agent-skills plugin, and the engine. There is no dependency on any image I publish —
see [`docs/featureloop-config.md`](docs/featureloop-config.md).

Update: `claude plugin update feature-loop` · `git -C ~/tools/feature-loop pull`.

## Configure a repo

Drop a `.featureloop` in the repo root (see [`examples/.featureloop`](examples/.featureloop)
and [`docs/featureloop-config.md`](docs/featureloop-config.md)). Minimum:

```sh
FL_BASE_BRANCH=main
FL_GATES='make test'        # your authoritative CI gate
```

Projects needing extra toolchain point `FL_DOCKERFILE` (or `FL_IMAGE`) at a **pure
toolchain** image — install tools to `/usr/local` so the non-root runtime user can use
them. feature-loop adds Claude/plugin/engine on top automatically.

## Layout

| Path | Role |
|------|------|
| `bin/feature-loop` | the engine (runs in the container; config-driven) |
| `bin/feature-loop-docker` | host runner: resolves your base, applies the overlay, runs the loop |
| `commands/` + `.claude-plugin/` | the `/auto-feature` command + marketplace manifest |
| `docker/overlay-bootstrap.sh` | injects claude + agent-skills + engine onto any apt base |
| `.github/workflows/ci.yml` | lints the scripts + validates the manifest |

## Development

```bash
make install   # pre-commit git hooks
make lint      # shellcheck, shfmt, markdownlint, actionlint, gitleaks
make test      # bats suite
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and the release process, and
[ROADMAP.md](ROADMAP.md) for what's planned.
