#!/usr/bin/env bats
#
# CLI-contract tests for the feature-loop scripts. These cover the parts that run
# without Docker, git side effects, or the Claude API: argument parsing, help/version,
# and example-config validity.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FL="$REPO_ROOT/bin/feature-loop"
  FLD="$REPO_ROOT/bin/feature-loop-docker"
  LINT="$REPO_ROOT/scripts/lint-plugin-manifests.sh"
}

@test "feature-loop --version prints a version" {
  run "$FL" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "feature-loop "* ]]
}

@test "feature-loop --help exits 0 with usage" {
  run "$FL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: feature-loop"* ]]
}

@test "feature-loop with no args exits 2 with usage" {
  run "$FL"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: feature-loop"* ]]
}

@test "feature-loop-docker --version prints a version" {
  run "$FLD" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "feature-loop-docker "* ]]
}

@test "feature-loop-docker --help exits 0 with usage" {
  run "$FLD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: feature-loop-docker"* ]]
}

@test "feature-loop-docker rejects an unknown option" {
  run "$FLD" --nope TICKET slug
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "example .featureloop sets a non-empty FL_GATES" {
  run bash -c "set -a; . '$REPO_ROOT/examples/.featureloop'; [ -n \"\$FL_GATES\" ]"
  [ "$status" -eq 0 ]
}

# --- C1: TICKET / SLUG must reject shell-injectable input -----------------------------

@test "feature-loop rejects TICKET containing a single quote" {
  run "$FL" "x'; bad" valid
  [ "$status" -eq 2 ]
  [[ "$output" == *"must match"* ]]
}

@test "feature-loop rejects SLUG containing a single quote" {
  run "$FL" valid "x'; bad"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must match"* ]]
}

@test "feature-loop-docker rejects TICKET containing a single quote" {
  run "$FLD" "x'; bad" valid
  [ "$status" -eq 2 ]
  [[ "$output" == *"must match"* ]]
}

@test "feature-loop-docker rejects SLUG containing a single quote" {
  run "$FLD" valid "x'; bad"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must match"* ]]
}

# --- C2: image refs and FL_DOCKERFILE must not allow Dockerfile injection ------------

@test "feature-loop-docker rejects --image with embedded newline" {
  run "$FLD" --image "$(printf 'python\nRUN bad')" valid valid
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid image"* ]]
}

@test "feature-loop-docker rejects FL_IMAGE from env with embedded newline" {
  FL_IMAGE="$(printf 'python\nRUN bad')" run "$FLD" valid valid
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid FL_IMAGE"* ]]
}

@test "feature-loop-docker rejects FL_DOCKERFILE containing .." {
  FL_DOCKERFILE='../evil' run "$FLD" valid valid
  [ "$status" -eq 2 ]
  [[ "$output" == *".."* ]]
}

# --- I-C: positive coverage — legitimate image refs must pass validation -------------

@test "feature-loop-docker accepts FL_IMAGE=python:3.14-slim" {
  FL_IMAGE=python:3.14-slim run "$FLD" valid valid
  [[ "$output" != *"invalid"* ]]
}

@test "feature-loop-docker accepts FL_IMAGE with registry:port path" {
  FL_IMAGE='localhost:5000/foo:tag' run "$FLD" valid valid
  [[ "$output" != *"invalid"* ]]
}

@test "feature-loop-docker accepts --image ghcr.io/owner/img:v1.0" {
  run "$FLD" --image ghcr.io/owner/img:v1.0 valid valid
  [[ "$output" != *"invalid image"* ]]
}

# --- --auth flag --------------------------------------------------------------------

@test "feature-loop-docker rejects an invalid --auth value" {
  run "$FLD" --auth nope valid valid
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid --auth"* ]]
}

# --- I1: --no-config flag skips sourcing .featureloop --------------------------------

@test "feature-loop accepts --no-config" {
  run "$FL" --no-config
  [ "$status" -eq 2 ]
  [[ "$output" != *"Unknown option"* ]]
  [[ "$output" == *"Usage: feature-loop"* ]]
}

@test "feature-loop rejects an unknown option" {
  run "$FL" --nope T S
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "feature-loop-docker accepts --no-config" {
  run "$FLD" --no-config
  [ "$status" -eq 2 ]
  [[ "$output" != *"Unknown option"* ]]
  [[ "$output" == *"Usage: feature-loop-docker"* ]]
}

@test "feature-loop --no-config does not source .featureloop" {
  tmp="$(mktemp -d)"
  (cd "$tmp" && git init -q && echo "FL_GATES=true" > .featureloop &&
    mkdir tasks && echo "todo" > tasks/plan.md &&
    "$FL" --no-config TICKET slug) 2>&1 | grep -q "FL_GATES is empty"
  rc=$?
  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
}

# --- traceability: per-run archive at FL_ARCHIVE_DIR ---------------------------------

@test "feature-loop archives the run to FL_ARCHIVE_DIR on completion" {
  tmp="$(mktemp -d)"
  archive="$tmp/archive"
  (
    cd "$tmp" || exit 1
    git init --bare -q upstream.git
    git init -q -b main work
    cd work || exit 1
    echo 'FL_GATES=true' > .featureloop
    mkdir tasks
    echo 'todo' > tasks/plan.md
    echo x > README.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../upstream.git
    git push -q origin main
    FL_CLAUDE=true FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$archive" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 \
      "$FL" TKT slug
  ) > /dev/null 2>&1
  rc=$?

  archive_ok=0
  if [ -d "$archive/runs" ] &&
    [ -f "$archive/INDEX.md" ] &&
    ls "$archive/runs"/TKT-*/summary.json > /dev/null 2>&1 &&
    ls "$archive/runs"/TKT-*/STATUS.md > /dev/null 2>&1; then
    archive_ok=1
  fi
  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$archive_ok" -eq 1 ]
}

# --- --auth oauth uses an unpredictable tempfile path (symlink defense) --------------

@test "feature-loop-docker --auth oauth on macOS never writes to a predictable tempfile" {
  # The predictable path ${TMPDIR:-/tmp}/fl-claude-creds.json is symlink-attackable
  # on shared TMPDIR. With a canary file pre-existing at that path, a correct
  # implementation (mktemp) leaves it intact; a vulnerable one clobbers it.
  tmpdir="$(mktemp -d)"
  canary="$tmpdir/fl-claude-creds.json"
  echo CANARY > "$canary"

  stub="$(mktemp -d)"
  cat > "$stub/uname" << 'EOF'
#!/usr/bin/env bash
case "$1" in
  -s | "") echo Darwin ;;
  *) /usr/bin/uname "$@" ;;
esac
EOF
  cat > "$stub/security" << 'EOF'
#!/usr/bin/env bash
echo '{"fake":"oauth-creds"}'
EOF
  cat > "$stub/docker" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub/uname" "$stub/security" "$stub/docker"

  work="$(mktemp -d)"
  (
    cd "$work" || exit 1
    git init -q
    echo 'FL_GATES=true' > .featureloop
    TMPDIR="$tmpdir" PATH="$stub:$PATH" FL_OAUTH_CREDS=/nonexistent \
      "$FLD" --auth oauth TKT slug
  ) > /dev/null 2>&1

  canary_intact=0
  [ "$(cat "$canary" 2> /dev/null)" = "CANARY" ] && canary_intact=1

  rm -rf "$tmpdir" "$stub" "$work"
  [ "$canary_intact" -eq 1 ]
}

