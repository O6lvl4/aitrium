#!/usr/bin/env bash
# Builds aitrium with everything it runs, for this machine, as one archive:
#
#   OUT/aitrium-TARGET.tar.gz      aitrium-TARGET/{aitrium, comide, golemide, porta,
#                                  gramide, hew, ctxgate, bridge/claude_bridge.py, PARTS}
#   OUT/aitrium-TARGET.tar.gz.sha256
#
# TARGET is darwin-arm64, linux-x86_64, … The parts are built at the commits dist/PARTS
# names, aitrium at this checkout's. On Linux, run it on the oldest glibc the archive
# should start on (scripts/package-linux.sh does, in Debian bullseye: glibc 2.31).
#
#   scripts/package.sh [OUT]            (default OUT: dist/out)
#   ALMIDE=/path/to/almide scripts/package.sh   build with this compiler, not the pinned one
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mkdir -p "${1:-$ROOT/dist/out}" && cd "${1:-$ROOT/dist/out}" && pwd)"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"; [ "$os" = darwin ] && [ "$arch" = aarch64 ] && arch=arm64
TARGET="$os-$arch"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ref_of() { awk -v n="$1" '$1 == n { print $3 }' "$ROOT/dist/PARTS"; }
repo_of() { awk -v n="$1" '$1 == n { print $2 }' "$ROOT/dist/PARTS"; }

fetch() {
  local name="$1" dir="$WORK/src/$1"
  git init -q "$dir"
  git -C "$dir" fetch -q --depth 1 "https://github.com/$(repo_of "$name")" "$(ref_of "$name")"
  git -C "$dir" checkout -q FETCH_HEAD
}

# Built quietly; the log's tail when it fails.
build() {
  local dir="$1" out="$2"
  ( cd "$dir" && "$ALMIDE" build --release src/main.almd -o "$out" ) > "$WORK/build.log" 2>&1 \
    || { echo "== building $out in $dir failed" >&2; tail -30 "$WORK/build.log" >&2; exit 1; }
}

if [ -z "${ALMIDE:-}" ]; then
  echo "== almide $(ref_of almide)"
  fetch almide
  cargo build --release --locked --bin almide --manifest-path "$WORK/src/almide/Cargo.toml" > "$WORK/build.log" 2>&1 \
    || { tail -30 "$WORK/build.log" >&2; exit 1; }
  ALMIDE="$WORK/src/almide/target/release/almide"
fi
"$ALMIDE" --version

stage="$WORK/aitrium-$TARGET"
mkdir -p "$stage/bridge"
for part in porta:porta comide:comide golemide:golemide gramide-cli:gramide hew:hew ctxgate:ctxgate; do
  name="${part%%:*}" bin="${part##*:}"
  echo "== $bin $(ref_of "$name")"
  fetch "$name"
  build "$WORK/src/$name" "$stage/$bin"
done
echo "== aitrium $(git -C "$ROOT" rev-parse HEAD)"
build "$ROOT" "$stage/aitrium"
cp "$ROOT/bridge/claude_bridge.py" "$stage/bridge/"
cp "$ROOT/README.md" "$ROOT/LICENSE-MIT" "$ROOT/LICENSE-APACHE" "$stage/"
{ grep -v '^#' "$ROOT/dist/PARTS" | awk 'NF { print $1, $2, $3 }'; echo "aitrium O6lvl4/aitrium $(git -C "$ROOT" rev-parse HEAD)"; } > "$stage/PARTS"

"$stage/porta" run --help | grep -q -- --credential \
  || { echo "porta has no --credential: aitrium's broker needs it (almide/porta#42)" >&2; exit 1; }
if [ "$os" = linux ]; then
  ! ldd "$stage"/* 2>/dev/null | grep -q 'libssl' || { echo "a binary links libssl" >&2; exit 1; }
  echo "needs glibc $(objdump -T "$stage"/aitrium "$stage"/comide "$stage"/golemide "$stage"/porta "$stage"/gramide "$stage"/hew "$stage"/ctxgate \
    | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"
fi

tar -C "$WORK" -czf "$OUT/aitrium-$TARGET.tar.gz" "aitrium-$TARGET"
( cd "$OUT" && { command -v sha256sum > /dev/null && sha256sum "aitrium-$TARGET.tar.gz" || shasum -a 256 "aitrium-$TARGET.tar.gz"; } > "aitrium-$TARGET.tar.gz.sha256" )
ls -l "$OUT/aitrium-$TARGET.tar.gz"
