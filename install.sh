#!/bin/sh
# Installs aitrium and everything it runs (comide, golemide, porta, …) from a release:
#
#   curl -fsSL https://raw.githubusercontent.com/O6lvl4/aitrium/main/install.sh | sh
#
# It unpacks into $PREFIX/share/aitrium and links $PREFIX/bin/aitrium to it; nothing else
# goes on PATH, so a comide or porta you already have is left as it is.
#
#   AITRIUM_PREFIX   where to install      (default: ~/.local)
#   AITRIUM_VERSION  a release tag, v0.1.0 (default: the latest)
#   AITRIUM_ARCHIVE  a local aitrium-TARGET.tar.gz to install instead of downloading
set -eu

PREFIX="${AITRIUM_PREFIX:-$HOME/.local}"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$os-$arch" in
  darwin-arm64 | darwin-aarch64) target=darwin-arm64 ;;
  linux-x86_64 | linux-amd64) target=linux-x86_64 ;;
  linux-aarch64 | linux-arm64) target=linux-aarch64 ;;
  *) echo "aitrium: no release for $os-$arch" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if [ -n "${AITRIUM_ARCHIVE:-}" ]; then
  cp "$AITRIUM_ARCHIVE" "$tmp/aitrium.tar.gz"
else
  case "${AITRIUM_VERSION:-latest}" in
    latest) base="https://github.com/O6lvl4/aitrium/releases/latest/download" ;;
    *) base="https://github.com/O6lvl4/aitrium/releases/download/$AITRIUM_VERSION" ;;
  esac
  echo "aitrium: downloading aitrium-$target.tar.gz"
  curl -fsSL "$base/aitrium-$target.tar.gz" -o "$tmp/aitrium.tar.gz"
  curl -fsSL "$base/aitrium-$target.tar.gz.sha256" -o "$tmp/sum"
  want="$(cut -d' ' -f1 "$tmp/sum")"
  got="$( (sha256sum "$tmp/aitrium.tar.gz" 2>/dev/null || shasum -a 256 "$tmp/aitrium.tar.gz") | cut -d' ' -f1)"
  [ "$want" = "$got" ] || { echo "aitrium: checksum mismatch for aitrium-$target.tar.gz" >&2; exit 1; }
fi

tar -xzf "$tmp/aitrium.tar.gz" -C "$tmp"
mkdir -p "$PREFIX/share" "$PREFIX/bin"
rm -rf "$PREFIX/share/aitrium"
mv "$tmp/aitrium-$target" "$PREFIX/share/aitrium"
ln -sf "$PREFIX/share/aitrium/aitrium" "$PREFIX/bin/aitrium"

echo "aitrium: installed in $PREFIX/share/aitrium, linked from $PREFIX/bin/aitrium"
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) echo "aitrium: add $PREFIX/bin to PATH" ;; esac
