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
# The secrets live OUTSIDE the repository, deliberately. Nothing site-specific
# reaches the image any more, so the build must not be able to read them even by
# accident: with no secrets.yaml in the tree and no kas include for it, a
# leftover ${WIFI_SSID} expands to empty and breaks loudly instead of silently
# baking a real credential into a bundle.
SEC=${KIOSK_SECRETS:-$HOME/.config/wisekiosk/secrets.yaml}

# The recovery script (issue #28) is placed on /data, not the rootfs, so it
# survives an A/B flip and a reflash. Its single source of truth is the
# kiosk-recover recipe's files/ dir; provisioning is the /data placement path,
# so it is copied to /data/RECOVER.sh here. ci-guards.sh guard 8 fails if this
# wiring is broken (script missing, or provision.sh no longer references it).
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RECOVER_SRC="$REPO/meta-wisekiosk/recipes-core/kiosk-recover/files/kiosk-recover"
[ -r "$RECOVER_SRC" ] || { echo "recovery script missing at $RECOVER_SRC"; exit 1; }

[ -r "$SEC" ] || {
    echo "no secrets at $SEC"
    echo "copy secrets.yaml.tmpl there and fill it in, or set KIOSK_SECRETS"
    exit 1
}

val() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$SEC" | head -n1; }
SSID=$(val WIFI_SSID);      PSK=$(val WIFI_PSK_HASH)
URL=$(val KIOSK_URL);       HOST=$(val KIOSK_HOSTNAME)
NS=$(val KIOSK_NAMESERVER); MID=$(val KIOSK_MACHINE_ID)

for pair in SSID:WIFI_SSID PSK:WIFI_PSK_HASH URL:KIOSK_URL HOST:KIOSK_HOSTNAME NS:KIOSK_NAMESERVER; do
    n=${pair%%:*}; real=${pair#*:}
    [ -n "${!n}" ] || { echo "secrets.yaml is missing $real"; exit 1; }
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
install -m 0755 "$RECOVER_SRC" "$STAGE/RECOVER.sh"

case "$MODE" in
  card)
    [ -d "$DEST" ] || { echo "$DEST is not a directory -- mount the /data partition first"; exit 1; }
    mkdir -p "$DEST/config" "$DEST/etc"
    cp "$STAGE/config/"* "$DEST/config/"
    cp "$STAGE/etc/machine-id" "$DEST/etc/machine-id"
    cp "$STAGE/RECOVER.sh" "$DEST/RECOVER.sh"
    chown -R 0:0 "$DEST/config" "$DEST/etc" 2>/dev/null || echo "note: run as root to own the files correctly"
    chown 0:0 "$DEST/RECOVER.sh" 2>/dev/null || true
    chmod 0600 "$DEST/config/wpa_supplicant.conf"
    chmod 0755 "$DEST/RECOVER.sh"

    # Verify here, not in a procedure someone is told to follow. The failure
    # this catches is discovered on the device otherwise, and a card that comes
    # up unprovisioned has no network, so recovering it means physical access
    # and a second flash.
    #
    # Both checks are of things the WRITE can get wrong, never of a value this
    # script just wrote from input it already validated: re-counting the ssid=
    # lines of a heredoc, or re-measuring the length of a machine-id the
    # 32-hex check above already rejected, is arithmetic on a known quantity and
    # looks identical whether or not it fails.
    #
    #   mode        world-readable wifi credentials on a card that leaves the
    #               room, and wpa_supplicant will not say a word about it. Fires
    #               when $DEST is the vfat boot partition rather than ext4
    #               /data: vfat accepts a chmod and ignores it
    #   ownership   the chown above is downgraded to a note on failure, so this
    #               is the check that makes it loud -- files owned by the
    #               invoking user land the wifi credentials on the device owned
    #               by uid 1000, the same failure the device branch calls out
    bad=0
    say() { printf 'VERIFY FAIL  %s\n' "$*" >&2; bad=1; }

    mode=$(stat -c %a "$DEST/config/wpa_supplicant.conf")
    [ "$mode" = "600" ] || say "wpa_supplicant.conf is mode $mode, must be 600"

    for f in "$DEST/config/"* "$DEST/etc/machine-id"; do
        own=$(stat -c %u:%g "$f")
        [ "$own" = "0:0" ] || say "$f is owned by $own, must be 0:0 -- re-run as root"
    done

    # RECOVER.sh delivery is a thing the write can get wrong (a full or ro card);
    # the device branch reads it back, so verify it here too. Checked on its own,
    # not folded into the loop above: a missing file gives a clean VERIFY FAIL
    # rather than a stat crash, and the loop keeps its loud failure on any other
    # missing literal path (machine-id).
    if [ -f "$DEST/RECOVER.sh" ]; then
        own=$(stat -c %u:%g "$DEST/RECOVER.sh")
        [ "$own" = "0:0" ] || say "$DEST/RECOVER.sh is owned by $own, must be 0:0 -- re-run as root"
    else
        say "RECOVER.sh not delivered to $DEST -- recovery script missing"
    fi

    if [ "$bad" -ne 0 ]; then
        echo "NOT provisioned -- do not boot this card" >&2
        exit 1
    fi

    sync
    echo "provisioned $DEST"
    ;;
  device)
    ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
    # tar over stdin: one stream, and a few kilobytes of it. Small enough that
    # transfer shape is not a consideration here either way.
    # --owner/--group: tar otherwise preserves THIS host's uid/gid, landing the
    # wifi credentials owned by uid 1000 on the device.
    #
    # rc is captured rather than left to errexit: a bare ssh diagnostic and a
    # silent exit 255 say nothing about which of this script's two remote steps
    # ran, and the difference matters -- a write that failed leaves /data as it
    # was, a read-back that failed does not say whether the write landed.
    rc=0
    tar -C "$STAGE" --owner=root --group=root --numeric-owner -cf - . | ssh "${ssh_opts[@]}" "$DEST" \
        'mkdir -p /data/config /data/etc && tar -C /data -xf - && chown -R 0:0 /data/config /data/etc && chmod 0600 /data/config/wpa_supplicant.conf && sync' || rc=$?
    [ "$rc" -eq 0 ] || { echo "could not write /data on $DEST (tar|ssh rc=$rc) -- nothing was provisioned" >&2; exit 1; }

    rc=0
    ssh "${ssh_opts[@]}" "$DEST" 'ls -l /data/config /data/etc/machine-id /data/RECOVER.sh' || rc=$?
    [ "$rc" -eq 0 ] || { echo "wrote /data on $DEST but could not read it back (ssh rc=$rc) -- check it by hand" >&2; exit 1; }
    echo "provisioned $DEST"
    ;;
  *) echo "unknown mode $MODE"; exit 1 ;;
esac
