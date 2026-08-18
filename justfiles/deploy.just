# Shared deploy recipes
#
# Required variables (set by importing Justfile):
#   machine     - Target machine (e.g., raspberrypi0-wifi)
#   image-name  - Image base name (e.g., core-image-base)

# Flash WIC image to SD card
[group('deploy')]
[script('bash')]
flash device:
    # errexit+pipefail, because the write is the whole point: without them a
    # failed `dd` -- sudo unable to authenticate, a card pulled mid-copy -- still
    # reaches the closing "Done. Safe to eject", and an unwritten card is
    # indistinguishable from a written one until it fails to boot.
    set -euo pipefail
    # sudo consults SUDO_ASKPASS only under -A. Without it, every root step here
    # dies on a host with no controlling terminal (CI, a hook, an agent shell).
    if [ -n "${SUDO_ASKPASS:-}" ]; then SUDO=(sudo -A); else SUDO=(sudo); fi
    IMAGE="build/tmp-{{machine}}/deploy/images/{{machine}}/{{image-name}}-{{machine}}.rootfs.wic.bz2"
    if [ ! -b "{{device}}" ]; then
        echo "Error: Device not found or not a block device: {{device}}"
        exit 1
    fi
    if [ ! -f "$IMAGE" ]; then
        echo "Error: Image not found: $IMAGE"
        echo "Did you run 'just build' first?"
        exit 1
    fi

    # A card reflash is the one path that can silently UN-ROTATE a unit: RAUC
    # never touches the FAT partition, so an OTA cannot fix a card written with
    # the wrong keyring, and the unit is wall-mounted. A device trusts only the
    # keyring baked into the slot it boots, so flashing an image built without
    # the fleet key strands it -- reachable again only by pulling the card.
    # Fails CLOSED: anything unproven refuses the write.
    FLEET_CERT="{{keys-root}}/{{fleet-key}}/signing.cert.pem"
    ROOTFS="build/tmp-{{machine}}/deploy/images/{{machine}}/{{image-name}}-{{machine}}.rootfs.ext4"
    test -f "$FLEET_CERT" || { echo "Error: fleet cert not found: $FLEET_CERT" >&2; exit 1; }
    test -f "$ROOTFS"     || { echo "Error: rootfs not found: $ROOTFS" >&2; exit 1; }
    command -v debugfs >/dev/null 2>&1 || { echo "Error: debugfs missing -- cannot verify the keyring; refusing to flash" >&2; exit 1; }

    # The keyring is read from the .ext4, because debugfs cannot address a
    # filesystem inside the partitioned, compressed .wic.bz2 that is actually
    # written. Both are emitted by one build under the same timestamp, so
    # requiring the timestamps to match is what makes the .ext4 evidence about
    # the .wic.bz2 -- without it this would verify one artifact and flash another.
    #
    # ASSUMPTION: wic populates the rootfs partition from IMAGE_ROOTFS, the same
    # tree the .ext4 is generated from, so the stamped .ext4 carries the same
    # /etc/rauc/keyring.pem the .wic does. A WKS_FILE that switched to rawcopy,
    # or sourced a different image, would break that link -- this check would
    # then need to loop-mount the .wic's rootfs partition instead.
    IMG_STAMP=$(basename "$(readlink -f "$IMAGE")"  | sed -n 's/.*rootfs-\([0-9]\{8,\}\)\..*/\1/p')
    EXT_STAMP=$(basename "$(readlink -f "$ROOTFS")" | sed -n 's/.*rootfs-\([0-9]\{8,\}\)\..*/\1/p')
    if [ -z "$IMG_STAMP" ] || [ "$IMG_STAMP" != "$EXT_STAMP" ]; then
        echo "Error: cannot tie the rootfs to the image being flashed" >&2
        echo "  image  build: ${IMG_STAMP:-unknown}" >&2
        echo "  rootfs build: ${EXT_STAMP:-unknown}" >&2
        echo "One is stale. Re-run 'just build' so both come from one build." >&2
        exit 1
    fi

    # Both fingerprints are captured with errexit OFF on purpose. `VAR=$(cmd)`
    # takes cmd's exit status, so under `set -e` an unreadable cert or a non-ext4
    # rootfs would abort the recipe right here and print nothing but "recipe
    # `flash` failed with exit code 1". Failing closed is not enough -- the
    # operator has to be told WHY, and suspending errexit is what makes the
    # empty-result branches below reachable at all. Both sides get the same
    # treatment: either input can be the broken one.
    set +e
    WANT_FP=$(openssl x509 -in "$FLEET_CERT" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//')
    BAKED_PEM=$(debugfs -R "cat /etc/rauc/keyring.pem" "$ROOTFS" 2>/dev/null)
    BAKED_FP=$(printf '%s\n' "$BAKED_PEM" \
        | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//')
    set -e

    # Tool output first, explanation LAST: openssl and debugfs are both happy to
    # emit a dozen lines, and whatever is printed last is what an operator
    # scanning the tail actually reads. Bounded with head so the reason cannot be
    # pushed off screen; `|| true` because pipefail would otherwise turn the
    # deliberately-failing diagnostic into an abort.
    if [ -z "$WANT_FP" ]; then
        echo "-- openssl reported: --" >&2
        { openssl x509 -in "$FLEET_CERT" -noout -fingerprint -sha256 2>&1 >/dev/null | head -3 >&2; } || true
        echo "Error: cannot read a certificate from the fleet cert:" >&2
        echo "  $FLEET_CERT" >&2
        echo "It exists but openssl could not parse it -- truncated, empty, or not" >&2
        echo "PEM. Refusing to flash: without it there is nothing to verify the card" >&2
        echo "against. Check the file, or that fleet-key in the Justfile names the" >&2
        echo "right key." >&2
        exit 1
    fi

    if [ -z "$BAKED_FP" ]; then
        echo "-- debugfs reported: --" >&2
        { debugfs -R "cat /etc/rauc/keyring.pem" "$ROOTFS" 2>&1 >/dev/null | head -3 >&2; } || true
        echo "Error: no readable certificate at /etc/rauc/keyring.pem in:" >&2
        echo "  $ROOTFS" >&2
        echo "The image may be truncated, not an ext4, or built without the RAUC" >&2
        echo "keyring recipe. Refusing to flash: an unverifiable card is not a safe" >&2
        echo "card, and a wrong keyring cannot be repaired over the air." >&2
        exit 1
    fi
    if [ "$BAKED_FP" != "$WANT_FP" ]; then
        echo "Error: the image does not bake the fleet keyring -- refusing to flash." >&2
        echo "  baked   : $BAKED_FP" >&2
        echo "  expected: $WANT_FP" >&2
        echo "  expected cert: $FLEET_CERT" >&2
        echo "This card would boot a unit that rejects every fleet update, and no" >&2
        echo "OTA could repair it. Rebuild against the fleet key, or check that" >&2
        echo "fleet-key in the Justfile still names the key the fleet trusts." >&2
        exit 1
    fi
    echo "verified: image bakes the fleet keyring ($BAKED_FP)"

    echo "Flashing $IMAGE to {{device}}..."
    echo "WARNING: This will overwrite all data on {{device}}!"
    # `|| true`: read exits non-zero at EOF, which errexit would turn into an
    # abort that reads like a decline. An empty REPLY declines on its own.
    read -p "Continue? [y/N] " -n 1 -r || true
    echo
    if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    if command -v bmaptool &> /dev/null; then
        BMAP="${IMAGE%.bz2}.bmap"
        if [ -f "$BMAP" ]; then
            "${SUDO[@]}" bmaptool copy --bmap "$BMAP" "$IMAGE" {{device}}
        else
            echo "Warning: bmap file not found, bmaptool will be slower"
            "${SUDO[@]}" bmaptool copy "$IMAGE" {{device}}
        fi
    else
        echo "bmaptool not found, falling back to dd (slower)..."
        bzcat "$IMAGE" | "${SUDO[@]}" dd of={{device}} bs=4M status=progress conv=fsync,sparse
    fi
    sync
    # The kernel holds the partition table it read at plug time, so the card's
    # new partitions -- including the fourth, /data -- do not exist as device
    # nodes yet, and `just provision-fresh-card` would report the card unflashed.
    "${SUDO[@]}" blockdev --rereadpt {{device}} || echo "Warning: could not re-read the partition table -- replug the card before provisioning"
    udevadm settle 2>/dev/null || true
    echo "Done. Safe to eject {{device}}."

# Provision a freshly flashed card: mount /data, write the site config, unmount
#
# /data is the FOURTH partition, not the rootfs, and nothing about the card says
# so -- writing the config into partition 2 leaves a unit that boots with no
# network and no way in but a USB keyboard. The suffix differs by device class:
# /dev/sdX takes a bare 4, mmcblk and nvme interpose a `p`.
#
# Verification is not here on purpose. It lives inside tools/provision.sh, which
# runs it whether it was reached through this recipe or called directly -- a
# check a human has to remember is a check that looks identical when it fails.
[group('deploy')]
[script('bash')]
[doc("Mount a fresh card's /data, provision it from secrets.yaml, unmount")]
provision-fresh-card device mountpoint="/mnt/kiosk-data":
    set -uo pipefail
    # sudo consults SUDO_ASKPASS only under -A, and a host with no controlling
    # terminal has no other way to answer the prompt.
    if [ -n "${SUDO_ASKPASS:-}" ]; then SUDO=(sudo -A); else SUDO=(sudo); fi
    case "{{device}}" in
        *mmcblk*|*nvme*) PART="{{device}}p4" ;;
        *)               PART="{{device}}4"  ;;
    esac
    if [ ! -b "$PART" ]; then
        echo "Error: $PART is not a block device -- flash the card first, and check the device name"
        exit 1
    fi
    "${SUDO[@]}" mkdir -p {{mountpoint}}
    "${SUDO[@]}" mount "$PART" {{mountpoint}} || { echo "could not mount $PART"; exit 1; }
    # umount on every exit path: an unmounted-but-still-mounted card gets pulled
    # out with the config still in page cache.
    trap '"${SUDO[@]}" umount {{mountpoint}} || echo "WARNING: {{mountpoint}} is still mounted"' EXIT
    # Root is needed to own the written files, but sudo resets HOME, so the
    # secrets path is resolved as the invoking user and passed through.
    "${SUDO[@]}" KIOSK_SECRETS="${KIOSK_SECRETS:-$HOME/.config/wisekiosk/secrets.yaml}" tools/provision.sh card {{mountpoint}}
