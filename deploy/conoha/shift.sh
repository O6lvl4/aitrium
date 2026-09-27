#!/bin/bash
# One shift of one role: onogoro runs comide on the role's instructions, unattended
# (--yes), every command it runs confined by porta. What the role wrote for people goes
# to its outbox; what it did goes to the journal.
#
#   onogoro-shift ROLE       reads /etc/onogoro/staff/ROLE.env and ROLE.md
#
# ROLE.env: NET (open | none), HARBOR (yes | no), READS (roles whose outboxes it reads),
# MODEL (comide's --model), SCHEDULE (the timer's OnCalendar=, read by onogoro-staff).
set -euo pipefail
role=$1
conf=/etc/onogoro/staff
NET=open HARBOR=no READS="" MODEL=""
# shellcheck disable=SC1090
. "$conf/$role.env"

home=/srv/staff/$role
mkdir -p "$home/work" "$home/outbox" "$home/journal"

# What other roles wrote, copied in: the lead reads them, and cannot write theirs.
for other in $READS; do
  rm -rf "$home/work/from/$other" && mkdir -p "$home/work/from/$other"
  cp -r "/srv/staff/$other/outbox/." "$home/work/from/$other/" 2>/dev/null || true
done

export ONOGORO_NET=$NET
[ "$HARBOR" = yes ] || unset ONOGORO_HARBOR_PORT ONOGORO_HARBOR_TOKEN

stamp=$(date +%F-%H%M)
args=(-p "$(cat "$conf/$role.md")" --root "$home/work" --yes)
[ -n "$MODEL" ] && args+=(--model "$MODEL")
if onogoro "${args[@]}" >"$home/outbox/.$stamp.md" 2>"$home/journal/$stamp.log"; then
  mv "$home/outbox/.$stamp.md" "$home/outbox/$stamp.md"
else
  code=$?
  mv "$home/outbox/.$stamp.md" "$home/journal/$stamp.failed.md"
  exit $code
fi
