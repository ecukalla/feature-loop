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

# Stub `docker` in PATH dir $1 to append its args (one per line) to $2/docker.log,
# so tests can assert which `-e VAR` flags the runner forwarded.
_stub_docker_logging_args() {
  cat > "$1/docker" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$2/docker.log"
exit 0
EOF
  chmod +x "$1/docker"
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
  # --no-config so the assertion targets the env-supplied value and isn't overridden
  # by this repo's own root .featureloop (which sets FL_DOCKERFILE).
  FL_DOCKERFILE='../evil' run "$FLD" --no-config valid valid
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

# --- live status: piped output stays plain (ISSUE-35) --------------------------------

@test "feature-loop piped output emits ==> headers and contains no escape codes" {
  # The engine runs headless in Docker with phase output piped to logs, so the
  # color/spinner/in-place display MUST be no-ops off-TTY: zero \033 (ESC) AND
  # zero \r (CR) in BOTH captured stdout AND every tasks/logs/* file. \r is the
  # primary mechanism of this feature (spin's carriage return, the gate panel's
  # CUU/EL), so the guard must cover it, not just ESC. bats already runs the
  # engine off-TTY, so a plain run is the off-TTY case. The ==> headers must
  # still appear (they replaced the === recap).
  tmp="$(mktemp -d)"
  out="$tmp/out.txt"
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
    FL_CLAUDE=true FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$tmp/arc" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$tmp/wt" \
      "$FL" TKT slug
  ) > "$out" 2> /dev/null
  rc=$?

  has_header=0
  no_escape=1
  grep -qF '==>' "$out" && has_header=1
  # stdout: no ESC, no CR
  grep -q "$(printf '\033')" "$out" && no_escape=0
  grep -q "$(printf '\r')" "$out" && no_escape=0
  # logs: no ESC, no CR in any tasks/logs/* file
  grep -rq "$(printf '\033')" "$tmp/wt/tasks/logs" && no_escape=0
  grep -rq "$(printf '\r')" "$tmp/wt/tasks/logs" && no_escape=0

  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$has_header" -eq 1 ]
  [ "$no_escape" -eq 1 ]
}

# --- live status: spinner is correct, not absent — relay/CI safe (ISSUE-43) ----------
#
# The #40 spinner gated on `[ -t 1 ]` alone, but a PTY can be a capture/relay that
# linearizes carriage returns, so the in-place spinner floods one line per frame. The
# fix (a) forwards the display-control env into the container so the documented opt-out
# actually reaches the engine, and (b) strengthens the engine gate to stand down when
# TERM is empty/dumb or CI is set, while a real attached terminal still animates.

@test "feature-loop-docker forwards FL_NO_SPINNER/NO_COLOR/FL_ASCII/CI when set, but not TERM when unattached" {
  # bats runs unattached, so the runner passes no `-t`: the display-control vars must
  # still be forwarded (the documented host opt-out was previously dropped, Gap #1),
  # but TERM must NOT be — without a PTY there is no real terminal type to forward.
  tmp="$(mktemp -d)"
  stub="$(mktemp -d)"
  _stub_docker_logging_args "$stub" "$tmp"

  (
    cd "$tmp" || exit 1
    git init -q
    echo 'FL_GATES=true' > .featureloop
    PATH="$stub:$PATH" ANTHROPIC_API_KEY=sk-test \
      FL_NO_SPINNER=1 NO_COLOR=1 FL_ASCII=1 CI=1 TERM=xterm-256color \
      "$FLD" TKT slug
  ) > /dev/null 2>&1

  fwd=1
  for v in FL_NO_SPINNER NO_COLOR FL_ASCII CI; do
    grep -qx "$v" "$tmp/docker.log" || fwd=0
  done
  term_absent=1
  grep -qx TERM "$tmp/docker.log" && term_absent=0

  rm -rf "$tmp" "$stub"
  [ "$fwd" -eq 1 ]
  [ "$term_absent" -eq 1 ]
}

@test "feature-loop-docker omits display-control env that is not set" {
  # The forwarding is conditional: an unset var must not appear as a bare `-e VAR`
  # (which would clear it inside the container, or worse leak the host's empty value).
  tmp="$(mktemp -d)"
  stub="$(mktemp -d)"
  _stub_docker_logging_args "$stub" "$tmp"

  (
    cd "$tmp" || exit 1
    git init -q
    echo 'FL_GATES=true' > .featureloop
    env -u FL_NO_SPINNER -u NO_COLOR -u FL_ASCII -u CI -u TERM \
      PATH="$stub:$PATH" ANTHROPIC_API_KEY=sk-test "$FLD" TKT slug
  ) > /dev/null 2>&1

  absent=1
  for v in FL_NO_SPINNER NO_COLOR FL_ASCII CI TERM; do
    grep -qx "$v" "$tmp/docker.log" && absent=0
  done

  rm -rf "$tmp" "$stub"
  [ "$absent" -eq 1 ]
}

