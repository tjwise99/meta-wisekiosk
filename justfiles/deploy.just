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
