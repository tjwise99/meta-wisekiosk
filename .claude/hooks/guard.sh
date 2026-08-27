#!/usr/bin/env bash
# PreToolUse guard. Exit 2 blocks the tool call; stderr is fed back to the model.
#
# Each rule below corresponds to a failure that actually happened, or to an
# irreversible action that currently depends on recall. CONTRIBUTING.md and
# CLAUDE.md carry the reasoning needed to plan correctly; this is the backstop
# for when recall fails. Prose is a suggestion, this is a gate -- and neither
# replaces the other, because a model that has not read the prose proposes the
# banned thing, gets blocked, and wastes a turn.
#
# Scope is THIS repository's hazards: a board that must not be touched, a disk
# that must not be overwritten, a lifeline that must not be cut. A rule the
# global guard already implements is not repeated here -- two enforcers of one
# rule drift -- so PR merges live there and not in this file. A rule it does NOT
# implement is not covered by saying it belongs elsewhere: rule 7 (bare -f on
# pkill/pgrep) is here because nothing host-wide carries it.
#
# Device identity is read ONLY from gitignored `local/device-identity.md`. This
# repository is PUBLIC: a tracked address is the thing the repository exists to
# not publish, so a guard keyed on one would be its own leak.
#
# Fail-open everywhere: no jq, no payload, no identity file, or an unparseable
# anything, and the call goes through. A guard that blocks on its own breakage
# gets disabled, and then it guards nothing.
#
# Self-test: bash .claude/hooks/guard-test.sh  (wired into `just guards` and CI)
set -uo pipefail

command -v jq > /dev/null 2>&1 || exit 0

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -n "$tool" ] || exit 0

