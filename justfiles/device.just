# Shared device command recipes (SSH-based)
#
# These recipes interact with running devices over SSH.
# All commands assume root@<host> SSH access is configured.

# Show RAUC status on a running device
[group('device')]
rauc-status host:
    ssh root@{{host}} "rauc status"

# Install RAUC bundle on a running device
[group('device')]
[script('bash')]
rauc-install host bundle:
    echo "Copying bundle to device..."
    scp {{bundle}} root@{{host}}:/data/update.raucb
    echo "Installing bundle..."
    ssh root@{{host}} "rauc install /data/update.raucb && rm /data/update.raucb"
    echo "Done. Reboot device to boot into new slot."

# Reboot a device
[group('device')]
reboot host:
    ssh root@{{host}} "reboot"

# Show system status on a running device
[group('device')]
[script('bash')]
status host:
    echo "=== RAUC Status ==="
    ssh root@{{host}} "rauc status" || true
    echo ""
    echo "=== Disk Usage ==="
    ssh root@{{host}} "df -h" || true
    echo ""
    echo "=== Uptime ==="
    ssh root@{{host}} "uptime" || true

# === Diagnostics ===
#
# Thin wrappers over tools/kiosk-*.sh. The reasoning behind each check lives in
# the script it wraps; .claude/skills/kiosk-debug/SKILL.md decides which one a
# given symptom calls for.

# Takes a CIDR rather than a host: this is the recipe for when the address is
# what you are missing. The script picks its own L2 view -- Windows interop
# under WSL, a local interface otherwise -- and prints which one it used,
# because a miss means something different in each.
#
# Exit 3 stays non-zero: it means "no L2 view, nothing could be identified", and
# a caller that read that as "the subnet is empty" is the exact mistake this
# recipe exists to prevent. But a rc=3 run can still have printed useful
# addresses above, and just's bare "error: recipe find failed" describes none of
# that, so the line below names what 3 means before just says its piece.
[group('device')]
[script('bash')]
[doc("Sweep a /24 and report Raspberry Pi OUIs from the best neighbour table available")]
find cidr:
    tools/kiosk-find.sh {{cidr}}
    rc=$?
    if [ $rc -eq 3 ]; then
        echo "exit 3: no L2 view of {{cidr}}. Anything printed above is reachability only," >&2
        echo "        not an identification, and no line of it says the subnet is empty." >&2
    fi
    exit $rc

# Run from the host serving the page -- a socket table only holds that host's
# own sockets, so the address to pass is the KIOSK's, not this host's.
[group('device')]
[doc("Infer browser state from TCP connections to the served page")]
tcp-state kiosk-addr port="8080":
    tools/kiosk-tcp-state.sh {{kiosk-addr}} {{port}}

[group('device')]
[doc("Capture the screen and check it is neither blank nor stale")]
screenshot host out="":
    tools/kiosk-screenshot.sh root@{{host}} {{out}}

# n is a SAMPLE COUNT, not hours: the sampler writes one line every 5 minutes,
# so 12 is the last hour and 288 the last day. Omitting it reads the whole log.
[group('device')]
[doc("Read the soak log summary from the device")]
soak-summary host n="24":
    tools/kiosk-ssh.sh root@{{host}} 'kiosk-soak.sh --summary {{n}}'

# Costs a reboot of the device and about three minutes. outdir defaults to
# local/ because the profile comes with a full journal dump -- hostname,
# addresses, SSID -- and local/ is this repository's gitignored home for exactly
# that; just runs recipes with cwd at the repository root, which is public.
[group('device')]
[doc("Profile one boot end to end: arm, reboot, collect, analyze, disarm")]
bootprofile host outdir="local":
    tools/kiosk-bootprofile.sh root@{{host}} {{outdir}}

# Pull-only, and deliberately so: /data is the one thing on this device that a
# reflash does not reproduce, and a backup recipe that can also write is a
# restore path nobody has rehearsed. Restoring is `just provision-device` plus
# whatever this archive holds, applied by hand.
#
# One plain stream, no chunking -- the plain-transfer shape verified against the
# capped board with #29. gzip -t below is what says whether the transfer arrived
# whole.
#
# The pull itself needs a reachable device. What runs without one: mkdir, the
# overwrite guard, and gzip -t catching a truncated (here, empty) stream.
#
# The tarball lands in local/: it holds /data/config/wpa_supplicant.conf and the
# persistent journal, and local/ is this repository's gitignored home for
# exactly that. just runs recipes with cwd at the repository root, which is
# public.
#
# host is an ssh target, `root@<addr>`, not a bare address: it defaults to
# kiosk-host, which every other host-defaulting recipe shares.
[group('device')]
[script('bash')]
[doc("Pull a dated tarball of the device's /data to this host")]
kiosk-backup host=kiosk-host:
    SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
    mkdir -p local
    OUT="local/kiosk-data-$(date +%F).tar.gz"
    if [ -e "$OUT" ]; then
        echo "$OUT exists -- move it aside rather than overwriting today's backup"
        exit 1
    fi
    $SSH {{host}} 'tar -czf - -C / data' > "$OUT"
    # A truncated stream still leaves a file, and gzip is where that shows up.
    gzip -t "$OUT" || { echo "$OUT does not decompress -- the transfer was cut short"; rm -f "$OUT"; exit 1; }
    echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