@test "feature-loop-docker forwards TERM when attached to a PTY" {
  # The other half of the gate: when a PTY IS attached, the host's real TERM is
  # forwarded so the in-container engine can trust it and keep the live status (#40).
  # `script` gives the child both a stdin and stdout PTY so `-t 0 && -t 1` holds.
  command -v script > /dev/null 2>&1 || skip "script (util-linux) not available"

  tmp="$(mktemp -d)"
  stub="$(mktemp -d)"
  _stub_docker_logging_args "$stub" "$tmp"

  cat > "$tmp/runner.sh" << EOF
#!/usr/bin/env bash
cd "$tmp" || exit 1
export PATH="$stub:\$PATH" ANTHROPIC_API_KEY=sk-test TERM=xterm-256color
exec "$FLD" TKT slug
EOF
  chmod +x "$tmp/runner.sh"

  (
    cd "$tmp" || exit 1
    git init -q
    echo 'FL_GATES=true' > .featureloop
    script -qec "$tmp/runner.sh" /dev/null
  ) > /dev/null 2>&1

  term_fwd=0
  grep -qx TERM "$tmp/docker.log" && term_fwd=1

  rm -rf "$tmp" "$stub"
  [ "$term_fwd" -eq 1 ]
}

@test "feature-loop engine suppresses the spinner on a PTY under CI, TERM=dumb, or empty TERM (ISSUE-43)" {
  # The core regression guard. Run the engine on a real PTY (so `[ -t 1 ]` holds and
  # FL_TTY=1) but with CI=1 / TERM=dumb — the relay/headless signal. The spinner must
  # stand down: zero "bare" carriage returns (a CR not part of a \r\n line ending) in
  # the output. Color (\033) is intentionally still on for a PTY and is not asserted —
  # ISSUE-43 is the \r flood, not color. A slow `claude` stub keeps the build alive
  # long enough that an un-suppressed spinner WOULD emit frames (verified: ~12 bare CR
  # without the gate, 0 with it), so this fails loudly if the gate regresses.
  command -v script > /dev/null 2>&1 || skip "script (util-linux) not available"
  command -v perl > /dev/null 2>&1 || skip "perl not available"

  _bare_cr_under_pty() { # $1=env-line  -> echoes count of bare CR bytes
    local d ts
    d="$(mktemp -d)"
    ts="$d/ts"
    (
      cd "$d" || exit 1
      git init --bare -q up.git
      git init -q -b main work
      cd work || exit 1
      echo 'FL_GATES=true' > .featureloop
      mkdir tasks
      echo todo > tasks/plan.md
      echo x > README.md
      git add -A
      git -c user.email=t@t -c user.name=t commit -qm init
      git remote add origin ../up.git
      git push -q origin main
    ) > /dev/null 2>&1
    cat > "$d/slowclaude" << 'EOS'
#!/usr/bin/env bash
sleep 0.5
exit 0
EOS
    chmod +x "$d/slowclaude"
    cat > "$d/r.sh" << EOF
#!/usr/bin/env bash
cd "$d/work" || exit 1
export FL_CLAUDE="$d/slowclaude" FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$d/arc"
export FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$d/wt"
$1
exec "$FL" TKT slug
EOF
    chmod +x "$d/r.sh"
    script -qec "$d/r.sh" "$ts" > /dev/null 2>&1
    # bare CR = carriage returns that are NOT part of a \r\n line ending (the PTY
    # turns every \n into \r\n; the spinner adds bare \r that this strip leaves behind).
    perl -0777 -pe 's/\r\n//g' "$ts" | tr -cd '\r' | wc -c
    rm -rf "$d"
  }

  ci_cr="$(_bare_cr_under_pty 'export CI=1 TERM=xterm-256color')"
  dumb_cr="$(_bare_cr_under_pty 'export TERM=dumb')"
  # Issue headline case (plan.md Gap #2): a PTY with an empty TERM. TERM must be
  # EXPORTED empty, not `unset` — bash re-defaults an unset TERM to `dumb` at startup,
  # which would silently land in the dumb branch above and leave the `-z TERM` gate
  # branch (bin/feature-loop:194) untested. An exported-empty TERM is the only thing
  # that reaches it, so dropping that branch makes this case re-flood and fail.
  empty_cr="$(_bare_cr_under_pty 'unset CI; export TERM=')"
  # Symmetric positive guard (the fix's headline promise and the plan's named top
  # risk, plan.md:53,69): a genuine attached terminal — real TERM, CI unset — must
  # STILL animate. Every suppression case above stays green under an over-aggressive
  # gate (unconditional FL_ANIMATE=0, an inverted condition, a `[ -n "$TERM" ]` typo);
  # only this case catches a gate that silently drops #40's live status. Verified
  # non-vacuous in both directions: 12 bare CR against the current engine, 0 if the
  # gate is made unconditional.
  live_cr="$(_bare_cr_under_pty 'unset CI; export TERM=xterm-256color')"

  [ "$ci_cr" -eq 0 ]
  [ "$dumb_cr" -eq 0 ]
  [ "$empty_cr" -eq 0 ]
  [ "$live_cr" -gt 0 ]
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

# --- regression: marketplace name must differ from the plugin name (ISSUE-11) --------

@test "marketplace name differs from the plugin name" {
  # `feature-loop@feature-loop` reads as a typo: the marketplace (the registry) and
  # the plugin it contains shared the name `feature-loop`. The marketplace is now
  # `ecukalla-plugins` so the install command (`feature-loop@ecukalla-plugins`) is
  # self-explanatory and leaves room for sibling plugins. Guard the duplication from
  # silently returning.
  market_name="$(jq -r '.name' "$REPO_ROOT/.claude-plugin/marketplace.json")"
  plugin_name="$(jq -r '.name' "$REPO_ROOT/.claude-plugin/plugin.json")"
  if [ "$market_name" = "$plugin_name" ]; then
    echo "marketplace.json:.name ('$market_name') must differ from plugin.json:.name ('$plugin_name') — the duplication makes the install command read as 'feature-loop@feature-loop'" >&2
    return 1
  fi
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

# --- regression: CI must install the Claude CLI from the pinned lockfile (ISSUE-10) ---

@test "ci.yml does not install the Claude CLI unpinned" {
  # A bare `npm install -g @anthropic-ai/claude-code` pulls whatever `latest`
  # resolves to on every CI run — a supply-chain risk. The validate-plugin job
  # must install from the tracked tools/ lockfile instead. This regresses if the
  # unpinned global install (no @<version>, no lockfile) ever re-appears.
  run grep -nE 'npm install -g @anthropic-ai/claude-code([^@]|$)' \
    "$REPO_ROOT/.github/workflows/ci.yml"
  [ "$status" -ne 0 ]
}

@test "ci.yml installs the Claude CLI from the tools lockfile" {
  grep -q 'npm --prefix tools ci' "$REPO_ROOT/.github/workflows/ci.yml"
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

# --- regression: the devcontainer build workflow must stay protective (#30) ---

@test "devcontainer.yml smoke-tests every gate-toolchain binary" {
  # This workflow exists because a broken Dockerfile (the #18 xz-utils drop, #29 fix)
  # merged green since nothing built it. The fix is itself a test, but it only catches
  # that regression class while its smoke list stays complete — dropping a tool (e.g.
  # xz --version) would let the workflow pass green while no longer guarding the base.
  WF="$REPO_ROOT/.github/workflows/devcontainer.yml"
  for tool in "node --version" "go version" "pre-commit --version" \
    "bats --version" "jq --version" "xz --version"; do
    grep -qF "$tool" "$WF" || {
      echo "missing smoke check: $tool" >&2
      return 1
    }
  done
}

@test "devcontainer.yml is path-filtered to .devcontainer changes" {
  # The path filter is what makes the build trigger when the base could have changed.
  # If it stops covering .devcontainer/**, the workflow goes dormant and the regression
  # class returns silently.
  grep -qF '.devcontainer/**' "$REPO_ROOT/.github/workflows/devcontainer.yml"
}

# --- regression: a green run commits the /code-simplify changes (ISSUE-41) -----------

@test "green run commits the code-simplify changes, leaving a clean worktree" {
  # The /code-simplify agent is told NOT to commit, and the engine had no commit of
  # its own, so a green run left the simplify cleanup as uncommitted tracked changes:
  # the gate passed on bytes that only existed in the working tree, and pushing the
  # branch tip silently dropped them. The engine must commit the simplify diff after
  # the post-simplify gate passes. Stub claude appends to a tracked file ONLY on the
  # simplify call (matched by prompt), reproducing that uncommitted hunk.
  tmp="$(mktemp -d)"
  stub="$tmp/claude"
  cat > "$stub" << 'EOF'
#!/usr/bin/env bash
# feature-loop invokes: claude --dangerously-skip-permissions -p <prompt>
prompt="${*: -1}"
case "$prompt" in
  *simplification*) printf 'simplified\n' >> tracked.txt ;;
esac
exit 0
EOF
  chmod +x "$stub"

  wt="$tmp/wt"
  (
    cd "$tmp" || exit 1
    git init --bare -q upstream.git
    git init -q -b main work
    cd work || exit 1
    echo 'FL_GATES=true' > .featureloop
    mkdir tasks
    echo 'todo' > tasks/plan.md
    printf 'original\n' > tracked.txt
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../upstream.git
    git push -q origin main
    FL_CLAUDE="$stub" FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$tmp/arc" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1
  rc=$?

  # No uncommitted tracked changes remain (the simplify hunk was committed).
  clean=0
  [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ] && clean=1
  # And the simplify change actually landed in a commit, not just the working tree.
  committed=0
  git -C "$wt" show HEAD:tracked.txt 2> /dev/null | grep -q simplified && committed=1

  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$clean" -eq 1 ]
  [ "$committed" -eq 1 ]
}

# --- regression: a mid-run abort must not exit 0 (masked-green crash, ISSUE-45) -------

@test "a mid-run abort with a zero \$? exits non-zero and prints no green DONE banner" {
  # The EXIT trap (on_exit) used to inherit the script's \$?, so any abort that left
  # \$?==0 made a crashed run exit 0 — green to the docker wrapper, CI, and humans. The
  # masking class is a `set -u` fatal expansion (unbound scalar or empty-array) on
  # macOS's stock Bash 3.2, which enters the trap with \$?==0 (measured; Bash 5.x instead
  # leaves \$?==1, so a literal `set -u` abort would be a no-op guard on this CI). The
  # fix derives the exit code from the explicit OUTCOME signal, not \$?: only a run that
  # reached OUTCOME=green may exit 0. This drives that exact trap state — \$?==0 with
  # OUTCOME never green — deterministically and cross-version by aborting the engine with
  # a plain `exit 0` mid-flight: FL_GATES='exit 0' eval'd in the parent shell during the
  # gate phase. (The gate normally runs against a clean materialized checkout in a
  # subshell, which would swallow the exit; stubbing `git clone` to fail forces the
  # in-place fallback that eval's FL_GATES in the parent.) Pre-fix this exits 0; post-fix
  # it must exit non-zero and never reach the green DONE banner.
  tmp="$(mktemp -d)"
  stub="$tmp/stub"
  mkdir "$stub"
  realgit="$(command -v git)"
  cat > "$stub/git" << EOF
#!/usr/bin/env bash
# Fail only \`git clone\` (used solely by the gate's clean-tree materialization) so the
# engine falls back to eval'ing FL_GATES in the parent shell; delegate everything else.
[ "\$1" = clone ] && exit 1
exec "$realgit" "\$@"
EOF
  chmod +x "$stub/git"

  wt="$tmp/wt"
  rc=0
  # `|| rc=$?` keeps bats's errexit from aborting the test on the engine's (expected)
  # non-zero exit, and captures the real code to assert on.
  (
    cd "$tmp" || exit 1
    git init --bare -q upstream.git
    git init -q -b main work
    cd work || exit 1
    printf "FL_GATES='exit 0'\n" > .featureloop
    mkdir tasks
    echo 'todo' > tasks/plan.md
    echo x > README.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../upstream.git
    git push -q origin main
    PATH="$stub:$PATH" FL_CLAUDE=true FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$tmp/arc" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$wt" \
      "$FL" TKT slug
  ) > "$tmp/out.txt" 2>&1 || rc=$?

  no_done=0
  grep -qF 'DONE:' "$tmp/out.txt" || no_done=1

  rm -rf "$tmp"
  [ "$rc" -ne 0 ]
  [ "$no_done" -eq 1 ]
}

# --- per-phase timeout: a throttled/wedged claude -p can't hang the run (ISSUE-48) ----

@test "a gate whose claude call times out is marked failed, and the run doesn't hang" {
  # A gate's verdict is "did the agent write its failure file?". A timed-out call never
  # writes one, so without the guard it mis-reads as a pass. The engine must synthesize
  # the failure file on timeout so the loop treats the gate as failed. The stub sleeps
  # ONLY on the test-gate prompt, outlasting FL_PHASE_TIMEOUT=1; everything else is
  # instant. The run must end bounded (not hang on the 10s sleep) and not-green.
  command -v timeout > /dev/null 2>&1 || skip "timeout (GNU coreutils) not available"
  tmp="$(mktemp -d)"
  stub="$tmp/claude"
  cat > "$stub" << 'EOF'
#!/usr/bin/env bash
# feature-loop invokes: claude --dangerously-skip-permissions -p <prompt>
prompt="${*: -1}"
case "$prompt" in
  *test-driven-development*) sleep 10 ;; # the test gate — outlasts FL_PHASE_TIMEOUT
esac
exit 0
EOF
  chmod +x "$stub"

  wt="$tmp/wt"
  rc=0
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
    FL_CLAUDE="$stub" FL_MAX_ITERS=1 FL_PHASE_TIMEOUT=1 \
      FL_ARCHIVE_DIR="$tmp/arc" FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1 || rc=$? # not-green exits 1; capture it instead of aborting the test

  # The synthesized failure file names the timeout, and the run ended not-green
  # (exit 1) rather than hanging on the stub's 10s sleep.
  timed_out_marked=0
  grep -rqi "timed out" "$tmp/arc/runs"/TKT-*/failures/test.md 2> /dev/null && timed_out_marked=1

  rm -rf "$tmp"
  [ "$rc" -eq 1 ]
  [ "$timed_out_marked" -eq 1 ]
}

@test "a gate whose claude call crashes is marked failed, not read as green (ISSUE-57)" {
  # A gate's verdict is "did the agent write its failure file?". A claude -p call that
  # exits non-zero for any reason other than a timeout (auth/API error, OOM, plain crash)
  # never writes one either, so without the guard it mis-reads as a pass (green). The
  # engine must synthesize the failure file on any non-zero exit. The stub exits 3 ONLY on
  # the test-gate prompt (no failure file written); everything else is instant and green.
  # The run must end not-green (exit 1) with a synthesized failure naming the crash.
  tmp="$(mktemp -d)"
  stub="$tmp/claude"
  cat > "$stub" << 'EOF'
#!/usr/bin/env bash
# feature-loop invokes: claude --dangerously-skip-permissions -p <prompt>
prompt="${*: -1}"
case "$prompt" in
  *test-driven-development*) exit 3 ;; # the test gate — crashes without writing a verdict
esac
exit 0
EOF
  chmod +x "$stub"

  wt="$tmp/wt"
  rc=0
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
    FL_CLAUDE="$stub" FL_MAX_ITERS=1 \
      FL_ARCHIVE_DIR="$tmp/arc" FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1 || rc=$? # not-green exits 1; capture it instead of aborting the test

  # The synthesized failure file names the crash and exit code, and the run ended not-green
  # (exit 1) rather than mis-reading the crashed gate as a pass.
  crash_marked=0
  grep -rqi "crashed (exit 3)" "$tmp/arc/runs"/TKT-*/failures/test.md 2> /dev/null && crash_marked=1

  rm -rf "$tmp"
  [ "$rc" -eq 1 ]
  [ "$crash_marked" -eq 1 ]
}

@test "a code-simplify timeout ships the green tip instead of failing the run" {
  # Simplify is optional post-green polish; a timeout there must not sink an
  # already-green tip. The stub sleeps ONLY on the simplify prompt (outlasting
  # FL_PHASE_TIMEOUT=1); the build + gates are instant and green. The run must end
  # green with a clean worktree (any partial simplify edit discarded).
  command -v timeout > /dev/null 2>&1 || skip "timeout (GNU coreutils) not available"
  tmp="$(mktemp -d)"
  stub="$tmp/claude"
  cat > "$stub" << 'EOF'
#!/usr/bin/env bash
prompt="${*: -1}"
case "$prompt" in
  *code-simplification*) sleep 10 ;; # simplify — outlasts FL_PHASE_TIMEOUT
esac
exit 0
EOF
  chmod +x "$stub"

  wt="$tmp/wt"
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
    FL_CLAUDE="$stub" FL_MAX_ITERS=1 FL_PHASE_TIMEOUT=1 \
      FL_ARCHIVE_DIR="$tmp/arc" FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1
  rc=$?

  green=0
  grep -q '"outcome": *"green"' "$tmp/arc/runs"/TKT-*/summary.json 2> /dev/null && green=1
  clean=0
  [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ] && clean=1

  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$green" -eq 1 ]
  [ "$clean" -eq 1 ]
}