REPO=${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
# Both overridable so the self-test can drive real fixtures rather than the
# machine it happens to run on. A test that only passes on one host measures
# that host.
IDFILE=${KIOSK_IDENTITY_FILE:-$REPO/local/device-identity.md}
SYSFS=${KIOSK_SYSFS_ROOT:-/sys}

# One `key = value` from the map's ```identity fence, empty when absent. Scoped
# to the fence so the prose around it -- which necessarily shows the format --
# cannot answer a lookup. The value may itself contain '=', so the split is at
# the FIRST one.
id_value() {
    [ -f "$IDFILE" ] || return 0
    awk -v want="$1" '
        /^```identity[[:space:]]*$/ { inblock = 1; next }
        inblock && /^```[[:space:]]*$/ { exit }
        inblock {
            eq = index($0, "=")
            if (eq == 0) next
            key = substr($0, 1, eq - 1)
            val = substr($0, eq + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            if (key == want) { print val; exit }
        }' "$IDFILE" 2>/dev/null
}

case "$tool" in
Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -n "$cmd" ] || exit 0

    # Heredoc bodies are data OR commands, decided by what consumes them. A
    # commit message or a document that merely mentions a banned pattern is not
    # an invocation -- blocking that was the ancestor guard's own first false
    # positive, caught when it refused the very commit that added it. But
    # `ssh <board> 'bash -s' <<'EOF'` is how tools/kiosk-ssh.sh documents batching
    # remote work, and every line of THAT body runs on the board. Stripping it
    # disarmed rules 1, 4 and 5 for the repository's own documented idiom.
    #
    # So: a body is kept when its opener names a shell interpreter (the body is
    # that shell's input) and dropped otherwise. Only shells -- a python or perl
    # heredoc is not shell syntax, and scanning it for shell verbs matches words,
    # not commands. `.sh` filenames and `~/.ssh/` paths are excluded by the
    # surrounding character classes, so `cat > tools/x.sh <<EOF` still drops.
    code=$(printf '%s\n' "$cmd" | awk -v shre='(^|[^[:alnum:]_.-])(ssh|bash|sh|zsh|dash|ksh)([^[:alnum:]_.-]|$)' '
        !inhd && match($0, /<<-?['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/) {
            t = substr($0, RSTART, RLENGTH)
            sub(/^<<-?['"'"'"]?/, "", t)
            sub(/['"'"'"]$/, "", t)
            term = t; inhd = 1; keep = ($0 ~ shre); print; next
        }
        inhd && $0 == term { inhd = 0; next }
        inhd { if (keep) print; next }
        { print }')

    # Whole-token view of the command, for matching an ssh target without a
    # regex built from a value (an address is full of '.', which an ERE reads as
    # "any character"). '/' is deliberately NOT a separator: splitting on it
    # would turn the MACHINE component of
    # build/tmp-<machine>/deploy/images/<machine>/... into a bare token equal to
    # the prod board's hostname, and every explicit-path bundle command would
    # false-block.
    # Shell punctuation and quoting all count as separators -- an address inside
    # an array assignment, `ssh=(ssh -o … root@<addr>)`, otherwise ends in a
    # token with a trailing ')' and matches nothing.
    #
    # tr sets are the same length on purpose: fifteen separators, fifteen
    # spaces. GNU tr silently pads a short second set by repeating its last
    # character, which would hide a miscount here rather than report one.
    norm=" $(printf '%s' "$code" | tr '@=:,"'"'"'();|&<>\t\n' '               ') "

    has_token() { [[ $norm == *" $1 "* ]]; }

    # Whitespace-split words of the command, for position-aware matching. Globbing
    # is off around the split: an unquoted `*` in the command would otherwise
    # expand against the working directory and replace the word with filenames.
    set -f
    # shellcheck disable=SC2206
    WORDS=($code)
    set +f

    # Every ssh invocation in the command, as `target<TAB>remote-command` lines.
    #
    # Position is the whole point. A bare hostname TOKEN cannot stand for "this
    # targets that board": the prod hostname is also the Yocto MACHINE name, so
    # `MACHINE=<host> just build` and every build path would false-match. Only
    # the first non-option word after an ssh client is a target, and only the
    # word after THAT is the remote command -- which is what separates
    # `ssh <host> reboot` from `ssh <host> 'grep -c reboot /var/log/messages'`.
    ssh_pairs=$(
        armed=0
        skip=0
        target=""
        for w in ${WORDS+"${WORDS[@]}"}; do
            w=${w#[\"\']}
            w=${w%[\"\']}
            case "$w" in
                ssh | */ssh | *ssh.sh) armed=1; skip=0; target=""; continue ;;
            esac
            [ "$armed" -eq 1 ] || continue
            if [ "$skip" -eq 1 ]; then skip=0; continue; fi
            case "$w" in
                # ssh options that take a separate value; the value is not a target.
                -l | -p | -o | -i | -F | -b | -c | -m | -E | -J | -L | -R | -D | -W | -Q | -S | -e)
                    skip=1; continue ;;
                -*) continue ;;
            esac
            if [ -z "$target" ]; then target=$w; continue; fi
            # A privilege or assignment prefix is not the remote command --
            # `ssh <board> 'sudo reboot'` reboots the board, and reading the
            # prefix as the verb made `sudo` a one-word bypass of rule 1.
            case "$w" in
                sudo | doas | env | nice | ionice | command | time) continue ;;
                [A-Za-z_]*=*) continue ;;
            esac
            printf '%s\t%s\n' "$target" "$w"
            target=""
            armed=0
        done
        [ -n "$target" ] && printf '%s\t\n' "$target"
    )
    # Matched with bash string tests, never `… | grep -q`: -q exits on the first
    # hit, the producer dies of SIGPIPE at 141, and pipefail returns that -- the
    # test would read false precisely when the pattern matches.
    ssh_target() { [[ $'\n'$ssh_pairs$'\n' == *$'\n'"$1"$'\t'* ]]; }
    ssh_verb() { [[ $'\n'$ssh_pairs$'\n' == *$'\t'"$1"$'\n'* ]]; }

    # True when $1 is the value of a `host=` recipe argument (`just … host=<host>`).
    # The pair is what makes this safe: `MACHINE=<host>` normalises to a different
    # pair and does not match.
    host_arg() { [[ $norm == *" host $1 "* ]]; }

    # Command position, tolerating the privilege and assignment prefixes the real
    # invocations carry. Every rule below that anchors a VERB anchors it with
    # this: a bare `(^|[;&|(]|&&|\|\|)[[:space:]]*` anchor is defeated by typing
    # `sudo` in front, and `sudo` is the natural hand-run spelling for most of
    # what these rules protect -- a /boot write, a reboot, an image write all
    # need root, and justfiles/deploy.just itself runs `"${SUDO[@]}" bmaptool`.
    # Anything using the bare anchor is a hole; the self-test carries a
    # sudo-prefixed must-block case per rule so a regression fails the build.
    CMDPOS='(^|[;&|(]|&&|\|\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((sudo|doas|env|nice|ionice|command|time)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)*'

    # --- RULE 1 -- destructive operation aimed at the PROD board -------------
    # The prod unit is wall-mounted and carries the live soak run (issue #40).
    # An OTA, a reboot, a rollback or a reprovision there ends a run that cannot
    # be replayed, and a bad slot costs a physical trip. The owner's standing
    # rule is that prod is read-only; the Justfile's own refusals cover the
    # tree-state half, not the which-board half, so this is the one that knows.
    #
    # Read-only recipes (status, screenshot, soak-summary, kiosk-backup,
    # rauc-status, tcp-state, kiosk-preflight) are NOT here: blocking those
    # would block the only way to observe the board this rule protects.
    #
    # Limit, stated rather than hidden: the target must be visible IN THIS
    # COMMAND. A `KIOSK_HOST` exported in an earlier tool call is invisible to a
    # hook that runs per call, and no rule here can see it.
    prod_addr=$(id_value prod.address)
    prod_host=$(id_value public.prod.hostname)
    targets_prod=0
    [ -n "$prod_addr" ] && has_token "$prod_addr" && targets_prod=1
    # Hostname only where the word sits in a TARGET position: `user@host`, the
    # first non-option word after an ssh client, or a `host=` recipe argument. A
    # bare hostname token is also the Yocto MACHINE name, which appears in
    # legitimate build paths and in `MACHINE=` assignments.
    if [ -n "$prod_host" ]; then
        case "$code" in *"@$prod_host"*) targets_prod=1 ;; esac
        ssh_target "$prod_host" && targets_prod=1
        host_arg "$prod_host" && targets_prod=1
    fi
    # The power verbs are anchored the way every other alternative here is.
    # Unanchored, `reboot` fired on the word itself, and
    # `ssh <prod> 'grep -c reboot /var/log/messages'` is an OBSERVATION --
    # reading the soak log for reboot events is the main legitimate activity on
    # that board, and the block message promises observation is allowed. Two
    # verb positions: command position (CMDPOS, so a `sudo` prefix is not a way
    # past it), and the remote command of an ssh (`ssh_verb`), which is where an
    # argument to a grep is not.
    prod_reboot=0
    for v in reboot shutdown halt poweroff; do
        ssh_verb "$v" && prod_reboot=1
    done
    if [ "$targets_prod" -eq 1 ] && { [ "$prod_reboot" -eq 1 ] || printf '%s' "$code" | grep -qE \
        "just[[:space:]]+(kiosk-ota|kiosk-install|kiosk-send-direct|kiosk-rollback|kiosk-reboot|reboot|rauc-install|provision-device|bootprofile|flash)([[:space:]]|$)|rauc[[:space:]]+install|systemctl[[:space:]]+(reboot|poweroff)|${CMDPOS}(reboot|shutdown|halt|poweroff)([[:space:]]|$)|tools/provision\.sh[[:space:]]+device|tools/rauc-rotate"; }; then
        cat >&2 <<'MSG'
