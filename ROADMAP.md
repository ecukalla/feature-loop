# Roadmap

Forward-looking items, tracked here until they become GitHub issues. See
[CHANGELOG.md](CHANGELOG.md) for what has shipped.

## Near-term

- [ ] First real end-to-end run (token-spending agents) validated on a sandbox repo.
- [ ] Publish to GitHub; verify the marketplace + `claude plugin install` path and the
      `/auto-feature` command end to end.
- [ ] Add `/review` as an optional read-only gate.
- [ ] Optional prebaked base image for CI speed (documented; not required).

## Ideas

- [ ] `FL_RUNNER=local` — run without Docker.
- [ ] `FL_SKIP_BOOTSTRAP` — skip injection for images that already ship Claude + plugin.
- [ ] Per-gate worktrees, to safely allow parallel writers.
- [ ] CI matrix that builds the overlay against several base images.
