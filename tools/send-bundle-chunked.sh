#!/bin/bash
# Deliver a large file to the kiosk over SSH in synced, resumable chunks.
#
# SUPERSEDED: the SDIO/mmc wedge this shape works around was a symptom of
# top-OPP memory corruption, fixed by the clock cap in
# meta-wisekiosk/recipes-core/kiosk-cpufreq. Kept until removal lands --
# issue #29 remove chunked bundle delivery.
#
# Evidence this was built on, measured on the uncapped board
# (mechanism: docs/issue_investigation/wifi_instability/README.md):
#   Test A  334 MB written to /data + sync, negligible network  -> SURVIVED
#   Test B  133 MB received into /dev/null, zero disk writes    -> HUNG in 11 s
#   TX      133 MB sent from the device, three runs             -> 2 of 3 HUNG
# Sustained activity in either direction wedged it, and combining network
# receive with a synchronous SD write was the worst case: a sync after every
# append made the board hang on the FIRST chunk every time, where the unsynced
# form moved 14 in a row.
#
# So the two are separated in time:
#   receive burst -> pause -> sync (no network in flight) -> pause -> repeat
#
# Progress is ALWAYS derived from the durable on-disk size, never from what this
# script believes it sent. An unsynced append is lost when the board hangs, and
# a read-back md5 will happily confirm a chunk that is still only in page cache
# -- that produced a silent 68 MB -> 60 MB rollback. Size-after-sync is the only
# honest progress marker.
set -u

BUNDLE=$(readlink -f "${1:?usage: send-bundle-chunked.sh <file> [chunk_mb] [rx_pause] [sync_pause]}")
CHUNK_MB=${2:-2}
RX_PAUSE=${3:-4}
SYNC_PAUSE=${4:-3}
HOST=${KIOSK_HOST:-root@192.168.1.6}
DEST=${KIOSK_DEST:-/data/update.raucb}
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

SIZE=$(stat -Lc%s "$BUNDLE")          # -L: a symlink's own size is its target's NAME length
CHUNK=$((CHUNK_MB * 1024 * 1024))
LOCAL_MD5=$(md5sum "$BUNDLE" | cut -d' ' -f1)
MAX_STALL=${MAX_STALL:-40}            # consecutive no-progress rounds before giving up

echo "bundle  $BUNDLE"
echo "  size=$SIZE md5=$LOCAL_MD5 chunk=${CHUNK_MB}MB rx_pause=${RX_PAUSE}s sync_pause=${SYNC_PAUSE}s"

hangs=0; sent=0; stall=0; t0=$(date +%s)

wait_for_device() {
	local waited=0
	until timeout 15 $SSH "$HOST" 'true' 2>/dev/null; do
		sleep 10; waited=$((waited + 10))
		[ $waited -ge 400 ] && { echo "  !! no device after ${waited}s"; return 1; }
	done
	if [ $waited -gt 0 ]; then
		hangs=$((hangs + 1))
		echo "  .. device back after ${waited}s (hang #$hangs, auto-recovered)"
	fi
	return 0
}

# Durable size: sync first so page cache cannot inflate the answer.
#
# CRITICAL: a failed read must NOT look like "0 bytes". busybox dd has no
# conv=notrunc, so writes are appends, and an append made while believing the
# file is empty lands 2MB in the MIDDLE of an 86MB file. That is exactly what
# corrupted two transfers: `${cur:-0}` turned a timed-out ssh into a legitimate
# offset of zero. Returns non-zero on any unreadable/non-numeric answer, and the
# caller retries rather than assuming.
durable_size() {
	local out
	wait_for_device || return 1
	out=$(timeout 120 $SSH "$HOST" "sync; if [ -e $DEST ]; then wc -c < $DEST; else echo 0; fi" 2>/dev/null | tr -d ' \r')
	case "${out:-}" in
		''|*[!0-9]*) return 1 ;;
	esac
	printf '%s' "$out"
}

# Roll back to a chunk boundary. bs=1M, never bs=1 (one syscall per byte at
# 60 MB is 60 million of them). The mv only happens if the copy is exactly right.
rewind_to() {
	local off=$1 mb got
	mb=$((off / 1048576))
	wait_for_device || return 1
	if [ "$off" -eq 0 ]; then timeout 60 $SSH "$HOST" "rm -f $DEST" 2>/dev/null; return 0; fi
	got=$(timeout 300 $SSH "$HOST" "dd if=$DEST of=$DEST.tmp bs=1M count=$mb 2>/dev/null; sync; wc -c < $DEST.tmp" 2>/dev/null | tr -d ' \r')
	if [ "${got:-0}" = "$off" ]; then
		timeout 60 $SSH "$HOST" "mv $DEST.tmp $DEST; sync" 2>/dev/null; return 0
	fi
	echo "  !! rewind to $off produced ${got:-0}; leaving $DEST untouched"
	timeout 60 $SSH "$HOST" "rm -f $DEST.tmp" 2>/dev/null
	return 1
}

while :; do
	if ! cur=$(durable_size); then
		echo "  .. size read failed; retrying (never assuming 0)"
		stall=$((stall + 1))
		[ $stall -ge $MAX_STALL ] && { echo "  !! $MAX_STALL rounds without progress"; exit 1; }
		sleep 5; continue
	fi
	[ "$cur" -ge "$SIZE" ] && break

	i=$((cur / CHUNK)); off=$((i * CHUNK))
	if [ "$cur" -ne "$off" ]; then
		echo "  partial tail: $cur -> rewinding to $off"
		rewind_to "$off" || exit 1
		continue
	fi

	pct=$((cur * 100 / SIZE))
	printf "  [%3d%%] chunk %d @ %d ... " "$pct" "$((i + 1))" "$off"

	# 1. receive burst -- no disk sync in flight
	dd if="$BUNDLE" bs=$CHUNK skip=$i count=1 2>/dev/null \
		| timeout 300 $SSH "$HOST" "cat >> $DEST" 2>/dev/null
	rc=$?
	if [ $rc -ne 0 ]; then
		echo "rx rc=$rc"
		wait_for_device || exit 1
		stall=$((stall + 1))
		[ $stall -ge $MAX_STALL ] && { echo "  !! $MAX_STALL rounds without progress"; exit 1; }
		continue
	fi

	# 2. quiet gap, 3. sync alone, 4. quiet gap
	sleep "$RX_PAUSE"
	wait_for_device || exit 1
	timeout 180 $SSH "$HOST" "sync" 2>/dev/null
	sleep "$SYNC_PAUSE"

	if ! new=$(durable_size); then
		echo "size unreadable; will re-derive"
		stall=$((stall + 1)); continue
	fi
	if [ "$new" -gt "$cur" ]; then
		sent=$((sent + 1)); stall=0
		echo "ok (+$((new - cur)) B, $new total)"
	else
		echo "LOST (still $new) -- resending"
		stall=$((stall + 1))
		[ $stall -ge $MAX_STALL ] && { echo "  !! $MAX_STALL rounds without progress"; exit 1; }
	fi
done

echo "=== transferred; $sent bursts, $hangs hangs, $(( ($(date +%s) - t0) / 60 )) min"
echo "=== end-to-end verify"
wait_for_device || exit 1
FINAL=$(timeout 600 $SSH "$HOST" "md5sum $DEST" 2>/dev/null | cut -d' ' -f1)
echo "  local  $LOCAL_MD5"
echo "  remote ${FINAL:-<none>}"
[ "$LOCAL_MD5" = "$FINAL" ] && { echo "  MATCH"; exit 0; } || { echo "  MISMATCH -- do not install"; exit 1; }
