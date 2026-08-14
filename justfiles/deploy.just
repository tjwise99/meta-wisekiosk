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
