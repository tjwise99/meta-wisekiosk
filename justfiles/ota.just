# Shared OTA recipes for RAUC + casync delta updates
#
# Required variables (set by importing Justfile):
#   rauc-bundle-dir  - Directory for output bundles
#   rauc-cert        - Path to RAUC signing certificate
#   rauc-key         - Path to RAUC signing key
#   rauc-keyring     - Path to RAUC keyring

# Convert RAUC bundle to casync format for delta updates
[group('ota')]
[script('bash')]
rauc-to-casync bundle:
    mkdir -p {{rauc-bundle-dir}}
    rauc convert \
        --cert={{rauc-cert}} \
        --key={{rauc-key}} \
        --keyring={{rauc-keyring}} \
        {{bundle}} \
        {{rauc-bundle-dir}}/$(basename {{bundle}} .raucb).caibx
    echo "Created casync bundle at {{rauc-bundle-dir}}/$(basename {{bundle}} .raucb).caibx"

# List new chunks between two casync stores (for delta upload)
[group('ota')]
[script('bash')]
casync-diff old-store new-store:
    NEW_CHUNKS=$(comm -23 \
        <(find {{new-store}} -name '*.cacnk' -printf '%f\n' 2>/dev/null | sort) \
        <(find {{old-store}} -name '*.cacnk' -printf '%f\n' 2>/dev/null | sort))
    echo "$NEW_CHUNKS"
    COUNT=$(echo "$NEW_CHUNKS" | grep -c . || true)
    # Calculate size of new chunks
    SIZE=0
    for chunk in $NEW_CHUNKS; do
        prefix="${chunk:0:4}"
        if [ -f "{{new-store}}/$prefix/$chunk" ]; then
            SIZE=$((SIZE + $(stat -c%s "{{new-store}}/$prefix/$chunk")))
        fi
    done
    SIZE_MB=$((SIZE / 1024 / 1024))
    # Output stats to stderr so they don't break pipelines
    echo "" >&2
    echo "Delta: $COUNT chunks, ${SIZE_MB}MB" >&2

# Package delta update: new chunks + bundle manifest into a tarball
# Extract on device with: tar -xf update.tar.gz -C /data
[group('ota')]
[script('bash')]
casync-package-delta old-store new-store bundle output="update.tar.gz":
    STAGING=$(mktemp -d)
    trap "rm -rf $STAGING" EXIT

    # Find new chunks
    NEW_CHUNKS=$(comm -23 \
        <(find {{new-store}} -name '*.cacnk' -printf '%f\n' 2>/dev/null | sort) \
        <(find {{old-store}} -name '*.cacnk' -printf '%f\n' 2>/dev/null | sort))

    # Stage chunks in updates.castr/
    mkdir -p "$STAGING/updates.castr"
    COUNT=0
    SIZE=0
    for chunk in $NEW_CHUNKS; do
        prefix="${chunk:0:4}"
        mkdir -p "$STAGING/updates.castr/$prefix"
        cp "{{new-store}}/$prefix/$chunk" "$STAGING/updates.castr/$prefix/"
        SIZE=$((SIZE + $(stat -c%s "{{new-store}}/$prefix/$chunk")))
        COUNT=$((COUNT + 1))
    done

    # Stage bundle manifest in rauc/
    mkdir -p "$STAGING/rauc"
    cp "{{bundle}}" "$STAGING/rauc/"

    # Create tarball
    tar -czf "{{output}}" -C "$STAGING" updates.castr rauc

    SIZE_MB=$((SIZE / 1024 / 1024))
    TARBALL_SIZE=$(du -h "{{output}}" | cut -f1)
    echo "Packaged $COUNT chunks (${SIZE_MB}MB) + bundle manifest"
    echo "Created {{output}} ($TARBALL_SIZE)"
    echo "Deploy with: tar -xf {{output}} -C /data"

