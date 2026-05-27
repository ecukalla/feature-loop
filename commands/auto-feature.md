---
description: Autonomous build→verify→fix loop in a container (build, test, CI gates, security, simplify)
argument-hint: <TICKET> <slug>
---

Run the feature-loop orchestrator in its container against the current repo. It builds
from `tasks/plan.md`, runs `/test` + the project's CI gates + a security audit in
parallel, loops any failures back into `/build`, then runs `/code-simplify` — all with
no approval prompts (bounded by the container).

Prerequisites:

- `/spec` and `/plan` have already produced `tasks/plan.md`.
- A `.featureloop` config exists in the repo root.
- `ANTHROPIC_API_KEY` is set in the environment.

Execute the runner with the supplied ticket and slug, and stream its output:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/feature-loop-docker" $ARGUMENTS
```

When it finishes, read `<worktree>/tasks/STATUS.md` and summarize the result: which
phases passed, how many iterations it took, and the branch to review.