# --- FL_ARCHIVE_DIR coupling between host runner and in-container engine -------------

@test "feature-loop-docker bind-mounts FL_ARCHIVE_DIR from .featureloop and pins the in-container path" {
  # When .featureloop sets FL_ARCHIVE_DIR=/custom, the runner must (a) bind-mount
  # /custom into the container, and (b) pass -e FL_ARCHIVE_DIR=/home/fluser/.feature-loop
  # so the engine writes into the mount instead of the user-supplied host path
  # (which doesn't exist in the container's filesystem).
  tmp="$(mktemp -d)"
  custom="$tmp/my-archive"

  stub="$(mktemp -d)"
  cat > "$stub/docker" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$tmp/docker.log"
echo --- >> "$tmp/docker.log"
exit 0
EOF
  chmod +x "$stub/docker"

  (
    cd "$tmp" || exit 1
    git init -q
    cat > .featureloop << EOF
FL_GATES=true
FL_ARCHIVE_DIR=$custom
EOF
    PATH="$stub:$PATH" ANTHROPIC_API_KEY=sk-test "$FLD" TKT slug
  ) > /dev/null 2>&1

  bind_ok=0
  env_ok=0
  archive_created=0
  grep -qF "$custom:/home/fluser/.feature-loop" "$tmp/docker.log" && bind_ok=1
  grep -qF "FL_ARCHIVE_DIR=/home/fluser/.feature-loop" "$tmp/docker.log" && env_ok=1
  [ -d "$custom" ] && archive_created=1

  rm -rf "$tmp" "$stub"
  [ "$bind_ok" -eq 1 ]
  [ "$env_ok" -eq 1 ]
  [ "$archive_created" -eq 1 ]
}