# Package full update: all chunks + bundle manifest into a tarball
# Use for initial loading or development when no base version exists
# Extract on device with: tar -xf update.tar.gz -C /data
[group('ota')]
[script('bash')]
casync-package store bundle output="update.tar.gz":
    STAGING=$(mktemp -d)
    trap "rm -rf $STAGING" EXIT

    # Stage all chunks in updates.castr/
    mkdir -p "$STAGING/updates.castr"
    COUNT=0
    SIZE=0
    for chunk in $(find {{store}} -name '*.cacnk' 2>/dev/null); do
        prefix=$(basename $(dirname $chunk))
        mkdir -p "$STAGING/updates.castr/$prefix"
        cp "$chunk" "$STAGING/updates.castr/$prefix/"
        SIZE=$((SIZE + $(stat -c%s "$chunk")))
        COUNT=$((COUNT + 1))
    done

    # Stage bundle manifest in rauc/
    mkdir -p "$STAGING/rauc"
    cp "{{bundle}}" "$STAGING/rauc/"

    # Create tarball
    tar -czf "{{output}}" -C "$STAGING" updates.castr rauc

    SIZE_MB=$((SIZE / 1024 / 1024))
    TARBALL_SIZE=$(du -h "{{output}}" | cut -f1)
    echo "Packaged $COUNT chunks (${SIZE_MB}MB) + bundle manifest"
    echo "Created {{output}} ($TARBALL_SIZE)"
    echo "Deploy with: tar -xf {{output}} -C /data"

# Show casync chunk store statistics
[group('ota')]
[script('bash')]
casync-stats store:
    CHUNKS=$(find {{store}} -name '*.cacnk' 2>/dev/null | wc -l)
    SIZE=$(du -sh {{store}} 2>/dev/null | cut -f1)
    echo "Chunks: $CHUNKS"
    echo "Size: $SIZE"

# === Tier 1 delivery: plain .raucb, chunked ===
#
# This board wedges on sustained SDIO traffic in EITHER direction, and a plain
# scp of the 133MB bundle hangs it in ~11s having moved 0 bytes. These recipes
# encode the delivery shape that works; see the kiosk-reference project,
# docs/experiment-log.md, for the measurements behind it.

# NOT covered by `just build`, which makes core-image-base only -- shipping a
# stale .raucb silently reinstalls the previous image.
#
# kconfig, not the root Justfile's `config`: that defaults to reference.yaml, a
# DIFFERENT product. Building the bundle against it fails on a missing include,
# which is the good case; silently building the wrong image would be the bad one.
# Comments must sit ABOVE the attributes -- just rejects one between them.
[group('ota')]
[doc("Build the RAUC update bundle")]
kiosk-bundle kconfig="kiosk-zero-w.yaml":
    kas-container shell {{kconfig}} -c "bitbake update-bundle"

# Every check here catches a failure that otherwise surfaces AFTER the 25-minute
# transfer, or does not surface at all.
[group('ota')]
[script('bash')]
[doc("Refuse a delivery that cannot work: slot size, stale bundle, /data space")]
kiosk-preflight image="build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/core-image-base-raspberrypi0-wifi.rootfs.ext4" bundle="build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/update-bundle-raspberrypi0-wifi.raucb" host="root@192.168.1.6":
    set -euo pipefail
    SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

    test -f "{{image}}"  || { echo "no rootfs image at {{image}}"; exit 1; }
    test -f "{{bundle}}" || { echo "no bundle at {{bundle}}"; exit 1; }
    IMAGE_B=$(stat -Lc %s "{{image}}")
    BUNDLE_B=$(stat -Lc %s "{{bundle}}")

    # Nothing ties the image inside the bundle to the slot that receives it. The
    # two agree only because both derive from AUTONOMOS_ROOTFS_SIZE in the same
    # build; a bundle built after that value changes cannot install on a device
    # flashed with the old layout, and it fails on the DEVICE mid-install rather
    # than in the build that produced it. Sector count is 512-byte units.
    A_BYTES=$(( $($SSH {{host}} 'cat /sys/class/block/mmcblk0p2/size') * 512 ))
    B_BYTES=$(( $($SSH {{host}} 'cat /sys/class/block/mmcblk0p3/size') * 512 ))
    echo "rootfs image  : $IMAGE_B"
    echo "slot A / B    : $A_BYTES / $B_BYTES"
    for slot in "$A_BYTES" "$B_BYTES"; do
        if [ "$IMAGE_B" -gt "$slot" ]; then
            echo "REFUSING: the image does not fit a $slot-byte slot"
            exit 1
        fi
    done

    # A leftover destination LARGER than the new bundle satisfies the sender's
    # resume condition immediately -- it reports a complete transfer having moved
    # zero bytes, and the install then reinstalls the PREVIOUS image. The
    # end-to-end md5 does catch it, 25 minutes later. Removing it also returns
    # ~130MB of the partition the bundle stages on.
    $SSH {{host}} 'rm -f /data/update.raucb; sync'

    FREE_KB=$($SSH {{host}} 'df -k /data | tail -n 1' | awk '{print $4}')
    NEED_KB=$(( BUNDLE_B / 1024 + 8192 ))
    echo "/data free    : ${FREE_KB}KB, need ${NEED_KB}KB"
    if [ "$FREE_KB" -lt "$NEED_KB" ]; then
        echo "REFUSING: not enough room on /data for the bundle"
        exit 1
    fi
    echo "preflight OK"

