#!/usr/bin/env bash
# Write per-site configuration to a device's /data. The image carries none of it.
#
#   tools/provision.sh device root@<host>     -- a running, reachable device
#   tools/provision.sh card   /mnt/data       -- a mounted /data partition
#
# Values come from secrets.yaml, which is gitignored. Nothing here is echoed:
# the SSID and PSK hash are not credential-shaped and would pass every scanner,
# which is exactly why they must not reach a transcript or a public repo.
#
# The chicken-and-egg is real and unavoidable: wifi credentials are what let you
# REACH the device, so the first write cannot come over the network. Use the
# `card` mode before first boot. `device` mode is for a unit you can already
# reach -- re-provisioning, or seeding one that still has a baked config.
set -euo pipefail

MODE=${1:?usage: provision.sh device <ssh-target> | card <mounted-/data>}
DEST=${2:?usage: provision.sh device <ssh-target> | card <mounted-/data>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SEC="$ROOT/secrets.yaml"
[ -r "$SEC" ] || { echo "no $SEC -- copy secrets.yaml.tmpl and fill it in"; exit 1; }

val() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$SEC" | head -n1; }
SSID=$(val WIFI_SSID);      PSK=$(val WIFI_PSK_HASH)
URL=$(val KIOSK_URL);       HOST=$(val KIOSK_HOSTNAME)
NS=$(val KIOSK_NAMESERVER); MID=$(val KIOSK_MACHINE_ID)

for n in SSID PSK URL HOST NS; do
    [ -n "${!n}" ] || { echo "secrets.yaml is missing $n"; exit 1; }
done

# machine-id: 32 lowercase hex. Generated per device if secrets.yaml has none --
# systemd rejects any other form and silently generates a fresh one at boot,
# which is the journal-orphaning bug this exists to prevent.
if [ -z "$MID" ]; then
    MID=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
    echo "generated a machine-id (not stored in secrets.yaml -- add it to keep it stable)"
fi
if [ "${#MID}" -ne 32 ] || [ -n "$(printf '%s' "$MID" | tr -d '0-9a-f')" ]; then
    echo "KIOSK_MACHINE_ID must be 32 lowercase hex characters"; exit 1
fi

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/config" "$STAGE/etc"
umask 077
cat > "$STAGE/config/wpa_supplicant.conf" <<EOF
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1

network={
    key_mgmt=WPA-PSK
    ssid="$SSID"
    psk=$PSK
}
EOF
umask 022
printf 'KIOSK_URL=%s\nKIOSK_INSPECTOR=0\n' "$URL" > "$STAGE/config/kiosk.conf"
printf '%s\n' "$HOST" > "$STAGE/config/hostname"
: > "$STAGE/config/resolv.conf"
for ns in $NS; do printf 'nameserver %s\n' "$ns" >> "$STAGE/config/resolv.conf"; done
printf '%s\n' "$MID" > "$STAGE/etc/machine-id"

case "$MODE" in
  card)
    [ -d "$DEST" ] || { echo "$DEST is not a directory -- mount the /data partition first"; exit 1; }
    mkdir -p "$DEST/config" "$DEST/etc"
    cp "$STAGE/config/"* "$DEST/config/"
    cp "$STAGE/etc/machine-id" "$DEST/etc/machine-id"
    chown -R 0:0 "$DEST/config" "$DEST/etc" 2>/dev/null || echo "note: run as root to own the files correctly"
    chmod 0600 "$DEST/config/wpa_supplicant.conf"
    sync
    echo "provisioned $DEST"
    ;;
  device)
    ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
    # tar over stdin: small, one stream, nothing like the sustained transfer that
    # wedges this board.
    # --owner/--group: tar otherwise preserves THIS host's uid/gid, landing the
    # wifi credentials owned by uid 1000 on the device.
    tar -C "$STAGE" --owner=root --group=root --numeric-owner -cf - . | ssh "${ssh_opts[@]}" "$DEST" \
        'mkdir -p /data/config /data/etc && tar -C /data -xf - && chown -R 0:0 /data/config /data/etc && chmod 0600 /data/config/wpa_supplicant.conf && sync'
    ssh "${ssh_opts[@]}" "$DEST" 'ls -l /data/config /data/etc/machine-id'
    echo "provisioned $DEST"
    ;;
  *) echo "unknown mode $MODE"; exit 1 ;;
esac
