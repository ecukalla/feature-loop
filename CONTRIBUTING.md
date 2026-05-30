# Contributing to feature-loop

Thanks for helping improve feature-loop. It is a small, focused tool — bash plus a
Claude plugin — so the bar is simple: keep it simple, tested, and lint-clean.

## Development setup

Requirements: `bash`, `git`, `jq`, [`pre-commit`](https://pre-commit.com),
[`bats`](https://github.com/bats-core/bats-core), and (for end-to-end runs) `docker`.

```bash
make install   # install the pre-commit git hooks
make lint      # run every pre-commit hook across the repo
make test      # run the bats suite
```

`make install` wires `pre-commit` so each commit is automatically
shellcheck/shfmt/markdownlint/gitleaks-clean.

## Conventions

- **Commits:** [Conventional Commits](https://www.conventionalcommits.org)
  (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`, …).
- **Shell:** `bash` with `set -euo pipefail`, formatted by `shfmt -i 2 -ci -sr`, and
  shellcheck-clean at `--severity=warning`.
- **Scope:** prefer the boring, obvious change. New behavior needs a `bats` test.
- **Issues:** for a plan-shaped work item meant to drive `/auto-feature`, follow
  [`docs/creating-an-issue.md`](docs/creating-an-issue.md). Thin bug/feature reports use
  the issue forms as-is.

## Pull requests

1. Branch from `main`.
2. `make lint test` must pass (CI enforces both).
3. Add an entry under `[Unreleased]` in `CHANGELOG.md`.
4. Keep each PR to one logical change.

## Releasing

Bump `FL_VERSION` in `bin/feature-loop` and `bin/feature-loop-docker`, the `version`
in `.claude-plugin/plugin.json`, and the `CHANGELOG.md` heading; then tag `vX.Y.Z`.
