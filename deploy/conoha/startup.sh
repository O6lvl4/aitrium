#!/bin/bash
# onogoro on ConoHa VPS: paste this as the server's startup script (Ubuntu 24.04).
#
# It installs the island and its door, and starts nothing that needs a key. Keys never go
# in a startup script: ConoHa keeps it, and anything on the server that can reach the
# metadata service can read it back. After the first boot, over SSH:
#
#   sudoedit /etc/onogoro/keys.env       the model keys (the supervisor's, never a worker's)
#   sudoedit /etc/onogoro/harbor.env     the ConoHa API user and the harbor's limits
#   sudo onogoro-staff enable            the harbor, and each role's timer
#
# The log of this script is /var/log/onogoro-install.log.
set -euo pipefail
exec >>/var/log/onogoro-install.log 2>&1

ALMIDE_TAG=${ALMIDE_TAG:-v0.64.0}
PORTA_TAG=${PORTA_TAG:-v0.6.16}
SRC=https://raw.githubusercontent.com/O6lvl4/onogoro/main/deploy/conoha

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git curl ca-certificates openssl build-essential ufw python3
timedatectl set-timezone Asia/Tokyo   # the roles' SCHEDULEs are in Japan time

# Nothing listens to the world but SSH. The harbor listens on 7707 on every interface
# (Almide's http.serve binds 0.0.0.0), so this is what keeps it local.
ufw default deny incoming
ufw allow OpenSSH
ufw --force enable

# Almide and porta: release binaries, checksums checked.
cd /tmp
curl -fsSL "https://github.com/almide/almide/releases/download/$ALMIDE_TAG/almide-linux-x86_64.tar.gz" -o almide.tgz
curl -fsSL "https://github.com/almide/almide/releases/download/$ALMIDE_TAG/almide-checksums.sha256" -o almide.sha
echo "$(grep 'almide-linux-x86_64.tar.gz' almide.sha | awk '{print $1}')  almide.tgz" | sha256sum -c -
tar -xzf almide.tgz && install -m 755 almide-linux-x86_64/almide /usr/local/bin/almide
curl -fsSL https://raw.githubusercontent.com/almide/porta/main/scripts/install.sh | PORTA_RELEASE_TAG=$PORTA_TAG bash -s /usr/local/bin
porta setup || true   # Ubuntu 23.10+: the AppArmor profile porta's namespaces need

# The agent and its tools, built from source.
mkdir -p /opt/onogoro && cd /opt/onogoro
for repo in O6lvl4/golemide O6lvl4/comide O6lvl4/hew O6lvl4/onogoro; do
  name=${repo#*/}
  [ -d "$name" ] || git clone -q --depth 1 "https://github.com/$repo" "$name"
  (cd "$name" && almide build src/main.almd -o "$name") && ln -sf "/opt/onogoro/$name/$name" "/usr/local/bin/$name"
done
[ -x /opt/onogoro/comide/bin/comide ] && ln -sf /opt/onogoro/comide/bin/comide /usr/local/bin/comide

# Two users. `harbor` holds the ConoHa API user and nothing else; `staff` runs the
# agents and holds the model keys and the harbor's token, never ConoHa's.
id harbor >/dev/null 2>&1 || useradd --system --home /var/lib/onogoro-harbor --create-home --shell /usr/sbin/nologin harbor
id staff >/dev/null 2>&1 || useradd --create-home --home /srv/staff --shell /bin/bash staff

mkdir -p /etc/onogoro/staff
for f in onogoro-harbor.service onogoro-shift@.service onogoro-staff shift.sh; do
  curl -fsSL "$SRC/$f" -o "/tmp/$f"
done
install -m 644 /tmp/onogoro-harbor.service /tmp/onogoro-shift@.service /etc/systemd/system/
install -m 755 /tmp/onogoro-staff /usr/local/bin/onogoro-staff
install -m 755 /tmp/shift.sh /usr/local/bin/onogoro-shift
for role in lead research sales dev; do
  for ext in env md; do
    [ -e "/etc/onogoro/staff/$role.$ext" ] || curl -fsSL "$SRC/staff/$role.$ext" -o "/etc/onogoro/staff/$role.$ext"
  done
done

# The harbor's token: made here, known to the harbor and to staff, and to no one else.
token=$(openssl rand -hex 24)
if [ ! -e /etc/onogoro/harbor.env ]; then
  curl -fsSL "$SRC/harbor.env.example" -o /etc/onogoro/harbor.env
  echo "ONOGORO_HARBOR_TOKEN=$token" >> /etc/onogoro/harbor.env
  chown harbor:harbor /etc/onogoro/harbor.env && chmod 600 /etc/onogoro/harbor.env
fi
if [ ! -e /etc/onogoro/keys.env ]; then
  curl -fsSL "$SRC/keys.env.example" -o /etc/onogoro/keys.env
  printf 'ONOGORO_HARBOR_PORT=7707\nONOGORO_HARBOR_TOKEN=%s\n' "$token" >> /etc/onogoro/keys.env
  chown staff:staff /etc/onogoro/keys.env && chmod 600 /etc/onogoro/keys.env
fi

systemctl daemon-reload
echo "onogoro installed $(date -Is). Next: sudoedit /etc/onogoro/keys.env /etc/onogoro/harbor.env; sudo onogoro-staff enable"