# --- optional API-spend cap: --max-budget-usd is opt-in (ISSUE-48) -------------------

# Run a full green loop with a claude stub that appends its argv (one arg per line) to
# $1, then echo whether `--max-budget-usd` was passed. $2 is extra env for the engine.
_engine_claude_argv() { # $1=argv-log  $2=extra-env -> stdout: "yes"/"no"
  local argslog="$1" extra="$2" d
  d="$(mktemp -d)"
  cat > "$d/claude" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$argslog"
exit 0
EOF
  chmod +x "$d/claude"
  (
    cd "$d" || exit 1
    git init --bare -q up.git
    git init -q -b main work
    cd work || exit 1
    echo 'FL_GATES=true' > .featureloop
    mkdir tasks
    echo todo > tasks/plan.md
    echo x > README.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../up.git
    git push -q origin main
    eval "export $extra"
    FL_CLAUDE="$d/claude" FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$d/arc" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$d/wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1
  if grep -qFx -- '--max-budget-usd' "$argslog"; then echo yes; else echo no; fi
  rm -rf "$d"
}

@test "FL_MAX_BUDGET_USD passes --max-budget-usd to the claude phase calls when set" {
  log="$(mktemp)"
  result="$(_engine_claude_argv "$log" 'FL_MAX_BUDGET_USD=5')"
  passed_value=0
  grep -qFx '5' "$log" && passed_value=1
  rm -f "$log"
  [ "$result" = yes ]
  [ "$passed_value" -eq 1 ]
}

@test "the claude phase calls omit --max-budget-usd when FL_MAX_BUDGET_USD is unset" {
  # Opt-in: a bogus flag must never be passed by default (the pinned CLI would error).
  log="$(mktemp)"
  result="$(_engine_claude_argv "$log" 'PATH=$PATH')"
  rm -f "$log"
  [ "$result" = no ]
}

# --- progress heartbeat: slow ≠ silent in headless logs (ISSUE-48) ------------------

@test "a slow phase emits a plain heartbeat tick off-TTY" {
  # Off-TTY the spinner is a no-op, so a long phase looked identical to a hang. The
  # heartbeat must emit a "still running" line (and stay plain — no CR/ESC). The stub
  # sleeps only on the build prompt, outlasting FL_HEARTBEAT_SECS=1; bats runs off-TTY.
  tmp="$(mktemp -d)"
  stub="$tmp/claude"
  cat > "$stub" << 'EOF'
#!/usr/bin/env bash
prompt="${*: -1}"
case "$prompt" in
  *incremental-implementation*) sleep 2 ;; # the build (writer) phase
esac
exit 0
EOF
  chmod +x "$stub"

  out="$tmp/out.txt"
  wt="$tmp/wt"
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
    FL_CLAUDE="$stub" FL_MAX_ITERS=1 FL_HEARTBEAT_SECS=1 \
      FL_ARCHIVE_DIR="$tmp/arc" FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$wt" \
      "$FL" TKT slug
  ) > "$out" 2>&1
  rc=$?

  ticked=0
  grep -qF 'still running' "$out" && ticked=1
  # The tick must stay plain — no CR or ESC in the captured stream.
  plain=1
  grep -q "$(printf '\r')" "$out" && plain=0
  grep -q "$(printf '\033')" "$out" && plain=0

  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$ticked" -eq 1 ]
  [ "$plain" -eq 1 ]
}

