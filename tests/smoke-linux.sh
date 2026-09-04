#!/usr/bin/env bash
# tests/smoke-linux.sh — run the full Linux path in a container, then doctor it.
# Skips what a container cannot provide: Docker-in-Docker, GitHub auth, private repos,
# /etc/hosts + mkcert, and the project installs that need the private registries.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SKIPS="docker,github-auth,clone-repos,project-deps,local-dev-wiring"
PLATFORM="${SMOKE_PLATFORM:-linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
IMAGE="workspace-installer-smoke"

docker build --platform "$PLATFORM" -t "$IMAGE" -f tests/Dockerfile.ubuntu .
docker run --rm --platform "$PLATFORM" "$IMAGE" bash -lc "
  set -euo pipefail
  ./bootstrap.sh --yes --skip $SKIPS
  ./doctor.sh --skip $SKIPS
"