@test "feature-loop engine prefers FL_ARCHIVE_DIR from env over .featureloop value" {
  # The docker runner pins the in-container FL_ARCHIVE_DIR via `-e`. That pin
  # only works if env wins over .featureloop inside the engine.
  tmp="$(mktemp -d)"
  env_archive="$tmp/env-archive"
  cfg_archive="$tmp/cfg-archive"

  (
    cd "$tmp" || exit 1
    git init --bare -q upstream.git
    git init -q -b main work
    cd work || exit 1
    cat > .featureloop << EOF
FL_GATES=true
FL_ARCHIVE_DIR=$cfg_archive
EOF
    mkdir tasks
    echo 'todo' > tasks/plan.md
    echo x > README.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../upstream.git
    git push -q origin main
    FL_CLAUDE=true FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$env_archive" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 \
      "$FL" TKT slug
  ) > /dev/null 2>&1
  rc=$?

  env_used=0
  cfg_used=0
  ls "$env_archive/runs"/TKT-*/summary.json > /dev/null 2>&1 && env_used=1
  ls "$cfg_archive/runs"/TKT-*/summary.json > /dev/null 2>&1 && cfg_used=1

  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$env_used" -eq 1 ]
  [ "$cfg_used" -eq 0 ]
}

# --- stricter manifest lint (issue #8): semver + source-path checks ------------------

@test "lint-plugin-manifests passes on the repo's own manifests" {
  run "$LINT"
  [ "$status" -eq 0 ]
}

@test "lint-plugin-manifests rejects a non-semver version in plugin.json" {
  tmp="$(mktemp -d)"
  mkdir "$tmp/.claude-plugin"
  jq '.version = "not-semver"' "$REPO_ROOT/.claude-plugin/plugin.json" \
    > "$tmp/.claude-plugin/plugin.json"
  cp "$REPO_ROOT/.claude-plugin/marketplace.json" "$tmp/.claude-plugin/marketplace.json"
  run "$LINT" "$tmp"
  rm -rf "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid semver"* ]]
}

@test "lint-plugin-manifests rejects a non-semver version in a marketplace plugin entry" {
  tmp="$(mktemp -d)"
  mkdir "$tmp/.claude-plugin"
  cp "$REPO_ROOT/.claude-plugin/plugin.json" "$tmp/.claude-plugin/plugin.json"
  jq '.plugins[0].version = "v1.0"' "$REPO_ROOT/.claude-plugin/marketplace.json" \
    > "$tmp/.claude-plugin/marketplace.json"
  run "$LINT" "$tmp"
  rm -rf "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid semver"* ]]
}

@test "lint-plugin-manifests rejects a marketplace source path that does not resolve" {
  tmp="$(mktemp -d)"
  mkdir "$tmp/.claude-plugin"
  cp "$REPO_ROOT/.claude-plugin/plugin.json" "$tmp/.claude-plugin/plugin.json"
  jq '.plugins[0].source = "./does-not-exist"' \
    "$REPO_ROOT/.claude-plugin/marketplace.json" \
    > "$tmp/.claude-plugin/marketplace.json"
  run "$LINT" "$tmp"
  rm -rf "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not resolve"* ]]
}

# --- regression: headless engine prompts must use skills, not slash-commands (#19) ---

@test "engine default prompts invoke agent-skills skills, not slash-commands" {
  # /build, /test, /code-simplify are agent-skills *project* commands that don't load
  # in the headless plugin container, so the writer no-opped ("Unknown command") and
  # the loop never committed. The default prompts must reference the backing skills.
  run grep -nE ':-/(build|test|code-simplify)' "$FL"
  [ "$status" -ne 0 ]
  grep -q 'incremental-implementation skill' "$FL"
  grep -q 'test-driven-development skill' "$FL"
  grep -q 'code-simplification skill' "$FL"
}

# --- regression: gates run against a clean checkout, not the bind-mount (#23) ---

@test "gate phase ignores spurious worktree +x bits by gating a clean checkout" {
  # macOS Docker bind mounts report a spurious +x on every file, which fails
  # pre-commit's check-executables-have-shebangs even though git records them 100644.
  # The gate phase must run FL_GATES against a git-materialized checkout (recorded
  # modes), not in place. Proxy gate `test ! -x plain.txt` fails in the +x worktree
  # but passes on the clean checkout.
  tmp="$(mktemp -d)"
  (
    cd "$tmp" || exit 1
    git init --bare -q upstream.git
    git init -q -b main seed
    cd seed || exit 1
    printf 'no shebang here\n' > plain.txt
    mkdir tasks && echo todo > tasks/plan.md
    git add plain.txt
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../upstream.git
    git push -q origin main
  ) > /dev/null 2>&1

  wt="$tmp/wt"
  git -C "$tmp/seed" worktree add -q "$wt" origin/main > /dev/null 2>&1
  chmod +x "$wt/plain.txt" # simulate the bind mount's spurious +x on a tracked 100644 file

  (
    cd "$tmp/seed" || exit 1
    printf "FL_GATES='test ! -x plain.txt'\n" > .featureloop
    FL_CLAUDE=true FL_MAX_ITERS=1 FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 \
      FL_ARCHIVE_DIR="$tmp/archive" FL_WT_DIR="$wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1
  rc=$?

  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
}
