#!/usr/bin/env bash
# What onogoro promises, checked on this machine with the onogoro on PATH, through the same
# worker comide calls (`onogoro KIND -- PROG ARGS`), without a model or a real key:
#   - a command writes the project and nothing else of the home
#   - a command cannot read the files the keys live in
#   - a command gets no key, and golemide (solve) gets a placeholder, not the key
# Exits non-zero on the first broken promise. .github/workflows/host.yml runs it.
set -uo pipefail

me="$(command -v onogoro)" || { echo "onogoro is not on PATH" >&2; exit 2; }
proj="$(mktemp -d)"; scratch="$(mktemp -d)"
mkdir -p "$HOME/.config/golemide"
keyfile="$HOME/.config/golemide/.env"
[ -e "$keyfile" ] && { echo "$keyfile exists; run this where it does not" >&2; exit 2; }
secret="not-a-real-key-$RANDOM$RANDOM"
echo "CLOUDFLARE_API_TOKEN=$secret" > "$keyfile"
trap 'rm -rf "$proj" "$scratch" "$keyfile" "$HOME/onogoro-outside"' EXIT

export ONOGORO_ROLE=worker ONOGORO_ROOT="$proj" ONOGORO_SCRATCH="$scratch"
export PATH="$(dirname "$(readlink -f "$me")"):$PATH"
export CLOUDFLARE_ACCOUNT_ID=0 CLOUDFLARE_API_TOKEN="$secret"
cd "$proj"

failed=0
check() { # NAME EXPECT(ok|refused) KIND -- PROG ARGS...
  local name="$1" expect="$2"; shift 2
  local out code
  out="$(onogoro "$@" 2>&1)"; code=$?
  local got=ok; [ $code -ne 0 ] && got=refused
  if [ "$got" = "$expect" ]; then echo "pass  $name"
  else echo "FAIL  $name (exit $code)"; echo "$out" | tail -5 | sed 's/^/      /'; failed=1; fi
}

check "a command writes the project"            ok      shell -- sh -c 'echo hi > made.txt && test -s made.txt'
check "a command cannot write the home"          refused shell -- sh -c 'touch "$HOME/onogoro-outside"'
check "a command cannot read the key file"       refused shell -- cat "$keyfile"
check "a command gets no key"                    ok      shell -- sh -c '[ -z "${CLOUDFLARE_API_TOKEN:-}" ]'
check "golemide gets a placeholder, not the key" ok      solve -- sh -c 'case "$CLOUDFLARE_API_TOKEN" in porta-cred-*) exit 0;; *) exit 1;; esac'
check "the key is in no variable inside solve"   ok      solve -- sh -c "! env | grep -q '$secret'"
check "golemide cannot read the key file"        refused solve -- cat "$keyfile"
[ -e "$HOME/onogoro-outside" ] && { echo "FAIL  the home was written after all"; failed=1; }
exit $failed
