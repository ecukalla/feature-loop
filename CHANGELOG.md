# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `--auth oauth` on `feature-loop-docker` — use your Claude.ai / Max subscription
  inside the container instead of API-key billing. Mounts the credentials Claude
  Code already stores on the host (or extracts them from the macOS Keychain entry
  `Claude Code-credentials` on the fly).
- Per-run archive at `$FL_ARCHIVE_DIR` (default `$HOME/.feature-loop`) — after
  every run, the engine writes a date-stamped directory containing
  `summary.json`, `summary.md`, `STATUS.md`, `retrospective.md`, `diff.stat`,
  `logs/`, and `failures/`, plus a row appended to a cross-run `INDEX.md`.
  The docker runner bind-mounts the host's `~/.feature-loop` into the container
  so artefacts survive worktree teardown.
- Optional retrospective phase: one final Claude call writes a "what went well /
  what needed fixing / what to improve" markdown to `tasks/retrospective.md`.
  Skip with `FL_RETROSPECTIVE=0`.

## [0.1.0] — 2026-05-27

Initial release.

### Added — engine and runner

- `bin/feature-loop`: config-driven build → verify → fix loop. Worktree off
  `origin/<base>`, `/build` as the only writer, parallel read-only gates (`/test`,
  project `FL_GATES`, security audit), failure → fix loop capped at `FL_MAX_ITERS`,
  `/code-simplify` and re-verify, live `tasks/STATUS.md` board.
- `bin/feature-loop-docker`: bring-your-own-Docker host runner. Resolves the base from
  `--image`, `FL_IMAGE`, `FL_DOCKERFILE`, or a neutral public default; wraps it with a
  cached overlay (`docker/overlay-bootstrap.sh`) that injects only the Claude CLI, the
  agent-skills plugin (pinned), and the engine onto any apt base; runs as a non-root
  user inside the container.
- `/auto-feature` Claude plugin command + marketplace manifest.
- `--help` / `--version` on both CLIs; `--no-config` skips sourcing `.featureloop`.

### Added — input validation and threat model

- `TICKET` / `SLUG` validated against `^[A-Za-z0-9._-]{1,64}$`. They are passed to the
  in-container shell as positional arguments, not via string interpolation, so safety
  doesn't depend on the regex alone.
- Image references (`--image` / `FL_IMAGE` / resolved base) validated against an OCI
  regex that supports private registries with a port (e.g. `localhost:5000/foo:tag`).
- `FL_DOCKERFILE` constrained to a relative path with no `..` component.
- `SECURITY.md` documents the `.featureloop` trust model, the read-write bind mount,
  gate-log redaction guidance, and the `ANTHROPIC_API_KEY` exposure model.

### Added — quality gates and CI

- `pre-commit` stack: shellcheck, shfmt, markdownlint, actionlint, gitleaks, plus
  standard whitespace / JSON / YAML / shebang hooks.
- `bats` test suite covering the CLI contract and the input-validation regexes.
- GitHub Actions: lint + test on every push, weekly `pre-commit autoupdate` (opens a
  PR if hook revs drift; the third-party action is SHA-pinned).
- `dependabot.yml` for GitHub Actions bumps.
- `Makefile` task runner: `make install / lint / fmt / test / clean`.

### Added — project hygiene

- README with badges, layout, and a Development section.
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant),
  `ROADMAP.md`.
- `.editorconfig`, `.gitattributes`, `.shellcheckrc`, `.markdownlint.yaml`.
- GitHub issue forms, PR template, `CODEOWNERS`.

[0.1.0]: https://github.com/ecukalla/feature-loop/releases/tag/v0.1.0