# --- commit attribution suppression / opt-out (ISSUE-50) -----------------------------
#
# Every claude call the engine makes must carry --settings disabling the
# "Co-Authored-By: Claude" / "Generated with Claude Code" trailer by default, so the
# loop's commits honor the no-AI-attribution convention. The host ~/.claude is never
# mounted, so --settings (which outranks every settings.json scope but "managed") is
# how the convention reaches the in-container agent. FL_COMMIT_ATTRIBUTION=1 opts out.

# Run the engine once with a claude stub that logs its argv to $tmp/claude-args.log,
# leaving the log at "$1/claude-args.log". $2 is an extra line for .featureloop
# (e.g. an opt-out toggle); $3..  are extra `VAR=value` env prefixes for the engine.
_run_engine_logging_claude_args() {
  local tmp="$1" extra_cfg="$2"
  shift 2
  local stub="$tmp/claude"
  cat > "$stub" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$tmp/claude-args.log"
exit 0
EOF
  chmod +x "$stub"
  (
    cd "$tmp" || exit 1
    git init --bare -q up.git
    git init -q -b main work
    cd work || exit 1
    {
      echo 'FL_GATES=true'
      [ -n "$extra_cfg" ] && echo "$extra_cfg"
    } > .featureloop
    mkdir tasks
    echo todo > tasks/plan.md
    echo x > README.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../up.git
    git push -q origin main
    env "$@" \
      FL_CLAUDE="$stub" FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$tmp/arc" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$tmp/wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1
}

@test "engine suppresses commit attribution by default (passes --settings to claude)" {
  tmp="$(mktemp -d)"
  _run_engine_logging_claude_args "$tmp" ""
  rc=$?
  has_flag=0
  suppresses=0
  grep -qxF -- '--settings' "$tmp/claude-args.log" && has_flag=1
  grep -qF '"includeCoAuthoredBy":false' "$tmp/claude-args.log" &&
    grep -qF '"attribution":{"commit":"","pr":""}' "$tmp/claude-args.log" && suppresses=1
  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$has_flag" -eq 1 ]
  [ "$suppresses" -eq 1 ]
}

@test "engine restores attribution with FL_COMMIT_ATTRIBUTION=1 from the environment" {
  tmp="$(mktemp -d)"
  _run_engine_logging_claude_args "$tmp" "" FL_COMMIT_ATTRIBUTION=1
  rc=$?
  no_flag=1
  grep -qxF -- '--settings' "$tmp/claude-args.log" && no_flag=0
  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$no_flag" -eq 1 ]
}

@test "engine reads the FL_COMMIT_ATTRIBUTION opt-out from .featureloop" {
  tmp="$(mktemp -d)"
  _run_engine_logging_claude_args "$tmp" 'FL_COMMIT_ATTRIBUTION=1'
  rc=$?
  no_flag=1
  grep -qxF -- '--settings' "$tmp/claude-args.log" && no_flag=0
  rm -rf "$tmp"
  [ "$rc" -eq 0 ]
  [ "$no_flag" -eq 1 ]
}

# --- --dry-run / --hermetic: run the whole loop with zero Claude calls (ISSUE-15) -----

@test "feature-loop --help documents --dry-run and --hermetic" {
  run "$FL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--hermetic"* ]]
}

