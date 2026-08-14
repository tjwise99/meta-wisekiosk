#!/bin/sh
# RAUC slot hooks. Runs on the RUNNING system with the freshly written slot
# mounted at $RAUC_SLOT_MOUNT_POINT, before that slot has ever booted.
#
# Purpose: carry this device's machine-id into the new slot.
#
# Why it cannot be done any other way. journald reads /etc/machine-id at ~8.2s,
# long before /data is mounted and far before sysinit.target, so a bind mount or
# a boot-time copy is too late -- the journal directory for that boot is already
# chosen. The value therefore has to be present IN the rootfs of the slot. This
# hook is the only point where the new slot's filesystem is writable and the old
# system still knows the device's identity.
#
# Without it, every OTA mints a new identity, journald orphans the previous
# namespace, and SystemMaxUse -- which is enforced per machine-id -- never bounds
# the total. Four namespaces reached 136.6MB on a 479MB /data that also stages
# the bundle.
#
# It is self-seeding: the first update to carry this hook captures the running
# machine-id into /data, so no flash-time provisioning step is needed for a
# device already in the field. /data survives both an A/B update and a slot
# reflash.
#
# DEFENSIVE BY CONSTRUCTION: a non-zero exit from a hook ABORTS the install.
# Nothing here is worth failing an update over, so every path exits 0.

set -u

case "$1" in
    slot-post-install)
        [ -n "${RAUC_SLOT_MOUNT_POINT:-}" ] || {
            echo "kiosk-slot-hook: no RAUC_SLOT_MOUNT_POINT, skipping"
            exit 0
        }

        # Seed /data from the running system the first time.
        if [ ! -s /data/etc/machine-id ] && [ -s /etc/machine-id ]; then
            mkdir -p /data/etc
            cp /etc/machine-id /data/etc/machine-id
            echo "kiosk-slot-hook: seeded /data/etc/machine-id from the running system"
        fi

        if [ -s /data/etc/machine-id ]; then
            id=$(tr -d '[:space:]' < /data/etc/machine-id)
            # 32 lowercase hex characters, or systemd rejects it and generates a
            # fresh one at boot -- which is exactly the failure being fixed.
            if [ "${#id}" -eq 32 ] && [ -z "$(printf '%s' "$id" | tr -d '0-9a-f')" ]; then
                printf '%s\n' "$id" > "$RAUC_SLOT_MOUNT_POINT/etc/machine-id"
                chmod 0644 "$RAUC_SLOT_MOUNT_POINT/etc/machine-id"
                echo "kiosk-slot-hook: wrote machine-id into the new slot"
            else
                echo "kiosk-slot-hook: /data/etc/machine-id is malformed, leaving the slot's own"
            fi
        fi
        ;;
esac

exit 0