BLOCKED: that is a destructive operation aimed at the PROD board.

Prod is wall-mounted and is carrying the live soak run. An OTA, install,
rollback, reboot, reprovision or profile there ends a run that cannot be
replayed, and a slot that comes up wrong costs a physical trip to the wall.

Retarget the BENCH board -- `local/device-identity.md` has the role map, and
`just find <cidr>` reports which address a swapped board took. Observation of
prod (status, screenshot, soak-summary, kiosk-backup, rauc-status) is allowed
and is not what this blocked.
MSG
        exit 2
    fi

    # --- RULE 2 -- writing an image to a NON-REMOVABLE block device ---------
    # `just flash /dev/sdX` and `dd of=...` are one character away from the
    # workstation's own disk, and the mistake is unrecoverable and instant. The
    # Justfile refuses a build from a dirty tree; nothing in it asks whether the
    # TARGET is a card. Classification is read from sysfs rather than assumed
    # from the name, because /dev/sda is a card reader on one host and the root
    # disk on the next.
    #
    # Unknown devices are ALLOWED -- a name that resolves to nothing (the
    # README's own `/dev/sdX` placeholder) is not evidence of a system disk, and
    # failing closed on the unknown would make the rule unusable.
    #
    # CMDPOS is what let `sudo bmaptool copy <image> /dev/sda` through when this
    # rule used a bare `(dd|bmaptool)` anchor. The writer list is not just
    # dd/bmaptool either -- a redirect, `tee`, `wipefs` or `mkfs` reach the same
    # platter -- and `just provision-fresh-card <device>` mounts and writes
    # partition 4 as root one README line below `just flash`.
    if printf '%s' "$code" | grep -qE \
        "${CMDPOS}(dd|bmaptool|wipefs|mkfs(\.[A-Za-z0-9]+)?|sgdisk|sfdisk|fdisk|parted|blkdiscard)([[:space:]]|$)|just[[:space:]]+(flash|provision-fresh-card)([[:space:]]|$)|of=[\"']?/dev/|>[[:space:]]*[\"']?/dev/(sd|hd|vd|xvd|nvme|mmcblk|loop|disk)|[[:space:]]tee([[:space:]]+-[^[:space:]]+)*[[:space:]]+[\"']?/dev/"; then
        # `/dev/disk/by-id/...` is captured whole and resolved: taking only the
        # leading `/dev/disk` made it an unknown name, which is the allowed path.
        # DEVROOT is overridable for the same reason SYSFS is -- a self-test that
        # can only run against this machine's /dev measures this machine.
        DEVROOT=${KIOSK_DEV_ROOT:-/dev}
        for dev in $(printf '%s' "$code" | grep -oE "/dev/(disk/by-[a-z]+/[^[:space:]\"'\`]+|[A-Za-z0-9]+)" | sort -u); do
            written=$dev
            node="$DEVROOT/${dev#/dev/}"
            if [ -e "$node" ]; then
                resolved=$(readlink -f "$node" 2>/dev/null)
                [ -n "$resolved" ] && dev="/dev/${resolved##*/}"
            fi
            base=${dev#/dev/}
            # Partition -> whole disk: sda1 -> sda, mmcblk0p1 -> mmcblk0,
            # nvme0n1p1 -> nvme0n1. sysfs carries `removable` on the disk only.
            case "$base" in
                mmcblk*p[0-9]*) base=${base%%p[0-9]*} ;;
                nvme*p[0-9]*)   base=${base%%p[0-9]*} ;;
                sd[a-z][0-9]*|vd[a-z][0-9]*|xvd[a-z][0-9]*|hd[a-z][0-9]*)
                    base=$(printf '%s' "$base" | sed 's/[0-9]*$//') ;;
            esac
            blocked=""
            case "$base" in
                nvme*|vd[a-z]|xvd[a-z])
                    blocked="$base is an internal system disk by name (NVMe / virtio); no card reader presents one" ;;
            esac
            if [ -z "$blocked" ] && [ -r "$SYSFS/block/$base/removable" ]; then
                if [ "$(cat "$SYSFS/block/$base/removable" 2>/dev/null)" = "0" ]; then
                    blocked="$SYSFS/block/$base/removable reports 0 -- this is a fixed disk, not a card"
                fi
            fi
            if [ -n "$blocked" ]; then
                cat >&2 <<MSG