@test "feature-loop --hermetic without --dry-run errors" {
  # --hermetic only stubs FL_GATES on top of a dry-run; on its own it is meaningless,
  # so it must error rather than silently doing nothing (or implying --dry-run).
  run "$FL" --hermetic TKT slug
  [ "$status" -eq 2 ]
  [[ "$output" == *"--hermetic requires --dry-run"* ]]
}

@test "feature-loop --dry-run runs the whole loop without ever invoking claude" {
  # The flag forces the FL_CLAUDE=true no-op seam AFTER config sourcing, so NO env
  # FL_CLAUDE is set here: a canary `claude` on PATH proves the flag (not the env) is
  # what suppresses every token-spending call. If the seam regressed, the canary would
  # run and leave its marker, and this fails loudly.
  tmp="$(mktemp -d)"
  stub="$(mktemp -d)"
  cat > "$stub/claude" << EOF
#!/usr/bin/env bash
echo CALLED >> "$tmp/claude.calls"
exit 0
EOF
  chmod +x "$stub/claude"

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
    PATH="$stub:$PATH" FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$tmp/arc" \
      FL_BASE_BRANCH=main FL_WT_DIR="$tmp/wt" \
      "$FL" --dry-run TKT slug
  ) > /dev/null 2>&1
  rc=$?

  never_called=0
  [ ! -f "$tmp/claude.calls" ] && never_called=1
  green=0
  grep -q '"outcome":        "green"' "$tmp/arc/runs"/TKT-*/summary.json 2> /dev/null && green=1

  rm -rf "$tmp" "$stub"
  [ "$rc" -eq 0 ]
  [ "$never_called" -eq 1 ]
  [ "$green" -eq 1 ]
}

