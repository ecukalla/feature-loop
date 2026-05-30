# Working an issue (worktree-first)

Runbook for taking **any GitHub issue number → its own git worktree → a reviewed PR**.

Writing the issue itself comes first — see [creating-an-issue.md](creating-an-issue.md)
for the plan-shaped issue shape. This runbook is the build half (issue → worktree → PR).

> **Standing rule:** every bug, issue, or Jira ticket gets its **own git worktree** —
> never `git checkout -b` on the main checkout. `main` stays clean for inspection while
> the fix happens in an isolated tree.

There are two paths. The **autonomous path** (feature-loop) is the default — it creates
the worktree and does the work. The **manual path** is for hand-fixes; it still uses a
worktree.

Set these once per issue, then paste the rest:

```bash
cd /Users/edmond/github/feature-loop
ISSUE=11                    # ← the GitHub issue number
SLUG=rename-marketplace     # ← short kebab-case description (a-z, 0-9, -)
TICKET="ISSUE-$ISSUE"       # branch → feature/$TICKET-$SLUG, worktree → .worktrees/$TICKET
```

---

## One-time setup (already in place for this repo)

The autonomous path needs these in the repo root. They were created while delivering
issue #11 and are reusable for every issue — recreate only if missing.

- **`.featureloop`** — base branch, gates, and the toolchain base:

  ```sh
  FL_BASE_BRANCH=main
  FL_MAX_ITERS=5
  FL_PLAN_FILE=tasks/plan.md
  FL_RETROSPECTIVE=0
  FL_GATES='pre-commit run --all-files && bats --print-output-on-failure tests/'
  FL_DOCKERFILE=docker/featureloop-base.Dockerfile
  ```

- **`docker/featureloop-base.Dockerfile`** — the default container base can't run this
  repo's pre-commit hooks (`markdownlint` needs Node ≥ 22.20, `actionlint`/`gitleaks`
  need Go ≥ 1.25, the manifest hook needs `jq`). This base carries all of them; the
  overlay adds claude + agent-skills on top.

- **Prerequisites:** Docker running, and Claude Code OAuth creds in the macOS Keychain
  (`Claude Code-credentials`). There's no `ANTHROPIC_API_KEY`, so runs use `--auth oauth`.

---

## Autonomous path — feature-loop creates the worktree and does the work

### 1. Make sure the plan exists

The engine builds from `tasks/plan.md`. Either run the interactive flow (`/spec` then
`/plan`), or — when the issue already contains a task breakdown — seed it from the body:

```bash
gh issue view "$ISSUE" --json body --jq .body > tasks/plan.md
```

### 2. Run the loop

```bash
./bin/feature-loop-docker --auth oauth "$TICKET" "$SLUG"
#   (plugin equivalent inside Claude Code:  /auto-feature ISSUE-<n> <slug>)
```

This creates the worktree `.worktrees/$TICKET` on branch `feature/$TICKET-$SLUG` off
`origin/main`, then runs build → test → CI gates → security → simplify with no prompts,
looping fixes until the gates are green. It does **not** push.

### 3. Watch it (optional, from a second terminal)

Give it ~1–3 min for the overlay build, then the worktree files appear live on disk:

```bash
# High-level board (macOS lacks `watch`, so loop it):
while :; do clear; cat .worktrees/$TICKET/tasks/STATUS.md 2>/dev/null; sleep 2; done

# One phase in detail:
tail -f .worktrees/$TICKET/tasks/logs/build-1.log   # build-N / test-N / gates-N / security-N
```

### 4. Review

```bash
cat ~/.feature-loop/runs/$TICKET-*/summary.md
git log  --oneline "origin/main..feature/$TICKET-$SLUG"
git diff "origin/main..feature/$TICKET-$SLUG"
```

The terminal prints `DONE: … is green` on success, or `STOP: gates still failing …` —
in which case inspect `.worktrees/$TICKET/tasks/failures/*` and the matching log.

### 5. Push + open the PR

```bash
git push -u origin "feature/$TICKET-$SLUG"
gh pr create --base main --head "feature/$TICKET-$SLUG" \
  --title "<type>: <summary>" --body "Closes #$ISSUE"
```

---

## Manual path — fix by hand, still in a worktree

When you'd rather edit yourself, the worktree rule still applies.

```bash
# 1. Worktree off the current origin/main (NOT git checkout -b)
git fetch origin main
git worktree add ".worktrees/$TICKET" -b "feature/$TICKET-$SLUG" origin/main
cd ".worktrees/$TICKET"

# 2. Do the work, committing as you go (conventional commits)
#    git commit -m "fix: …"

# 3. Run the gates. The host may lack Node 22.20 / Go 1.25, so run them in the
#    toolchain image for parity with CI:
docker build -f ../../docker/featureloop-base.Dockerfile -t fl-gates ../../docker
docker run --rm -v "$PWD":/src:ro fl-gates bash -lc '
  git config --global --add safe.directory "*"
  git clone -q --no-hardlinks /src /work && cd /work
  pre-commit run --all-files && bats --print-output-on-failure tests/'

# 4. Push + PR (from the worktree or the main checkout — the branch is shared)
git push -u origin "feature/$TICKET-$SLUG"
gh pr create --base main --head "feature/$TICKET-$SLUG" \
  --title "<type>: <summary>" --body "Closes #$ISSUE"
```

---

## Cleanup (after the PR merges)

```bash
cd /Users/edmond/github/feature-loop
git worktree remove ".worktrees/$TICKET"          # add --force if it has leftovers
git branch -d "feature/$TICKET-$SLUG"
git worktree prune                                 # clears any stale entries
```

> The autonomous path's worktree records an in-container path (`/workspace/...`), so on
> the host it shows as **prunable** in `git worktree list` after the run — that's
> expected; `git worktree prune` clears it. The branch and its commits live in the
> shared `.git`, so push/PR work fine from the main checkout regardless.
