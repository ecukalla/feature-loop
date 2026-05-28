#!/usr/bin/env bats
#
# CLI-contract tests for the feature-loop scripts. These cover the parts that run
# without Docker, git side effects, or the Claude API: argument parsing, help/version,
# and example-config validity.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FL="$REPO_ROOT/bin/feature-loop"
  FLD="$REPO_ROOT/bin/feature-loop-docker"
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