@test "feature-loop --dry-run honours real gates; --hermetic stubs them green" {
  # Plain --dry-run runs the REAL FL_GATES (only Claude is stubbed), so a failing gate
  # (`exit 7`) keeps the run non-green. --hermetic additionally stubs FL_GATES=true, so
  # the same repo reaches green — proving the two flags are distinct.
  _run_gate7() { # $1=extra-flags -> sets global rc (non-green is expected, so capture
    # the status with `|| rc=$?` rather than `rc=$?` on its own line — a bare failing
    # subshell trips bats's per-command failure check before the capture runs).
    local d
    d="$(mktemp -d)"
    rc=0
    (
      cd "$d" || exit 1
      git init --bare -q upstream.git
      git init -q -b main work
      cd work || exit 1
      echo "FL_GATES='exit 7'" > .featureloop
      mkdir tasks
      echo 'todo' > tasks/plan.md
      echo x > README.md
      git add -A
      git -c user.email=t@t -c user.name=t commit -qm init
      git remote add origin ../upstream.git
      git push -q origin main
      FL_CLAUDE=true FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$d/arc" FL_BASE_BRANCH=main \
        FL_RETROSPECTIVE=0 FL_WT_DIR="$d/wt" \
        "$FL" $1 TKT slug
    ) > /dev/null 2>&1 || rc=$?
    rm -rf "$d"
  }

  _run_gate7 "--dry-run"
  plain_rc="$rc"
  _run_gate7 "--dry-run --hermetic"
  herm_rc="$rc"

  [ "$plain_rc" -ne 0 ] # real gate `exit 7` fails -> not green
  [ "$herm_rc" -eq 0 ]  # hermetic stubs the gate -> green
}

