# Security Policy

## Reporting a vulnerability

Please report security issues **privately** via
[GitHub Security Advisories](https://github.com/ecukalla/feature-loop/security/advisories/new)
rather than opening a public issue. Expect an initial response within a few days.

## Threat model

feature-loop runs `claude --dangerously-skip-permissions`, which removes Claude Code's
approval prompts. This is **only safe inside the container**, whose isolation bounds the
blast radius — never run the engine that way directly on a host you care about.

- No secrets are baked into images; `ANTHROPIC_API_KEY` is passed at runtime only.
- The agent-skills plugin is installed from a pinned commit (`AGENT_SKILLS_REF`).
- `gitleaks` runs in pre-commit and CI to catch committed secrets.
- The overlay creates a non-root user; Claude refuses skip-permissions as root.

### What you implicitly trust when running feature-loop

- **The target repo's `.featureloop`** — it is **sourced as bash** before anything enters
  the container, so any code in it runs on your host. Treat trust in `.featureloop`
  as equal to trust in the target repo. Pass `--no-config` to skip sourcing when
  running against an unfamiliar repo.
- **The base image you bring** (`--image` / `FL_IMAGE` / `FL_DOCKERFILE`) — `docker build`
  runs its `RUN` lines as **root** inside the build container. `TICKET`, `SLUG`, and
  image refs are validated to block shell- and Dockerfile-injection, but a malicious
  base image is still a base image.
- **The agent-skills plugin** at the pinned `AGENT_SKILLS_REF` commit. Bumping that
  arg is a deliberate decision; consider reviewing the diff first.
- **The Claude CLI** at the version installed by `npm install -g @anthropic-ai/claude-code`
  inside the overlay. In **CI**, the CLI is instead pinned via a tracked lockfile:
  the `validate-plugin` job installs from `tools/package.json` (`npm --prefix tools ci`)
  rather than pulling `latest` on every run, so a compromised release can't execute
  against PR builds unnoticed. `tools/package.json` is the source of truth for that pin
  and dependabot bumps it weekly.

### What the loop will do to your repo

- **Bind-mount the repo into the container `read-write`** (`/workspace`). Agents commit
  to the feature branch on your behalf — that is the *point*. The loop never pushes
  and never auto-merges; you review and push.
- **Write under `tasks/` and `.worktrees/`** and add both to `.git/info/exclude` so the
  artefacts don't leak into commits.
- **Run `make` / your `FL_GATES`** with the container's egress to the internet. If your
  gates echo secrets (e.g. `env`, a test printing a database URL), the redirected
  output is captured in `tasks/logs/gates-*.log`. **Redact** secrets in gate output;
  remove the worktree (or run `make clean`) when finished.

### What it does *not* do

- It does not exfiltrate your `ANTHROPIC_API_KEY` to anywhere except the Anthropic API
  (the key is passed only via the `-e` env to the run container). Any process inside
  the container — including the pinned agent-skills plugin — can read that env, so
  trust in the in-container code is trust in that exact pinned commit.

## Supported versions

The latest `main` is supported. Pre-1.0, there are no backports.
