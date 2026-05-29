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

# System toolchain: pre-commit (gate driver), bats (test runner), jq (manifest-lint
# helper), and xz-utils — needed to unpack the Node `.tar.xz` below and NOT present in
# the golang base, so it must be installed before the Node step. pre-commit is installed
# via pipx into /usr/local/bin so it is on the non-root user's PATH. Pinned to a known
# version so the gate toolchain is reproducible (same pin discipline as the Go base,
# Node, and every pre-commit hook rev).
ENV PRE_COMMIT_VERSION=4.6.0
RUN apt-get update \
  && apt-get install -y --no-install-recommends xz-utils bats jq pipx \
  && rm -rf /var/lib/apt/lists/* \
  && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install "pre-commit==${PRE_COMMIT_VERSION}" \
  && chmod -R a+rX /opt/pipx

# Node, pinned to match the overlay (docker/overlay-bootstrap.sh), unpacked into /usr/local.
# The expected SHA-256 is pinned literally here (per arch, from the release's SHASUMS256.txt)
# rather than fetched at build time: a fetched checksum shares the tarball's origin, so an
# attacker who can tamper with one can tamper with both. Pinning the hash in this tracked,
# reviewed file means a substituted tarball — corrupted, truncated, or maliciously swapped —
# fails the build instead of landing on PATH for the gate run. (Bump both hashes with NODE_VERSION.)
ENV NODE_SHA256_x64=00bbd05e306ea68b6e13e17360d0e2f680b493ef95f2fea1c4296ff7437530bc \
    NODE_SHA256_arm64=06907b9c088ce62305bc1530e5c1ae1510245114645768f7750c349c5b6fe667
RUN arch="$(dpkg --print-architecture)" \
  && case "$arch" in arm64) na=arm64; sha="$NODE_SHA256_arm64" ;; *) na=x64; sha="$NODE_SHA256_x64" ;; esac \
  && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${na}.tar.xz" -o /tmp/node.tar.xz \
  && printf '%s  /tmp/node.tar.xz\n' "$sha" | sha256sum -c - \
  && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
  && rm -f /tmp/node.tar.xz
