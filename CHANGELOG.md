# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.2] — 2026-05-31

### Fixed

- A `test` / `security` gate whose `claude -p` call exited non-zero for any reason other
  than a timeout (auth/API error, OOM, a killed process, a rejected `--settings`, a bad
  `FL_CLAUDE` binary) wrote no failure file, so the gate mis-read as a pass and the run
  could ship `green` on a gate that never actually ran — the same fail-open hole
  `gate_pipeline` already guarded against. The guard (`fl_gate_timeout` → `fl_gate_crash`)
  now synthesizes the failure file on **any** non-zero gate exit, keeping the distinct
  "timed out" wording and adding a "crashed (exit N)" message for other failures, so the
  loop treats the unfinished gate as failed and retries instead of shipping green. (#104)

## [0.5.1] — 2026-05-31

### Added

- `--dry-run` / `FL_DRY_RUN=1` and `--hermetic` for `bin/feature-loop`: exercise the full
  orchestration (worktree, STATUS.md, gates, archive) with zero `claude` calls and zero
  token spend. `--hermetic` also stubs `FL_GATES`. Dry-run runs are tagged in the archive
  (`summary.json` `dry_run` flag and `(dry-run)` markers in STATUS.md / summary.md /
  INDEX.md). (#55)
- `FL_COMMIT_ATTRIBUTION` knob (`.featureloop` / environment, default `0`). Set it to `1`
  to restore Claude Code's `Co-Authored-By: Claude` / "Generated with Claude Code"
  attribution trailer on the loop's commits and PRs. (#50)

### Fixed

- Commits the in-container agent authors no longer carry a `Co-Authored-By: Claude` /
  "Generated with Claude Code" trailer by default, which violated the no-AI-attribution
  convention. The host `~/.claude` is never mounted, so the engine now passes the
  suppression on every `claude` call via the `--settings` flag (which outranks every
  `settings.json` scope but managed), holding regardless of the base image. (#50)

## [0.5.0] — 2026-05-30

### Added

- Per-phase wall-clock timeout for `bin/feature-loop`: every token-spending `claude -p`
  call (build, the test/security gates, simplify, retrospective) is wrapped in GNU
  `timeout`, configurable via `FL_PHASE_TIMEOUT` (default `1200`s). A throttled or wedged
  call is killed at the limit instead of hanging the run indefinitely. A timed-out gate
  has its failure file synthesized so the loop treats it as failed and retries (rather
  than mis-reading "no failure file written" as a pass); a timed-out post-green
  `/code-simplify` discards its partial edits and ships the already-green tip. Where
  `timeout` is unavailable the calls run unbounded rather than failing. (#48)
- Optional `FL_MAX_BUDGET_USD` config for `bin/feature-loop`: when set, it is passed as
  `--max-budget-usd` to each `claude -p` phase call, bounding a runaway agentic loop by
  cost as a complement to the wall-clock `FL_PHASE_TIMEOUT`. Opt-in (unset = no cap) so a
  guessed default can't silently truncate a legitimate multi-step phase. (The originating
  plan proposed `--max-turns`, but the pinned Claude CLI exposes only `--max-budget-usd`;
  this implements the bound with the flag the CLI actually offers.) (#48)
- Progress heartbeat for headless `bin/feature-loop` runs: off-TTY (piped/CI/Docker),
  where the spinner is a no-op, long phases now emit a plain `… still running (Nm)` tick
  every `FL_HEARTBEAT_SECS` (default 60), and STATUS.md stamps each running phase with
  its start time. A slow-but-progressing phase is no longer indistinguishable from a
  hung one — the ambiguity that prompted the original report. This also surfaces upstream
  throttling: the elapsed-time tick makes a throttled phase visibly slow, and a timed-out
  phase's log tail (captured in its failure file) shows whatever the CLI emitted. No 429
  parsing is added because the CLI logs no structured rate-limit signal to key on. (#48)

### Fixed

- `bin/feature-loop` now exits non-zero when a run aborts mid-flight instead of reporting
  success. On macOS's stock Bash 3.2 a `set -u` fatal expansion (unbound scalar or empty
  array) enters the `EXIT` trap with `$?==0`, so a crashed run used to exit `0` and read as
  green to the docker wrapper, CI, and humans. `on_exit` now derives the exit code from the
  explicit `OUTCOME` signal — a propagated failure keeps its code, and only a run that
  reached green may exit `0`. (#45)

## [0.4.2] — 2026-05-30

### Added

- `docs/creating-an-issue.md` documents how to write a plan-shaped work item — the kind
  of issue whose body is piped verbatim into `tasks/plan.md` and executed by
  `/auto-feature`. It covers the report-vs-plan-issue split, the
  `gh issue view … > tasks/plan.md` contract, the plan skeleton (Problem, Decision,
  Architecture, Task list, Out of scope, Checkpoints, Risks), and the repo-specific
  judgment calls: verification must map to `FL_GATES`, new behavior needs a `bats` test,
  generic surface vs. this repo's own config, and semver intent. Cross-linked from
  `CONTRIBUTING.md` and `docs/working-an-issue.md`. (#21)

### Fixed

- The live status spinner no longer floods the output with one line per frame when
  `feature-loop` runs under a PTY that doesn't collapse carriage returns (a capture/relay,
  an IDE/agent terminal, `docker logs`). The animation now also stands down when `TERM`
  is empty or `dumb` or when `CI` is set, alongside the existing TTY and `FL_NO_SPINNER`
  checks. `feature-loop-docker` forwards `FL_NO_SPINNER` / `NO_COLOR` / `FL_ASCII` / `CI`
  into the container when set, and `TERM` only when a terminal is attached — so the
  documented `FL_NO_SPINNER` kill switch now actually reaches the engine on Docker runs,
  while genuinely-attached runs keep their live status. Closes #43.

## [0.4.1] — 2026-05-30

### Fixed

- A green `feature-loop` run no longer leaves the post-green `/code-simplify` cleanup as
  uncommitted changes in the run's worktree. The engine now commits the simplify diff
  after the final gate passes, so the branch tip you push is the simplified tree.
  Previously the run reported green on changes that lived only in the working tree, and
  pushing the tip silently dropped them. (#41)

## [0.4.0] — 2026-05-29

### Added

- Live terminal status for `bin/feature-loop` runs: colored `==>` section headers per
  phase, a spinner during the long build/simplify calls, and a live in-place display of
  the three concurrent gates (test / project / security) that resolves to `✓`/`✗` as
  each finishes. Status is never color-only — a glyph and a word carry the meaning, so
  it stays legible under `NO_COLOR`, in piped logs, and for red-green color vision
  deficiency. Off-TTY (piped/headless/CI) the output is plain `==>` headers and result
  lines with zero escape codes. New opt-outs: `NO_COLOR` (standard) drops color,
  `FL_NO_SPINNER=1` drops the animation, `FL_ASCII=1` uses ASCII marks/frames. (#35)

### Changed

- The plain `=== … ===` stdout recap line from `feature-loop` is replaced by the `==>`
  headers and a final summary; `tasks/STATUS.md` is unchanged. (#35)

## [0.3.0] — 2026-05-29

### Added

- `docs/billing-and-auth.md` documents how feature-loop runs are billed and flags
  Anthropic's **2026-06-15** change: *programmatic* Claude usage — the Agent SDK and
  `claude -p`, which is every feature-loop phase — moves off Pro/Max subscription limits
  onto a separate monthly credit billed at full API rates once spent. This affects the
  `--auth oauth` path; the `ANTHROPIC_API_KEY` path is unchanged. The README `--auth
  oauth` example now links the doc. (#36)
- `feature-loop-docker --auth oauth` now prints a one-line billing reminder to stderr
  about that change; silence it with `FL_NO_BILLING_NOTICE=1`. (#36)

## [0.2.0] — 2026-05-29

### Changed

- The plugin marketplace was renamed from `feature-loop` to `ecukalla-plugins` to
  disambiguate it from the plugin it contains, which is also named `feature-loop`.
  The old `feature-loop@feature-loop` install command read as a typo; it is now the
  self-explanatory `feature-loop@ecukalla-plugins`, and the owner-prefixed name leaves
  room for sibling plugins later. The plugin name is unchanged. A bats regression
  guards the duplication from returning. Existing 0.1.x installs keep working; to pick
  up the new name, re-add the marketplace:

  ```bash
  claude plugin uninstall feature-loop
  claude plugin marketplace remove feature-loop
  claude plugin marketplace add ecukalla/feature-loop
  claude plugin install feature-loop@ecukalla-plugins
  ```

  Closes #11.

## [0.1.5] — 2026-05-29

### Fixed

- The overlay now pins the Claude CLI to `2.1.156` instead of installing whatever
  `latest` resolves to. `latest` became `2.1.154` (the Opus 4.8 launch) on 2026-05-28,
  which wedges headless `claude -p` runs with a `400 "thinking … blocks cannot be
  modified"` — the autonomous writer crashed every iteration and produced no commits.
  Pinned to the verified-good `2.1.156`, overridable via `CLAUDE_CODE_VERSION` (still
  presence-guarded, so a base that already ships `claude` keeps it). Closes #27.
- `.devcontainer/Dockerfile` (this repo's gate-toolchain base) builds again: it installs
  `xz-utils` before unpacking the Node tarball. A prior change dropped it and ran the apt
  step after the download, so `tar -xJf` failed with `xz: Cannot exec`. (#29)

### Security

- CI's `validate-plugin` job installs the Claude CLI from a tracked, version-pinned
  lockfile (`tools/package.json` → `2.1.156`, via `npm --prefix tools ci`) instead of
  `npm install -g @anthropic-ai/claude-code`, which pulled `latest` on every run.
  Dependabot tracks the pin weekly; a bats regression guards the unpinned form from
  returning. Closes #10.

### Added

- This repo's own dogfooding config — a tracked root `.featureloop` and
  `.devcontainer/Dockerfile` (Go 1.25 + Node 22.20 + pre-commit + bats + jq) — so
  `/auto-feature` can run feature-loop on itself durably. Kept off the generic plugin
  surface; consumers still bring their own base. Closes #18.

## [0.1.4] — 2026-05-29

### Fixed

- Engine `build`/`test`/`simplify` phases now invoke their agent-skills skills by
  name (`incremental-implementation`, `test-driven-development`,
  `code-simplification`) instead of the `/build`, `/test`, `/code-simplify` slash
  commands. Those are agent-skills *project* commands that don't load in the headless
  plugin container, so the writer ran as `Unknown command`, made no edits, and the
  loop could never converge or commit. The `security` phase already used the working
  skill-by-name form. Closes #19.
- The autonomous gate phase now runs `FL_GATES` against a clean, git-materialized
  checkout instead of in place on the worktree. On macOS, Docker Desktop's bind mount
  reports spurious executable bits, so `check-executables-have-shebangs` failed ~20
  tracked-but-non-executable files (`README.md`, `Makefile`, …) and a local run never
  went green even though CI (clean Linux checkout) passed. The materialized tree carries
  git's recorded modes and replays uncommitted changes (e.g. the simplify phase's) on
  top. Closes #23.

## [0.1.3] — 2026-05-28

### Changed

- Bump `docker/overlay-bootstrap.sh` default `NODE_VERSION` from `22.15.0` to `22.20.0` so npm-based pre-commit hooks (e.g. `markdownlint-cli`, which pulls `ava@7` requiring node ≥22.20) install cleanly in the overlay without users having to override `NODE_VERSION`. Closes #12.

### Added

- `scripts/lint-plugin-manifests.sh` catches manifest defects that
  `claude plugin validate --strict` misses: non-semver `version` in
  `plugin.json` or `marketplace.json:.plugins[]`, and marketplace
  `source` paths that don't resolve on disk. Wired into both
  `pre-commit` (runs when `.claude-plugin/*.json` changes) and the
  `validate-plugin` CI job. Closes #8. Requires `jq`.

## [0.1.2] — 2026-05-28

### Fixed

- `--auth oauth` on macOS now extracts the Keychain credential blob to an
  `mktemp`-named file with `0600` perms, instead of a predictable path under
  `$TMPDIR`. Closes a symlink-attack window where a hostile local user on a
  shared `TMPDIR` could redirect the credential write.
- `FL_ARCHIVE_DIR` set in `.featureloop` is now honored end-to-end. The host
  runner reads it as the host-side path, bind-mounts it into the container at
  `/home/fluser/.feature-loop`, and forces the engine's in-container
  `FL_ARCHIVE_DIR` to that target via `-e`. Previously, a custom
  `FL_ARCHIVE_DIR` in `.featureloop` was silently lost on container teardown
  because the engine wrote to an unmounted path. Inside the engine, env now
  wins over `.featureloop` for this variable so the runner's pin is
  authoritative. The undocumented `FL_HOST_ARCHIVE_DIR` knob is removed.

## [0.1.1] — 2026-05-28

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

[Unreleased]: https://github.com/ecukalla/feature-loop/compare/v0.5.2...HEAD
[0.5.2]: https://github.com/ecukalla/feature-loop/releases/tag/v0.5.2
[0.5.1]: https://github.com/ecukalla/feature-loop/releases/tag/v0.5.1
[0.5.0]: https://github.com/ecukalla/feature-loop/releases/tag/v0.5.0
[0.4.2]: https://github.com/ecukalla/feature-loop/releases/tag/v0.4.2
[0.4.1]: https://github.com/ecukalla/feature-loop/releases/tag/v0.4.1
[0.4.0]: https://github.com/ecukalla/feature-loop/releases/tag/v0.4.0
[0.3.0]: https://github.com/ecukalla/feature-loop/releases/tag/v0.3.0
[0.2.0]: https://github.com/ecukalla/feature-loop/releases/tag/v0.2.0
[0.1.5]: https://github.com/ecukalla/feature-loop/releases/tag/v0.1.5
[0.1.4]: https://github.com/ecukalla/feature-loop/releases/tag/v0.1.4
[0.1.3]: https://github.com/ecukalla/feature-loop/releases/tag/v0.1.3
[0.1.2]: https://github.com/ecukalla/feature-loop/releases/tag/v0.1.2
[0.1.1]: https://github.com/ecukalla/feature-loop/releases/tag/v0.1.1
[0.1.0]: https://github.com/ecukalla/feature-loop/releases/tag/v0.1.0
