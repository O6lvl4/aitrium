#!/usr/bin/env bash
# scripts/package.sh in a Rust container with the musl target and musl-gcc, so every
# binary in the Linux archive is static and starts on any Linux of its architecture.
#
#   scripts/package-linux.sh [OUT]      PLATFORM=linux/amd64 scripts/package-linux.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mkdir -p "${1:-$ROOT/dist/out}" && cd "${1:-$ROOT/dist/out}" && pwd)"
docker run --rm ${PLATFORM:+--platform "$PLATFORM"} \
  -v "$ROOT:/aitrium:ro" -v "$OUT:/out" rust:1-bookworm \
  bash -c 'apt-get -qq update > /dev/null && apt-get -qq install -y musl-tools file > /dev/null \
    && rustup target add "$(uname -m)-unknown-linux-musl" > /dev/null \
    && git config --global --add safe.directory "*" && cp -r /aitrium /tmp/aitrium \
    && /tmp/aitrium/scripts/package.sh /out && chown -R '"$(id -u):$(id -g)"' /out'