BLOCKED: writing to $written ($dev), which is not removable media.

$blocked

Flashing the wrong device destroys the host, instantly and with no undo. Confirm
the card with \`lsblk -o NAME,SIZE,RM,MODEL\` (RM=1 is removable) and re-run
against that device. \`just flash\` expects the SD card, not a system disk.
MSG
                exit 2
            fi
        done
    fi

    # --- RULE 3 -- 2>/dev/null on an ssh to a board -------------------------
    # A suppressed probe makes a broken CHECK indistinguishable from a broken
    # DEVICE. This produced a false "kernel missing from slot A" on 2026-08-13:
    # the mount had failed and the error vanished.
    #
    # Scoped to one command SEGMENT, because suppression on an unrelated local
    # command in the same call is not a suppressed device probe -- checking the
    # whole command once blocked `tail file 2>/dev/null` merely because an ssh
    # appeared elsewhere in the call. The HOST, though, is looked for across the
    # whole command: the array style used here puts it on the definition line
    #   ssh=(ssh -o ... root@<addr>); timeout 60 "${ssh[@]}" 'cmd' 2>/dev/null
    # so the dangerous segment names ssh but never the host.
    board_named=0
    for key in prod.address bench.address; do
        v=$(id_value "$key")
        [ -n "$v" ] && has_token "$v" && board_named=1
    done
    for key in public.prod.hostname bench.hostname; do
        v=$(id_value "$key")
        if [ -n "$v" ]; then
            case "$code" in *"@$v"*) board_named=1 ;; esac
            ssh_target "$v" && board_named=1
            host_arg "$v" && board_named=1
        fi
    done
    # `ssh` is word-anchored, as every sibling rule in this file is. A bare
    # substring match blocked `ssh-keygen -R <addr> 2>/dev/null` -- a local
    # known_hosts edit, and the routine step after reflashing a board -- and
    # `cat ~/.ssh/known_hosts 2>/dev/null`, on the `.ssh/` path component. The
    # trailing class excludes '/' and '-' for those two; the repository's own ssh
    # wrapper is named, because it IS the probe.
    #
    # Counted with -c rather than ended with `grep -q`: -q exits on the first hit
    # and the producer dies of SIGPIPE at 141, which pipefail then returns -- the
    # condition would read false precisely when the pattern matches.
    suppressed=$(printf '%s\n' "$code" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' \
                 | grep -cE "2>/dev/null.*((^|[^[:alnum:]_.-])ssh([^[:alnum:]_/-]|$)|kiosk-ssh\.sh)|((^|[^[:alnum:]_.-])ssh([^[:alnum:]_/-]|$)|kiosk-ssh\.sh).*2>/dev/null") || true
    if [ "$board_named" -eq 1 ] && [ "${suppressed:-0}" -gt 0 ]; then
        cat >&2 <<'MSG'
BLOCKED: 2>/dev/null on an ssh command to a kiosk board.

A suppressed probe cannot distinguish "the check is broken" from "the device is
broken". Let stderr through, or capture it and print it on failure.
MSG
        exit 2
    fi

    # --- RULE 4 -- THE LIFELINE ---------------------------------------------
    # SSH over wlan0 is the only way to reach a board. Losing it costs a
    # physical trip to a wall-mounted unit -- the single failure class this
    # project spends real caution to avoid, and there is no remote undo.
    # Masking logind / userdbd / resolved / zram is deliberate (kiosk-hardware,
    # issue #17) and stays allowed; only the network path is protected.
    if printf '%s' "$code" | grep -qE 'systemctl[^|;&]*(disable|mask|stop)' \
       && printf '%s' "$code" | grep -qE '(sshd|ssh\.service|ssh\.socket|wpa[-_]supplicant|systemd-networkd|dhcpcd|networking)'; then
        cat >&2 <<'MSG'
BLOCKED: that disables part of the LIFELINE (sshd / wpa_supplicant /
systemd-networkd / dhcpcd / networking).

SSH over wlan0 is the only way to reach this device, and there is no remote
undo. `just kiosk-recover` reverses the boot trims that ARE reversible; this is
not one of them.
MSG
        exit 2
    fi

    # --- RULE 5 -- /boot is the ONE partition with no A/B protection --------
    # The kernel and rootfs are per-slot and fall back on their own, but
    # cmdline.txt, config.txt and uboot.env are SHARED, so a bad write breaks
    # BOTH slots and needs the card pulled. Reads are fine. `rauc status mark-*`
    # writes uboot.env as normal operation and is allowed.
    #
    # THREE anchored shapes, because the ancestor of this rule over-matched
    # three times: unanchored `fw_setenv` fired on the word inside an echo; `cp`
    # matched a READ of /boot; and "a-r-m" contains "rm", so `arch/arm/boot/dts/`
    # blocked a read-only `ls` of the kernel source tree. The general fix for the
    # last is that /boot/ counts as THE /boot mount only when it STARTS a path --
    # preceded by whitespace, start of line, or '='. That also stops
    # /mnt/root/boot/ (a slot rootfs reached by bind mount) being mistaken for
    # the shared FAT partition.
    B='(^|[[:space:]]|=)/boot/'
    # The escape hatch is read from the COMMAND TEXT, not the environment. This
    # hook runs in its own process BEFORE the command executes, so an inline
    # `VAR=1 cmd` prefix -- which is what the message tells you to type -- never
    # reaches it as a variable. Checking the environment here looked right,
    # passed a test that exported the variable, and opened the gate the first
    # time it was really used.
    if ! printf '%s' "$cmd" | grep -qE '(^|[[:space:]])KIOSK_ALLOW_BOOT_WRITE=1[[:space:]]' && {
         printf '%s' "$code" | grep -qE "${CMDPOS}fw_setenv([[:space:]]|$)" ||
         printf '%s' "$code" | grep -qE ">>?[[:space:]]*/boot/" ||
         printf '%s' "$code" | grep -qE "${CMDPOS}(rm|tee|truncate|dd|sed)([[:space:]][^|;&]*)?${B}" ||
         printf '%s' "$code" | grep -qE "${CMDPOS}(cp|mv)[[:space:]][^|;&]*${B}[^[:space:]|;&]*[[:space:]]*($|[;&|])"
       }; then
        cat >&2 <<'MSG'
BLOCKED: writing to /boot on a kiosk board.

/boot is the only partition with NO A/B protection -- the kernel and rootfs live
in the RAUC slots and fall back automatically, but cmdline.txt, config.txt and
uboot.env are SHARED, so a bad write breaks both slots at once and needs the
card pulled.

Kernel and boot changes ship by OTA instead, so that the A/B fallback covers
them. If a /boot write is genuinely required it needs explicit per-change owner
authorization (as ` panic=10` had, on a bench unit, 2026-08-12).

With that authorization, re-run with the escape hatch:
  KIOSK_ALLOW_BOOT_WRITE=1 <command>
MSG
        exit 2
    fi

    # --- RULE 6 -- `; echo $?` after a pipeline -----------------------------
    # A pipeline reports the LAST command's status, so `just verify | tail -50 ;
    # echo $?` reports tail. A failing gate reads green. Done exactly that on
    # 2026-08-13 and the number had to be retracted in the same message.
    if printf '%s' "$code" | grep -qE '\|[^|]*;[[:space:]]*echo[^;]*\$\?'; then
        cat >&2 <<'MSG'
