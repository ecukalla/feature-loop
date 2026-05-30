# Creating an issue

This guide is the front half of the issue lifecycle: how to **write** an issue. Once
it exists and you are ready to build it, [working-an-issue.md](working-an-issue.md)
takes over (create → work).

An issue in this repo serves one of two audiences. Pick the right shape up front —
they have different goals.

## The two kinds of issue

1. **A report** — you hit a bug or want a feature, and you want it on record. The thin
   [`bug_report.yml`](../.github/ISSUE_TEMPLATE/bug_report.yml) and
   [`feature_request.yml`](../.github/ISSUE_TEMPLATE/feature_request.yml) forms exist
   for this. Low friction, no structure required. If that is you, stop here — open one
   of those forms and you are done.

2. **A plan-shaped work item** — an issue meant to be *executed* by `/auto-feature`.
   Its body is not just a description; it becomes the engine's plan, verbatim. This is
   the kind this guide is about, because here the structure is load-bearing.

## The contract: the issue body becomes `tasks/plan.md`

When you run a plan-shaped issue through the loop, the first step (see
[working-an-issue.md](working-an-issue.md)) is:

```bash
gh issue view "$ISSUE" --json body --jq .body > tasks/plan.md
```

The issue body is piped straight into `tasks/plan.md` — the file the engine reads as
its plan (`FL_PLAN_FILE`, which defaults to `tasks/plan.md`). Nothing reshapes or
summarizes it in between. So **writing the issue *is* writing the plan.** Every
ambiguity you leave in the body is an ambiguity the autonomous writer has to guess at.

A practical consequence: the body must stay free-form markdown. That is why this is a
doc and a Markdown template, not a YAML issue form — a form would flatten the repeating
`Task → Acceptance / Verification / Files` groups and the Risks table into single
fields, constraining the very artifact that has to stay flexible.

## The plan skeleton

A plan-shaped issue body should carry these sections, in order. The optional
[`plan_work_item.md`](../.github/ISSUE_TEMPLATE/plan_work_item.md) template stamps out
the headings; this section explains what goes in each.

- **Problem** — what is wrong or missing today, and why it matters *here*. Concrete,
  not aspirational.
- **Decision (+ rejected alternatives)** — the approach you chose, and the ones you
  did not, with one line each on why. Recording the rejected paths stops the loop (and
  future readers) from re-litigating them.
- **Architecture / Files** — the shape of the change and the specific files it touches.
  Naming the files up front keeps the writer's edits scoped.
- **Task list** — the heart of the plan. One entry per task, each with:
  - **Acceptance** — what is true when the task is done, stated so it can be checked.
  - **Verification** — exact command(s) that prove it (see below).
  - **Files** — the files that task expects to touch.
- **Out of scope** — what this issue deliberately does *not* do. Prevents scope drift.
- **Checkpoints** — natural stopping points where the tree is green and reviewable.
- **Risks** — a short table of what could go wrong, impact, and mitigation.

For two worked examples already written in this shape, open issues **#11** (the
marketplace rename) and **#18** (this repo's own dogfooding config). Read either
end-to-end before writing your own — they are the canonical reference.

## Repo-specific judgment the skeleton cannot capture

The headings are mechanical; these calls are not. Get them right and the loop converges.

- **Verification must map to `FL_GATES`.** A task is only "done" when the repo's gates
  pass. Here that gate is:

  ```bash
  pre-commit run --all-files && bats --print-output-on-failure tests/
  ```

  Write each task's Verification as commands the gates actually run. "It looks right"
  is not a verification; a gate command is.

- **New behavior needs a `bats` test.** Per [CONTRIBUTING.md](../CONTRIBUTING.md), any
  behavior change ships with a test. If a task changes what the tool *does*, its
  Acceptance should call for a `bats` test and its Verification should run `bats tests/`.
  Docs-only tasks are exempt — say so explicitly when they are.

- **Generic surface vs. this repo's own config.** `feature-loop` is a generic tool that
  prescribes no toolchain — consumers start from
  [`examples/.featureloop`](../examples/.featureloop). The root
  [`.featureloop`](../.featureloop) and `.devcontainer/Dockerfile` are *this* repo's
  dogfooding config, not part of the shipped surface. When you plan a change, be clear
  which side of that line it lands on: a change to the generic plugin surface affects
  every consumer; a change to the dogfooding config affects only our own runs.

- **Semver intent.** State which line the change ships in. Internal-only changes (docs,
  CI, this repo's own config) stay in the `0.1.x` patch line. A user-facing change to
  the generic surface warrants a `0.2.0`-style minor bump. Either way, an issue's plan
  should add a `[Unreleased]` entry to [`CHANGELOG.md`](../CHANGELOG.md); the release
  heading is cut later (see CONTRIBUTING's "Releasing").

## Next step

Issue written and ready to build? Hand it to
[working-an-issue.md](working-an-issue.md) — that runbook covers issue → worktree → PR.
