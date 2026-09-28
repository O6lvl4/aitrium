#!/usr/bin/env bash
# scripts/package.sh inside Debian bullseye (glibc 2.31), so the Linux archive starts on
# every newer libc: Debian bookworm and trixie, Ubuntu 22.04 and 24.04, python:*-slim.
#
#   scripts/package-linux.sh [OUT]      PLATFORM=linux/amd64 scripts/package-linux.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mkdir -p "${1:-$ROOT/dist/out}" && cd "${1:-$ROOT/dist/out}" && pwd)"
docker run --rm ${PLATFORM:+--platform "$PLATFORM"} \
  -v "$ROOT:/aitrium:ro" -v "$OUT:/out" rust:1-bullseye \
  bash -c 'git config --global --add safe.directory "*" && cp -r /aitrium /tmp/aitrium \
    && /tmp/aitrium/scripts/package.sh /out && chown -R '"$(id -u):$(id -g)"' /out'