@test "feature-loop tags summary.json dry_run by flag and by FL_DRY_RUN env" {
  # The tag must be conditional: true under --dry-run or FL_DRY_RUN=1, false otherwise.
  _dry_run_field() { # $1=flags $2=env-assignment -> echoes the dry_run JSON value
    local d
    d="$(mktemp -d)"
    (
      cd "$d" || exit 1
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
      env $2 FL_CLAUDE=true FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$d/arc" \
        FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$d/wt" \
        "$FL" $1 TKT slug
    ) > /dev/null 2>&1
    grep -o '"dry_run":[^,]*' "$d/arc/runs"/TKT-*/summary.json | tr -d ' '
    rm -rf "$d"
  }

  [ "$(_dry_run_field '' '')" = '"dry_run":false' ]
  [ "$(_dry_run_field '--dry-run' '')" = '"dry_run":true' ]
  [ "$(_dry_run_field '' 'FL_DRY_RUN=1')" = '"dry_run":true' ]
}

@test "feature-loop --dry-run cannot be re-armed by .featureloop (DRY_RUN clobber, ISSUE-15)" {
  # The dry-run decision is taken from the CLI/env only and snapshot-restored across
  # config sourcing, so a repo's .featureloop setting DRY_RUN=0 (or HERMETIC=1) must NOT
  # re-enable real Claude calls. .featureloop is sourced in the engine's own shell, so
  # before the fix those lines clobbered the user's --dry-run and the canary `claude` on
  # PATH ran 5 times; after it, the canary is never invoked and the run stays tagged.
  tmp="$(mktemp -d)"
  stub="$(mktemp -d)"
  cat > "$stub/claude" << EOF
#!/usr/bin/env bash
echo CALLED >> "$tmp/claude.calls"
exit 0
EOF
  chmod +x "$stub/claude"

  (
    cd "$tmp" || exit 1
    git init --bare -q upstream.git
    git init -q -b main work
    cd work || exit 1
    printf 'FL_GATES=true\nDRY_RUN=0\nHERMETIC=1\n' > .featureloop
    mkdir tasks
    echo 'todo' > tasks/plan.md
    echo x > README.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../upstream.git
    git push -q origin main
    PATH="$stub:$PATH" FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$tmp/arc" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$tmp/wt" \
      "$FL" --dry-run TKT slug
  ) > /dev/null 2>&1
  rc=$?

  never_called=0
  [ ! -f "$tmp/claude.calls" ] && never_called=1
  dry_tagged=0
  grep -q '"dry_run":        true' "$tmp/arc/runs"/TKT-*/summary.json 2> /dev/null && dry_tagged=1

  rm -rf "$tmp" "$stub"
  [ "$rc" -eq 0 ]
  [ "$never_called" -eq 1 ]
  [ "$dry_tagged" -eq 1 ]
}

# --- dry-run (dry-run) markers in the rendered archive artefacts (ISSUE-15, Task 2) ---
#
# summary.json's dry_run boolean is covered above; these guard the three human-readable
# markers the plan also enumerates — STATUS.md title, summary.md Outcome, INDEX.md cell —
# plus the INDEX "column count unchanged" invariant. Each is implemented but was
# otherwise unasserted, so a future edit could drop or malform one (e.g. shift the INDEX
# table) with the suite still green.

# Build a one-commit repo under $1 and run feature-loop with flags $2 (FL_GATES=$3);
# artefacts land in $1/arc (archive) and $1/wt (worktree). FL_CLAUDE=true so the loop
# is a no-op writer regardless of the flags under test.
_dry_run_archive() {
  local d="$1" flags="$2" gates="$3"
  (
    cd "$d" || exit 1
    git init --bare -q upstream.git
    git init -q -b main work
    cd work || exit 1
    echo "FL_GATES=$gates" > .featureloop
    mkdir tasks
    echo 'todo' > tasks/plan.md
    echo x > README.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git remote add origin ../upstream.git
    git push -q origin main
    FL_CLAUDE=true FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$d/arc" \
      FL_BASE_BRANCH=main FL_RETROSPECTIVE=0 FL_WT_DIR="$d/wt" \
      "$FL" $flags TKT slug
  ) > /dev/null 2>&1
}

@test "feature-loop --dry-run marks the STATUS.md title; a normal run does not" {
  tmp="$(mktemp -d)"
  _dry_run_archive "$tmp" "--dry-run" "true"
  dry_status="$(cat "$tmp/arc/runs"/TKT-*/STATUS.md 2> /dev/null)"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"
  _dry_run_archive "$tmp" "" "true"
  plain_status="$(cat "$tmp/arc/runs"/TKT-*/STATUS.md 2> /dev/null)"
  rm -rf "$tmp"

  [[ "$dry_status" == *"feature-loop (dry-run)"* ]]
  [[ "$plain_status" != *"(dry-run)"* ]]
}