BLOCKED: `; echo $?` after a pipeline reports the LAST command's exit status
(usually tail/grep), not the work you care about. A failing gate reads green.

Instead: redirect to a file and test $? on the very next line, or read
"${PIPESTATUS[@]}" in bash / "$pipestatus[@]" in zsh -- indexed from 1 in zsh.
MSG
        exit 2
    fi

    # --- RULE 7 -- bare -f on pkill/pgrep -----------------------------------
    # The pattern being searched for is IN the harness's own shell command line,
    # so `-f` matches that line and the tool call kills itself. Happened twice on
    # 2026-08-13, exit 144.
    #
    # This one is here rather than in the global guard because there is no
    # host-wide rule to inherit: the global guard covers PR merges and nothing
    # else. `-x -f '<exact argv>'` is the safe spelling and stays allowed --
    # the first option token has to END in f for this to fire.
    if printf '%s' "$code" | grep -qE "${CMDPOS}(pkill|pgrep)[[:space:]]+-[a-zA-Z]*f([[:space:]]|$)"; then
        cat >&2 <<'MSG'
BLOCKED: a bare -f on pkill/pgrep matches this harness's own shell command line,
because the pattern you are searching for is IN that command line. Killed the
tool call twice in this project (exit 144).

Instead:
  pid=$(pgrep -x -f "/bin/bash /full/path/to/script.sh" | head -1); kill "$pid"
  pkill -x <exact-process-name>
MSG
        exit 2
    fi
    ;;

Edit|Write|MultiEdit|NotebookEdit)
    fp=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -n "$fp" ] || exit 0
    case "$fp" in
    "$REPO"/*)
        # --- RULE 8 -- editing the build tree mid-build ---------------------
        # bitbake parses every recipe at start. Editing now either changes
        # nothing (you build stale content believing otherwise) or invalidates
        # the run -- and a full run here is ~4.5 h. Done twice on 2026-08-13.
        # Environment-dependent by nature, and the self-test says so rather than
        # asserting a block that only holds while a build is up.
        if timeout 5 docker ps --format '{{.Image}}' 2>/dev/null | grep -qi 'kas'; then
            cat >&2 <<MSG
BLOCKED: a kas/bitbake build container is running, and this edits the build tree.

bitbake parsed these recipes at start -- editing now either changes nothing or
invalidates a run that costs ~4.5 h.

Instead: develop in a git worktree and merge after the build finishes.
  git -C $REPO worktree list
MSG
            exit 2
        fi
        ;;
    esac
    ;;
esac
exit 0