# Separates the receive burst from the sync: combining them is what hangs it.
[group('ota')]
[script('bash')]
[doc("Deliver a bundle in chunked bursts, verified end to end")]
kiosk-send bundle="build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/update-bundle-raspberrypi0-wifi.raucb" host="root@192.168.1.6" chunk_mb="2" rx_pause="4" sync_pause="3":
    KIOSK_HOST={{host}} tools/send-bundle-chunked.sh {{bundle}} {{chunk_mb}} {{rx_pause}} {{sync_pause}}

# Does NOT reboot -- inspect `rauc status` first, then `just kiosk-reboot`.
[group('ota')]
[script('bash')]
[doc("Install a staged bundle and show slot state")]
kiosk-install host="root@192.168.1.6":
    SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    echo "== before"
    $SSH {{host}} 'fw_printenv BOOT_ORDER BOOT_A_LEFT BOOT_B_LEFT; rauc status 2>&1 | grep -E "Booted|Activated|boot status"'
    echo "== verifying bundle signature against the device keyring"
    $SSH {{host}} 'rauc info /data/update.raucb' || { echo "bundle did not verify -- refusing to install"; exit 1; }
    echo "== installing"
    $SSH {{host}} 'rauc install /data/update.raucb'
    echo "== after"
    $SSH {{host}} 'fw_printenv BOOT_ORDER BOOT_A_LEFT BOOT_B_LEFT; rauc status 2>&1 | grep -E "Booted|Activated|boot status"'
    echo "Now: just kiosk-reboot   (fallback slot stays bootable if it fails)"

# Reboot and wait for the kiosk to answer again.
[group('ota')]
[script('bash')]
kiosk-reboot host="root@192.168.1.6":
    SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    BEFORE=$($SSH {{host}} 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null)
    $SSH {{host}} 'systemctl reboot' >/dev/null 2>&1 || true
    T0=$(date +%s)
    while :; do
        NOW=$($SSH {{host}} 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)
        [ -n "$NOW" ] && [ "$NOW" != "$BEFORE" ] && break
        [ $(( $(date +%s) - T0 )) -gt 300 ] && { echo "did not come back in 300s"; exit 1; }
        sleep 5
    done
    echo "back after $(( $(date +%s) - T0 ))s, boot_id $NOW"
    $SSH {{host}} 'rauc status 2>&1 | grep -E "Booted|boot status"; systemctl is-active kiosk; fw_printenv BOOT_ORDER BOOT_A_LEFT BOOT_B_LEFT'

# Full Tier 1 OTA. Builds the bundle FIRST so a stale .raucb cannot be shipped.
[group('ota')]
kiosk-ota host="root@192.168.1.6" kconfig="kiosk-zero-w.yaml": (kiosk-bundle kconfig) (kiosk-preflight "build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/core-image-base-raspberrypi0-wifi.rootfs.ext4" "build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/update-bundle-raspberrypi0-wifi.raucb" host) (kiosk-send "build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/update-bundle-raspberrypi0-wifi.raucb" host) (kiosk-install host)
    @echo "Delivered and installed. Verify, then: just kiosk-reboot {{host}}"

# Roll back to the other slot.
[group('ota')]
[script('bash')]
kiosk-rollback host="root@192.168.1.6":
    SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    $SSH {{host}} 'rauc status mark-bad booted; fw_printenv BOOT_ORDER BOOT_A_LEFT BOOT_B_LEFT'
    echo "Marked booted slot bad. Now: just kiosk-reboot {{host}}"
