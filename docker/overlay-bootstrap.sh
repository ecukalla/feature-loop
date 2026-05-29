#!/usr/bin/env bash
#
# overlay-bootstrap — idempotently inject what feature-loop needs onto ANY base
# image: git, a recent Node, the Claude CLI, the agent-skills plugin, and a non-root
# runtime user (Claude refuses --dangerously-skip-permissions as root).
#
# Runs as root during `docker build` of the overlay. Assumes a Debian/Ubuntu-family
# base (apt). For non-apt bases, pre-bake these yourself or use an apt-based image.
set -eu

NODE_VERSION="${NODE_VERSION:-22.20.0}"
# Pinned agent-skills commit (override to move it). Installed from a local clone, so
# `claude plugin install` never clones from github (slim images have no ssh client).
AGENT_SKILLS_REF="${AGENT_SKILLS_REF:-7338cf0a5a9557275e3cd8dc520002e59215e0a7}"
export DEBIAN_FRONTEND=noninteractive

if ! command -v apt-get > /dev/null 2>&1; then
  echo "ERROR: non-apt base image. Pre-bake claude + agent-skills, or use a Debian/Ubuntu base." >&2
  exit 1
fi

apt_install() { apt-get update && apt-get install -y --no-install-recommends "$@" && rm -rf /var/lib/apt/lists/*; }

# 1) base utilities
need=""
for b in git curl ca-certificates xz-utils; do command -v "${b%%-*}" > /dev/null 2>&1 || need="$need $b"; done
[ -n "$need" ] && apt_install $need || true

# 2) Node >= 18 (Claude CLI needs it)
node_ok=0
if command -v node > /dev/null 2>&1; then
  major="$(node -v | sed 's/^v//' | cut -d. -f1)"
  [ "$major" -ge 18 ] && node_ok=1
fi
if [ "$node_ok" -ne 1 ]; then
  arch="$(dpkg --print-architecture 2> /dev/null || echo amd64)"
  case "$arch" in arm64) na=arm64 ;; *) na=x64 ;; esac
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${na}.tar.xz" -o /tmp/node.tar.xz
  tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1
  rm -f /tmp/node.tar.xz
fi

# 3) Claude CLI (global). Pinned: 2.1.154 (the Opus 4.8 launch) wedges headless `-p`
#    runs with a 400 "thinking blocks cannot be modified" — see #27, anthropics/claude-code#63247.
command -v claude > /dev/null 2>&1 || npm install -g @anthropic-ai/claude-code@2.1.156

# 4) non-root runtime user
id -u fluser > /dev/null 2>&1 || useradd -m -s /bin/bash fluser

# 5) agent-skills plugin. Clone over HTTPS, repoint its marketplace at the local copy
#    so `claude plugin install` installs from disk (no github/ssh clone), then install
#    for fluser.
if ! su - fluser -c "claude plugin list 2>/dev/null | grep -q agent-skills"; then
  rm -rf /opt/agent-skills
  git clone https://github.com/addyosmani/agent-skills /opt/agent-skills
  git -C /opt/agent-skills checkout --quiet "$AGENT_SKILLS_REF"
  node -e 'const f="/opt/agent-skills/.claude-plugin/marketplace.json";const fs=require("fs");const m=JSON.parse(fs.readFileSync(f));m.plugins[0].source="./";fs.writeFileSync(f,JSON.stringify(m,null,2));'
  chmod -R a+rX /opt/agent-skills
  su - fluser -c "claude plugin marketplace add /opt/agent-skills \
    && claude plugin install agent-skills@addy-agent-skills \
    && claude plugin list"
fi
