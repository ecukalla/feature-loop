# This repo's own gate toolchain. feature-loop is generic — bring your own base;
# see examples/.featureloop.
#
# feature-loop wraps whatever base you name with its overlay (Claude CLI + agent-skills
# + the engine) at run time, so this image is PURE TOOLCHAIN: only what this repo's gate
# chain — `pre-commit run --all-files && bats tests/` — needs to pass.
#
#   - Go base: the actionlint, gitleaks, and shfmt pre-commit hooks build under
#     `language: golang`, so a Go toolchain has to be on PATH.
#   - Node: markdownlint-cli runs under pre-commit's `language: node`; a system Node
#     keeps hook setup fast and offline-friendly.
#   - pre-commit drives the gate; bats runs tests/; jq backs the manifest-lint hook.
#
# Tools install to system paths (/usr/local) so the non-root user the overlay creates
# can use them.
FROM golang:1.25-bookworm

ENV NODE_VERSION=22.20.0 \
    DEBIAN_FRONTEND=noninteractive

# Node, pinned to match the overlay (docker/overlay-bootstrap.sh), unpacked into /usr/local.
# The tarball is verified against the release's published SHASUMS256.txt before unpacking, so a
# corrupted or MITM'd download fails the build instead of landing on PATH for the gate run.
RUN arch="$(dpkg --print-architecture)" \
  && case "$arch" in arm64) na=arm64 ;; *) na=x64 ;; esac \
  && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${na}.tar.xz" -o /tmp/node.tar.xz \
  && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" -o /tmp/SHASUMS256.txt \
  && sha="$(grep "  node-v${NODE_VERSION}-linux-${na}.tar.xz\$" /tmp/SHASUMS256.txt | cut -d' ' -f1)" \
  && [ -n "$sha" ] && printf '%s  /tmp/node.tar.xz\n' "$sha" | sha256sum -c - \
  && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
  && rm -f /tmp/node.tar.xz /tmp/SHASUMS256.txt

# pre-commit (gate driver), bats (test runner), jq (manifest-lint helper). pre-commit
# is installed via pipx into /usr/local/bin so it is on the non-root user's PATH. Pinned
# to a known version so the gate toolchain is reproducible (same pin discipline as the Go
# base, Node, and every pre-commit hook rev).
ENV PRE_COMMIT_VERSION=4.6.0
RUN apt-get update \
  && apt-get install -y --no-install-recommends bats jq pipx \
  && rm -rf /var/lib/apt/lists/* \
  && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install "pre-commit==${PRE_COMMIT_VERSION}" \
  && chmod -R a+rX /opt/pipx