@test "feature-loop --hermetic marks the summary.md Outcome line; a normal run does not" {
  # --hermetic so a no-gate repo reaches green and the Outcome is **green** (dry-run).
  tmp="$(mktemp -d)"
  _dry_run_archive "$tmp" "--dry-run --hermetic" "true"
  dry_outcome="$(grep '^- Outcome:' "$tmp/arc/runs"/TKT-*/summary.md 2> /dev/null)"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"
  _dry_run_archive "$tmp" "" "true"
  plain_outcome="$(grep '^- Outcome:' "$tmp/arc/runs"/TKT-*/summary.md 2> /dev/null)"
  rm -rf "$tmp"

  [[ "$dry_outcome" == *"**green** (dry-run)"* ]]
  [[ "$plain_outcome" != *"(dry-run)"* ]]
}

@test "feature-loop --dry-run marks the INDEX.md outcome cell without shifting columns" {
  tmp="$(mktemp -d)"
  _dry_run_archive "$tmp" "--dry-run" "true"
  row="$(grep '^| TKT-' "$tmp/arc/INDEX.md" 2> /dev/null)"
  ncols="$(printf '%s\n' "$row" | awk -F'|' '{print NF}')"
  rm -rf "$tmp"

  [[ "$row" == *"green (dry-run)"* ]]
  # `| a | b | c | d | e |` is 5 columns = 7 awk fields (leading + trailing empties).
  # The marker lives inside a cell, so it must not add or shift a pipe.
  [ "$ncols" -eq 7 ]
}

# --- regression: Ctrl-C / SIGINT must not fire the billable retrospective (ISSUE-58) --

@test "an interrupted run (SIGINT) skips the billable retrospective" {
  # Ctrl-C routes through the EXIT trap so the run still archives — but the retrospective
  # is a billable `claude -p` call, and interrupting a run to STOP it must not spend
  # tokens on a reflection. The stub records every prompt it is handed; the build call
  # blocks (so the engine is mid-run, parked in its phase `wait`, when the signal lands)
  # while the retrospective prompt — if it were ever issued — returns at once and leaves
  # its tell-tale line in the log for the assertion to catch.
  tmp="$(mktemp -d)"
  stub="$tmp/stub"
  mkdir "$stub"
  cat > "$stub/claude" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/claude.calls"
case "\$*" in
  *retrospective*) exit 0 ;;  # never block; its presence in the log fails the test
esac
: > "$tmp/building"            # signal the harness that the build phase has started
sleep 30                       # hold the engine in its phase \`wait\` until interrupted
exit 0
EOF
  chmod +x "$stub/claude"

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
  ) > /dev/null 2>&1

  # Run the engine in the background. `exec` makes $! the engine process itself (not the
  # wrapping subshell), so `kill -INT` lands on the very process whose INT trap is under
  # test. FL_RETROSPECTIVE is left at its default (enabled): the skip must come from the
  # interrupt, not from the opt-out.
  (cd "$tmp/work" && exec env PATH="$stub:$PATH" FL_NO_SPINNER=1 FL_MAX_ITERS=1 \
    FL_ARCHIVE_DIR="$tmp/arc" FL_BASE_BRANCH=main FL_WT_DIR="$tmp/wt" \
    "$FL" TKT slug) > /dev/null 2>&1 &
  pid=$!

  # Deterministically (with a 10s ceiling) wait until the build phase is actually running
  # before interrupting, so the signal always lands mid-run rather than racing startup.
  built=0
  for _ in $(seq 1 100); do
    [ -f "$tmp/building" ] && {
      built=1
      break
    }
    sleep 0.1
  done
  kill -INT "$pid"
  rc=0
  wait "$pid" || rc=$?

  retro_called=0
  grep -q retrospective "$tmp/claude.calls" 2> /dev/null && retro_called=1
  build_called=0
  [ -s "$tmp/claude.calls" ] && build_called=1

  rm -rf "$tmp"
  [ "$built" -eq 1 ]        # we really did interrupt mid-build
  [ "$build_called" -eq 1 ] # sanity: the loop ran and issued the build call
  [ "$rc" -eq 130 ]         # 128 + SIGINT: the INT trap's exit code
  [ "$retro_called" -eq 0 ] # the billable retrospective was NOT issued
}

@test "a normal (uninterrupted) run still writes the retrospective" {
  # Guards the skip above against over-reach: with no interrupt and the retrospective
  # enabled (default), a green run MUST still issue the billable retrospective call.
  tmp="$(mktemp -d)"
  stub="$tmp/stub"
  mkdir "$stub"
  cat > "$stub/claude" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/claude.calls"
exit 0
EOF
  chmod +x "$stub/claude"

  rc=0
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
    PATH="$stub:$PATH" FL_NO_SPINNER=1 FL_MAX_ITERS=1 FL_ARCHIVE_DIR="$tmp/arc" \
      FL_BASE_BRANCH=main FL_WT_DIR="$tmp/wt" \
      "$FL" TKT slug
  ) > /dev/null 2>&1 || rc=$?

  retro_called=0
  grep -q retrospective "$tmp/claude.calls" 2> /dev/null && retro_called=1

  rm -rf "$tmp"
  [ "$rc" -eq 0 ]           # reached green
  [ "$retro_called" -eq 1 ] # the retrospective ran on a normal finish
}
