#!/bin/sh
# Installs onogoro and everything it runs (comide, golemide, porta, …) from a release:
#
#   curl -fsSL https://raw.githubusercontent.com/O6lvl4/onogoro/main/install.sh | sh
#
# It unpacks into $PREFIX/share/onogoro and links $PREFIX/bin/onogoro to it; nothing else
# goes on PATH, so a comide or porta you already have is left as it is.
#
#   ONOGORO_PREFIX   where to install      (default: ~/.local)
#   ONOGORO_VERSION  a release tag, v0.1.0 (default: the latest)
#   ONOGORO_ARCHIVE  a local onogoro-TARGET.tar.gz to install instead of downloading
set -eu

PREFIX="${ONOGORO_PREFIX:-$HOME/.local}"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$os-$arch" in
  darwin-arm64 | darwin-aarch64) target=darwin-arm64 ;;
  linux-x86_64 | linux-amd64) target=linux-x86_64 ;;
  linux-aarch64 | linux-arm64) target=linux-aarch64 ;;
  *) echo "onogoro: no release for $os-$arch" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if [ -n "${ONOGORO_ARCHIVE:-}" ]; then
  cp "$ONOGORO_ARCHIVE" "$tmp/onogoro.tar.gz"
else
  case "${ONOGORO_VERSION:-latest}" in
    latest) base="https://github.com/O6lvl4/onogoro/releases/latest/download" ;;
    *) base="https://github.com/O6lvl4/onogoro/releases/download/$ONOGORO_VERSION" ;;
  esac
  echo "onogoro: downloading onogoro-$target.tar.gz"
  curl -fsSL "$base/onogoro-$target.tar.gz" -o "$tmp/onogoro.tar.gz"
  curl -fsSL "$base/onogoro-$target.tar.gz.sha256" -o "$tmp/sum"
  want="$(cut -d' ' -f1 "$tmp/sum")"
  got="$( (sha256sum "$tmp/onogoro.tar.gz" 2>/dev/null || shasum -a 256 "$tmp/onogoro.tar.gz") | cut -d' ' -f1)"
  [ "$want" = "$got" ] || { echo "onogoro: checksum mismatch for onogoro-$target.tar.gz" >&2; exit 1; }
fi

tar -xzf "$tmp/onogoro.tar.gz" -C "$tmp"
mkdir -p "$PREFIX/share" "$PREFIX/bin"
rm -rf "$PREFIX/share/onogoro"
mv "$tmp/onogoro-$target" "$PREFIX/share/onogoro"
ln -sf "$PREFIX/share/onogoro/onogoro" "$PREFIX/bin/onogoro"

echo "onogoro: installed in $PREFIX/share/onogoro, linked from $PREFIX/bin/onogoro"
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) echo "onogoro: add $PREFIX/bin to PATH" ;; esac
