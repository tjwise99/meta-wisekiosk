# Shared deploy recipes
#
# Required variables (set by importing Justfile):
#   machine     - Target machine (e.g., raspberrypi0-wifi)
#   image-name  - Image base name (e.g., core-image-base)

# Flash WIC image to SD card
[group('deploy')]
[script('bash')]
flash device:
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
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    if command -v bmaptool &> /dev/null; then
        BMAP="${IMAGE%.bz2}.bmap"
        if [ -f "$BMAP" ]; then
            sudo bmaptool copy --bmap "$BMAP" "$IMAGE" {{device}}
        else
            echo "Warning: bmap file not found, bmaptool will be slower"
            sudo bmaptool copy "$IMAGE" {{device}}
        fi
    else
        echo "bmaptool not found, falling back to dd (slower)..."
        bzcat "$IMAGE" | sudo dd of={{device}} bs=4M status=progress conv=fsync,sparse
    fi
    sync
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
    case "{{device}}" in
        *mmcblk*|*nvme*) PART="{{device}}p4" ;;
        *)               PART="{{device}}4"  ;;
    esac
    if [ ! -b "$PART" ]; then
        echo "Error: $PART is not a block device -- flash the card first, and check the device name"
        exit 1
    fi
    sudo mkdir -p {{mountpoint}}
    sudo mount "$PART" {{mountpoint}} || { echo "could not mount $PART"; exit 1; }
    # umount on every exit path: an unmounted-but-still-mounted card gets pulled
    # out with the config still in page cache.
    trap 'sudo umount {{mountpoint}} || echo "WARNING: {{mountpoint}} is still mounted"' EXIT
    # Root is needed to own the written files, but sudo resets HOME, so the
    # secrets path is resolved as the invoking user and passed through.
    sudo KIOSK_SECRETS="${KIOSK_SECRETS:-$HOME/.config/wisekiosk/secrets.yaml}" tools/provision.sh card {{mountpoint}}
