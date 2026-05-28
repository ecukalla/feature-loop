#!/usr/bin/env bash
#
# lint-plugin-manifests — defects that `claude plugin validate --strict` misses:
#  1. invalid semver in `.claude-plugin/plugin.json:.version`
#  2. invalid semver in `.claude-plugin/marketplace.json:.plugins[].version` (if set)
#  3. `marketplace.json:.plugins[].source` paths that don't resolve on disk
#
# Usage: scripts/lint-plugin-manifests.sh [ROOT]
#   ROOT defaults to the repo root (parent of this script). Used by bats for
#   per-test fixture dirs.
#
# Requires: jq.
set -euo pipefail

# SemVer 2.0.0 — https://semver.org/#backusnaur-form-grammar-for-valid-semver-versions
# Simplified: MAJOR.MINOR.PATCH with optional -PRERELEASE and +BUILD metadata.
readonly SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PLUGIN="$ROOT/.claude-plugin/plugin.json"
MARKET="$ROOT/.claude-plugin/marketplace.json"

errors=0

check_semver() {
  local where="$1" value="$2"
  [[ "$value" =~ $SEMVER_RE ]] || {
    echo "ERROR: $where '$value' is not valid semver" >&2
    errors=$((errors + 1))
  }
}

if [ -f "$PLUGIN" ]; then
  version="$(jq -r '.version // empty' "$PLUGIN")"
  [ -n "$version" ] && check_semver "plugin.json:.version" "$version"
fi

if [ -f "$MARKET" ]; then
  i=0
  while IFS= read -r entry_version; do
    [ -n "$entry_version" ] && check_semver "marketplace.json:.plugins[$i].version" "$entry_version"
    i=$((i + 1))
  done < <(jq -r '.plugins[].version // ""' "$MARKET")

  i=0
  while IFS= read -r src; do
    if [ -n "$src" ] && [ ! -e "$ROOT/$src" ]; then
      echo "ERROR: marketplace.json:.plugins[$i].source '$src' does not resolve under $ROOT" >&2
      errors=$((errors + 1))
    fi
    i=$((i + 1))
  done < <(jq -r '.plugins[].source // ""' "$MARKET")
fi

if [ "$errors" -gt 0 ]; then
  echo "✘ Manifest lint failed ($errors)" >&2
  exit 1
fi
echo "✔ Manifest lint passed"
