#!/usr/bin/env bash
# Self-test for .claude/hooks/guard.sh. Run by `just guards` and by CI, so a
# future edit that breaks a rule fails the build instead of silently opening a
# gate. This is what makes the guard trustworthy: without it, "the guard passed"
# and "the guard matched nothing at all" look identical.
#
# It lives in a file because the payloads necessarily contain the very patterns
# the guard blocks -- typing them into a Bash tool call trips the guard itself.
#
# EVERY rule is tested in BOTH directions. A guard that fires on legal input is
# its own failure, and a must-block case hides that completely.
#
# Both directions of every INPUT SHAPE the guard normalises, too, not only of
# every rule. A suite with no heredoc must-block case and no sudo-prefixed case
# reported pass=60 fail=0 while the guard allowed an OTA to prod inside
# `ssh … 'bash -s' <<'EOF'` and `sudo bmaptool copy <image> /dev/sda` against a
# fixed disk: "the guard passed" and "the guard never looked" were identical for
# those two paths. A new normalisation step needs its own pair of cases.
#
# Identity and sysfs are FIXTURES, never this machine and never the real map:
#   - the real map is gitignored, so a test reading it could not run in CI, and
#     a test with real values baked in would publish them (this repo is PUBLIC);
#   - the fixture addresses are RFC 5737 documentation addresses, which identify
#     nothing and pass `tools/ci-guards.sh` guard 6 and `tools/scrub-identity.py`;
#   - the fixture prod HOSTNAME deliberately ends in `0-wifi`, reproducing the
#     shape of the real one: it is also the Yocto MACHINE name, so it appears
#     inside legitimate build paths, and the "spelled differently but valid"
#     case below proves the guard does not block those.
set -uo pipefail

G="$(cd "$(dirname "$0")" && pwd)/guard.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

cat > "$T/device-identity.md" <<'FIXTURE'
# fixture identity map
```identity
prod.address    = 198.51.100.7
bench.address   = 198.51.100.14
bench.hostname  = fixture-bench
public.prod.hostname = fixture-board0-wifi
```
FIXTURE

mkdir -p "$T/sys/block/sdz" "$T/sys/block/sdy"
echo 0 > "$T/sys/block/sdz/removable"   # a fixed disk
echo 1 > "$T/sys/block/sdy/removable"   # a card reader

# A /dev fixture, for the same reason sysfs is one. `/dev/disk/by-id/...` is a
# symlink to a disk node, and taking only its leading component made it an
# unknown name -- which is the ALLOWED path, so a by-id write to the system disk
# went through. Resolving needs a real symlink, and a real one on this machine
# would make the case untestable in CI.
mkdir -p "$T/dev/disk/by-id"
: > "$T/dev/sdz"
ln -s ../../sdz "$T/dev/disk/by-id/fixture-fixed-disk"

export KIOSK_IDENTITY_FILE="$T/device-identity.md"
export KIOSK_SYSFS_ROOT="$T/sys"
export KIOSK_DEV_ROOT="$T/dev"

pass=0; fail=0
# Extra environment for the guard under test, as `env` arguments. Used by the
# worktree block, which has to UNSET the identity-file override -- an assignment
# prefix cannot express that, and a prefix on a shell FUNCTION persists past the
# call in bash, which would silently re-point every later case.
TENV=()
t() { # $1=label $2=expect $3=payload
  out=$(printf '%s' "$3" | env ${TENV+"${TENV[@]}"} "$G" 2>&1); rc=$?
  got=$([ $rc -eq 2 ] && echo BLOCK || echo ALLOW)
  if [ "$got" = "$2" ]; then r="ok  "; pass=$((pass+1)); else r="FAIL"; fail=$((fail+1)); fi
  printf '%s expected=%-5s got=%-5s  %s\n' "$r" "$2" "$got" "$1"
  [ "$got" = "$2" ] || printf '        %s\n' "$out" | head -n 3
}
# jq-constructed, NOT printf: a payload containing a double quote (e.g. echo
# "exit=$?") breaks hand-built JSON, jq returns an empty command, and the guard
# then has nothing to match -- the test reports ALLOW while measuring nothing.
b() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
e() { jq -nc --arg f "$1" '{tool_name:"Edit",tool_input:{file_path:$f}}'; }

PROD='198.51.100.7'; BENCH='198.51.100.14'; PHOST='fixture-board0-wifi'
# Assembled, so no line in this file is itself the banned spelling.
KILLPAT='pk''ill'; GREPPAT='pg''rep'

echo "--- must BLOCK: rule 1, destructive op aimed at PROD ---"
t "prod OTA by address"   BLOCK "$(b "just kiosk-ota host=root@$PROD")"
t "prod reboot by name"   BLOCK "$(b "just kiosk-reboot host=root@$PHOST")"
t "prod rauc install"     BLOCK "$(b "ssh root@$PROD rauc install /data/update.raucb")"
t "prod bare reboot"      BLOCK "$(b "ssh root@$PROD reboot")"
t "prod reprovision"      BLOCK "$(b "tools/provision.sh device root@$PROD")"
t "prod scp-style target" BLOCK "$(b "just kiosk-send-direct host=root@$PROD:/data")"
# The hostname in ssh-target position, with no `user@` to key on. `-l root <host>`
# and a bare `ssh <host> <cmd>` are ordinary spellings, and matching the bare
# TOKEN is not available here -- it is also the MACHINE name (see the ALLOW
# cases below). Position is what separates them.
t "prod ssh, no user@"    BLOCK "$(b "ssh $PHOST reboot")"
t "prod ssh -l root"      BLOCK "$(b "ssh -l root $PHOST reboot")"
t "prod host= no user@"   BLOCK "$(b "just kiosk-ota host=$PHOST")"
# THE heredoc regression. tools/kiosk-ssh.sh documents `'bash -s' <<'EOF'` as the
# way to batch remote work, so this is the encouraged spelling, not an evasion --
# and stripping the body disarmed rules 1, 4 and 5 for it.
t "prod OTA in heredoc"   BLOCK "$(b "$(printf "tools/kiosk-ssh.sh root@%s 'bash -s' <<'EOF'\nrauc install /data/update.raucb\nreboot\nEOF" "$PROD")")"
# A power verb on a board is run as root, so `sudo` in front of it is the
# NATURAL spelling, not an evasion -- and it moved the verb off command position
# and out of the ssh remote-command slot, which disarmed the whole rule.
t "prod sudo reboot"      BLOCK "$(b "ssh root@$PROD 'sudo reboot'")"
t "prod sudo reboot bare" BLOCK "$(b "ssh root@$PROD sudo reboot")"
t "prod shutdown -r"      BLOCK "$(b "ssh root@$PROD 'shutdown -r now'")"
t "prod local sudo reboot" BLOCK "$(b "ssh root@$PROD uptime && sudo reboot")"
# An assignment AFTER the privilege word. `env VAR=V <cmd>` is the ONLY way env
# is ever used, and the prefix used to accept assignments only BEFORE it -- so
# the commonest spelling there is walked past rules 1, 2, 5 and 7 untouched.
t "prod sudo VAR= reboot" BLOCK "$(b "ssh root@$PROD uptime && sudo LC_ALL=C reboot")"
t "prod env VAR= reboot"  BLOCK "$(b "ssh root@$PROD uptime && env LC_ALL=C reboot")"
# A wrapper option with a SEPARATE value walked the anchor past the verb too.
t "prod sudo -u root"     BLOCK "$(b "ssh root@$PROD uptime && sudo -u root reboot")"
t "prod ssh sudo -u root" BLOCK "$(b "ssh root@$PROD sudo -u root reboot")"
# `systemctl halt` and `systemctl kexec` end the soak exactly as `reboot` does;
# the systemctl alternation listed only reboot/poweroff.
t "prod systemctl halt"   BLOCK "$(b "ssh root@$PROD systemctl halt")"
t "prod systemctl kexec"  BLOCK "$(b "ssh root@$PROD systemctl kexec")"

echo "--- must BLOCK: rule 2, image write to a non-removable device ---"
t "flash to fixed disk"   BLOCK "$(b 'just flash /dev/sdz')"
t "dd to nvme"            BLOCK "$(b 'dd if=core-image.wic of=/dev/nvme0n1 bs=4M')"
t "dd to virtio disk"     BLOCK "$(b 'dd if=core-image.wic of=/dev/vda bs=4M')"
t "bmaptool to fixed"     BLOCK "$(b 'bmaptool copy core-image.wic.bz2 /dev/sdz')"
t "dd to fixed partition" BLOCK "$(b 'dd if=x.img of=/dev/sdz1')"
# Every one of these needs root, and justfiles/deploy.just runs bmaptool under
# sudo, so the sudo-prefixed form is the NATURAL hand-run spelling -- it moved
# the writer off command position and the whole rule stopped applying.
t "sudo bmaptool"         BLOCK "$(b 'sudo bmaptool copy core-image.wic.bz2 /dev/sdz')"
t "sudo dd, quoted of="   BLOCK "$(b "sudo dd if=x.wic of='/dev/sdz' bs=4M")"
t "device via variable"   BLOCK "$(b "D=/dev/sdz; sudo dd if=x.wic of=\$D")"
t "provision-fresh-card"  BLOCK "$(b 'just provision-fresh-card /dev/sdz')"
t "redirect to disk"      BLOCK "$(b 'cat core-image.wic > /dev/sdz')"
t "tee to disk"           BLOCK "$(b 'cat core-image.wic | sudo tee /dev/sdz > /dev/null')"
t "wipefs a disk"         BLOCK "$(b 'sudo wipefs -a /dev/sdz')"
t "mkfs a partition"      BLOCK "$(b 'sudo mkfs.vfat /dev/sdz1')"
t "by-id path"            BLOCK "$(b 'sudo dd if=x.wic of=/dev/disk/by-id/fixture-fixed-disk bs=4M')"
# The same prefix salad, on a writer that has no `of=` for the rule to fall back
# on -- so these measure the command-position anchor and nothing else.
t "sudo VAR= wipefs"      BLOCK "$(b 'sudo LC_ALL=C wipefs -a /dev/sdz')"
t "env VAR= sudo wipefs"  BLOCK "$(b 'env KIOSK=1 sudo wipefs -a /dev/sdz')"
t "sudo -u root bmaptool" BLOCK "$(b 'sudo -u root bmaptool copy core-image.wic.bz2 /dev/sdz')"

echo "--- must BLOCK: rules 3-7 ---"
t "ssh + suppress"        BLOCK "$(b "ssh root@$BENCH uptime 2>/dev/null")"
t "array form + suppress" BLOCK "$(b "ssh=(ssh -o BatchMode=yes root@$BENCH)
timeout 60 \"\${ssh[@]}\" uptime 2>/dev/null")"
t "disable sshd"          BLOCK "$(b "ssh root@$BENCH systemctl disable sshd")"
t "mask wpa_supplicant"   BLOCK "$(b 'systemctl mask wpa_supplicant.service')"
t "stop networkd"         BLOCK "$(b 'systemctl stop systemd-networkd')"
t "write cmdline.txt"     BLOCK "$(b 'echo x > /boot/cmdline.txt')"
t "cp INTO /boot"         BLOCK "$(b 'cp /data/uImage /boot/uImage')"
t "mv INTO /boot"         BLOCK "$(b 'mv new.dtb /boot/overlay.dtb')"
t "rm from /boot"         BLOCK "$(b 'rm /boot/cmdline.txt')"
t "tee into /boot"        BLOCK "$(b 'echo x | tee /boot/config.txt')"
t "sed -i on /boot"       BLOCK "$(b 'sed -i s/a/b/ /boot/cmdline.txt')"
t "fw_setenv"             BLOCK "$(b 'fw_setenv bootdelay 0')"
# Every /boot writer needs root on the board, so the sudo-prefixed form is the
# spelling a hand-run actually takes -- and it moved the writer off command
# position, which switched rule 5 off for all of these at once. `doas` and a
# `VAR=1 ` assignment are the same hole spelled differently.
t "sudo sed -i on /boot"  BLOCK "$(b 'sudo sed -i s/a/b/ /boot/cmdline.txt')"
t "sudo rm from /boot"    BLOCK "$(b 'sudo rm /boot/cmdline.txt')"
t "sudo truncate /boot"   BLOCK "$(b 'sudo truncate -s0 /boot/config.txt')"
t "sudo dd into /boot"    BLOCK "$(b 'sudo dd if=k.img of=/boot/uImage')"
t "sudo cp INTO /boot"    BLOCK "$(b 'sudo cp /data/uImage /boot/uImage')"
t "sudo mv INTO /boot"    BLOCK "$(b 'sudo mv new.dtb /boot/overlay.dtb')"
t "pipe to sudo tee"      BLOCK "$(b 'echo x | sudo tee /boot/config.txt')"
t "sudo fw_setenv"        BLOCK "$(b 'sudo fw_setenv bootdelay 0')"
t "doas sed on /boot"     BLOCK "$(b 'doas sed -i s/a/b/ /boot/cmdline.txt')"
t "assignment + sed"      BLOCK "$(b 'FOO=1 sed -i s/a/b/ /boot/cmdline.txt')"
# Assignment AFTER the privilege word, which is how `env` is spelled and how a
# locale-pinned sudo run is spelled. Ordering the prefix as assignments-then-
# wrappers left every one of these allowed.
t "env VAR= rm /boot"     BLOCK "$(b 'env LC_ALL=C rm /boot/cmdline.txt')"
t "sudo VAR= sed /boot"   BLOCK "$(b 'sudo LC_ALL=C sed -i s/a/b/ /boot/cmdline.txt')"
t "env VAR= sudo rm"      BLOCK "$(b 'env KIOSK=1 sudo rm /boot/cmdline.txt')"
t "sudo -u root rm /boot" BLOCK "$(b 'sudo -u root rm /boot/cmdline.txt')"
t "nice -n 5 tee /boot"   BLOCK "$(b 'nice -n 5 tee /boot/config.txt')"
t "timeout 60 rm /boot"   BLOCK "$(b 'timeout 60 rm /boot/cmdline.txt')"
t "exit-echo after pipe"  BLOCK "$(b 'just verify | tail -50 ; echo "exit=$?"')"
t "kiosk-ssh + suppress"  BLOCK "$(b "tools/kiosk-ssh.sh root@$BENCH uptime 2>/dev/null")"
t "pkill bare -f"         BLOCK "$(b "$KILLPAT -f doseresp.sh")"
t "pgrep after &&"        BLOCK "$(b "cd /tmp && $GREPPAT -f nettest")"
t "pkill combined -af"    BLOCK "$(b "$KILLPAT -af foo")"
# Killing another user's process needs root, so this is the ordinary spelling
# too -- and the harness's own command line is still what the -f matches.
t "sudo pkill bare -f"    BLOCK "$(b "sudo $KILLPAT -f doseresp.sh")"
t "env pgrep bare -f"     BLOCK "$(b "env $GREPPAT -f nettest")"
t "env VAR= pkill -f"     BLOCK "$(b "env LC_ALL=C $KILLPAT -f doseresp.sh")"
t "sudo -u root pkill -f" BLOCK "$(b "sudo -u root $KILLPAT -f doseresp.sh")"
# The other two rules the heredoc strip disarmed. A shell reads these bodies.
t "lifeline in heredoc"   BLOCK "$(b "$(printf "ssh root@%s bash <<'EOF'\nsystemctl disable sshd\nEOF" "$BENCH")")"
t "/boot in heredoc"      BLOCK "$(b "$(printf "bash <<'EOF'\necho x > /boot/cmdline.txt\nEOF")")"

echo "--- must ALLOW: the legal variants ---"
t "bench OTA by address"  ALLOW "$(b "just kiosk-ota host=root@$BENCH")"
t "bench OTA by name"     ALLOW "$(b 'just kiosk-ota host=root@fixture-bench')"
# THE regression case. The prod hostname is also the Yocto MACHINE name, so it
# appears three times inside a legitimate bundle path aimed at the BENCH board.
# Splitting the command on '/' would make each of those a bare token equal to
# the prod hostname and false-block every explicit-path delivery.
t "MACHINE name in paths" ALLOW "$(b "just kiosk-send-direct bundle=build/tmp-$PHOST/deploy/images/$PHOST/update-bundle-$PHOST.raucb host=root@$BENCH")"
t "MACHINE= assignment"   ALLOW "$(b "MACHINE=$PHOST just build")"
t "MACHINE name, ls path" ALLOW "$(b "ls build/tmp-$PHOST/deploy/images/$PHOST/")"
echo "--- must ALLOW: observing PROD is not destroying it ---"
t "prod soak-summary"     ALLOW "$(b "just soak-summary root@$PROD 24")"
t "prod screenshot"       ALLOW "$(b "just screenshot root@$PROD")"
t "prod backup"           ALLOW "$(b "just kiosk-backup host=root@$PROD")"
t "prod rauc-status"      ALLOW "$(b "just rauc-status root@$PROD")"
t "prod preflight"        ALLOW "$(b "just kiosk-preflight host=root@$PROD")"
# Reading the soak log for reboot events is the primary legitimate activity on
# prod, and the block message promises observation is allowed. An unanchored
# `reboot` alternative blocked exactly this.
t "prod grep for reboot"  ALLOW "$(b "ssh root@$PROD 'grep -c reboot /var/log/messages'")"
t "prod soak | grep"      ALLOW "$(b "just soak-summary root@$PROD 24 | grep reboot")"
# The other direction of the sudo-prefix fix: skipping the prefix must land on
# the REAL verb, not on the argument of a grep one word further along.
t "prod sudo grep reboot" ALLOW "$(b "ssh root@$PROD 'sudo grep -c reboot /var/log/messages'")"
# The other direction of the prefix rework. A locale-pinned read of the soak log
# is an OBSERVATION, and so is one run under `sudo -n`: accepting an option's
# separate value mid-prefix would swallow `grep` as the value of `-n` and anchor
# on the word after `-c`, which is the literal `reboot` being searched FOR.
t "prod env grep reboot"  ALLOW "$(b "ssh root@$PROD 'env LC_ALL=C grep -c reboot /var/log/messages'")"
t "prod local env grep"   ALLOW "$(b "ssh root@$PROD uptime && env LC_ALL=C grep -c reboot /tmp/soak.log")"
t "prod sudo -n grep"     ALLOW "$(b "ssh root@$PROD uptime && sudo -n grep -c reboot /tmp/soak.log")"
t "prod ssh sudo -u grep" ALLOW "$(b "ssh root@$PROD sudo -u root grep -c reboot /var/log/messages")"
# Rule 1 is scoped to PROD, not to the verb: the bench board is the reboot target.
t "bench systemctl halt"  ALLOW "$(b "ssh root@$BENCH systemctl halt")"
t "bench env VAR= OTA"    ALLOW "$(b "env LC_ALL=C just kiosk-ota host=root@$BENCH")"
t "bench sudo -u reboot"  ALLOW "$(b "ssh root@$BENCH sudo -u root reboot")"
echo "--- must ALLOW: rule 2's legal targets ---"
t "flash to card reader"  ALLOW "$(b 'just flash /dev/sdy')"
t "dd to removable part"  ALLOW "$(b 'dd if=x.img of=/dev/sdy1')"
t "flash to mmcblk"       ALLOW "$(b 'just flash /dev/mmcblk0')"
t "README placeholder"    ALLOW "$(b 'just flash /dev/sdX')"
t "sudo bmaptool to card" ALLOW "$(b 'sudo bmaptool copy core-image.wic.bz2 /dev/sdy')"
t "fresh card to reader"  ALLOW "$(b 'just provision-fresh-card /dev/sdy')"
t "lsblk names a disk"    ALLOW "$(b 'lsblk -o NAME,SIZE,RM,MODEL /dev/sdz')"
t "2>/dev/null, no disk"  ALLOW "$(b 'ls /nonexistent 2>/dev/null')"
echo "--- must ALLOW: rules 3-7 ---"
t "ssh, no suppress"      ALLOW "$(b "ssh root@$BENCH uptime")"
t "UserKnownHosts"        ALLOW "$(b "ssh -o UserKnownHostsFile=/dev/null root@$BENCH uptime")"
t "local suppress only"   ALLOW "$(b 'grep foo bar 2>/dev/null')"
t "local supp + ssh else" ALLOW "$(b "tail -n 5 /tmp/out 2>/dev/null
ssh=(ssh -o BatchMode=yes root@$BENCH)
timeout 60 \"\${ssh[@]}\" uptime")"
t "mask logind"           ALLOW "$(b 'systemctl mask systemd-logind.service')"
t "mask resolved"         ALLOW "$(b 'systemctl mask systemd-resolved.service')"
t "mask zram"             ALLOW "$(b 'systemctl mask zram.service')"
t "sshd is-active"        ALLOW "$(b 'systemctl is-active sshd')"
t "read /boot"            ALLOW "$(b 'cat /boot/cmdline.txt')"
t "ls /boot"              ALLOW "$(b 'ls -l /boot/')"
t "cp FROM /boot"         ALLOW "$(b 'cp /boot/uImage /data/uImage-known-good')"
t "cat FROM /boot"        ALLOW "$(b 'cat /boot/uImage > /data/uImage-A')"
# "a-r-m" contains "rm": arch/arm/boot/dts/ once blocked a read-only ls of the
# kernel source tree. /boot/ only counts when it STARTS a path.
t "arm/boot in a path"    ALLOW "$(b 'ls build/work-shared/kernel-source/arch/arm/boot/dts/overlays/')"
# Tolerating the prefix must not turn READS of /boot into writes.
t "sudo read /boot"       ALLOW "$(b 'sudo cat /boot/cmdline.txt')"
t "sudo ls /boot"         ALLOW "$(b 'sudo ls -l /boot/')"
t "sudo cp FROM /boot"    ALLOW "$(b 'sudo cp /boot/uImage /data/uImage-known-good')"
# Nor may the repeating prefix group: reads of /boot stay reads however many
# wrapper words, assignments and options sit in front of them.
t "sudo cat /boot"        ALLOW "$(b 'sudo cat /boot/config.txt')"
t "env VAR= cat /boot"    ALLOW "$(b 'env LC_ALL=C cat /boot/config.txt')"
t "sudo -u root ls /boot" ALLOW "$(b 'sudo -u root ls -l /boot/')"
t "sudo -u root sysctl"   ALLOW "$(b 'sudo -u root systemctl is-active sshd')"
t "slot rootfs boot"      ALLOW "$(b 'cd /mnt/root/boot && cat /data/uImage-arm1 > uImage')"
t "rauc mark-good"        ALLOW "$(b 'rauc status mark-good booted')"
t "fw_setenv mentioned"   ALLOW "$(b 'echo "re-arm via rauc, not fw_setenv"')"
t "pipe, no exit echo"    ALLOW "$(b 'just verify | tail -50')"
t "heredoc body mentions" ALLOW "$(b "$(printf 'git commit -F - <<EOF\nnote: fw_setenv is refused by the guard\nEOF')")"
# The other direction of the same fix: a body no shell reads is still data. The
# opener names a file, not an interpreter, so `.sh` in a path must not arm it.
t "doc heredoc mentions"  ALLOW "$(b "$(printf "cat > docs/note.md <<'EOF'\nrauc install on prod is refused, as is a reboot there\nEOF")")"
t "script heredoc, data"  ALLOW "$(b "$(printf "cat > tools/example.sh <<'EOF'\nfw_setenv bootdelay 0\nEOF")")"
t "known_hosts edit"      ALLOW "$(b "ssh-keygen -R $BENCH 2>/dev/null")"
t "read .ssh, suppressed" ALLOW "$(b "cat ~/.ssh/known_hosts 2>/dev/null | grep -c $BENCH")"
t "pgrep -x -f exact"     ALLOW "$(b "$GREPPAT -x -f '/bin/bash /tmp/x.sh'")"
t "pkill -x by name"      ALLOW "$(b "$KILLPAT -x surf")"
t "pkill in an echo"      ALLOW "$(b "echo 'do not use $KILLPAT -f here'")"
t "edit outside the repo" ALLOW "$(e /home/tjwise/elsewhere/NOTES.md)"

echo "--- escape hatch: authorized /boot write ---"
# The marker is read from the COMMAND TEXT, never the environment: this hook runs
# in its own process BEFORE the command executes, so the inline `VAR=1 cmd` prefix
# the block message tells you to type is just text at that point. Both directions
# are exercised, and the second IS the regression -- an earlier guard read the
# variable, passed a test that exported it, and opened the gate in real use.
#
# The payload is a REDIRECT, not `cp`: the redirect shape carries no
# command-position anchor at all, so this ALLOW can come only from the marker
# check. An anchored writer could be allowed by the anchor instead -- passing
# while measuring nothing.
t "hatch in command text" ALLOW "$(b 'KIOSK_ALLOW_BOOT_WRITE=1 cat /data/cmdline.txt > /boot/cmdline.txt')"
printf '%s' "$(b 'cat /data/cmdline.txt > /boot/cmdline.txt')" > "$T/hatch.json"
KIOSK_ALLOW_BOOT_WRITE=1 "$G" < "$T/hatch.json" > /dev/null 2>&1
rc=$?
if [ $rc -eq 2 ]; then r="ok  "; pass=$((pass+1)); else r="FAIL"; fail=$((fail+1)); fi
printf '%s expected=BLOCK got=%-5s  hatch in ENVIRONMENT only\n' "$r" "$([ $rc -eq 2 ] && echo BLOCK || echo ALLOW)"

echo "--- worktree: the map lives in the PRIMARY tree only ---"
# `local/` is gitignored, so a linked worktree never has one. Resolving the map
# as `$REPO/local/...` therefore found nothing from a worktree and rules 1 and 3
# fail-opened THERE -- which is where device work is done, so the guard was inert
# in its most important location and said nothing about it.
#
# A REAL `git worktree`, not a hand-made directory pair: the resolution runs
# `git rev-parse --git-common-dir`, and a fixture that does not exercise that
# call would pass whether or not the resolution works.
#
# git exports GIT_DIR, GIT_INDEX_FILE and friends to its hooks, and this suite
# runs from .githooks/pre-commit by way of tools/ci-guards.sh. Left in place
# they aim the fixture's `git init` -- and the guard's own `rev-parse` -- back
# at THIS repository, whose primary tree does have a map: the case would then
# pass on a resolution it never exercised. Unset for the fixture and for the
# guard alike.
GITUNSET=(-u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_OBJECT_DIRECTORY
          -u GIT_COMMON_DIR -u GIT_PREFIX -u GIT_NAMESPACE
          -u GIT_ALTERNATE_OBJECT_DIRECTORIES)
if env "${GITUNSET[@]}" git -c init.defaultBranch=main init -q "$T/primary" \
   && env "${GITUNSET[@]}" git -C "$T/primary" -c user.email=guard@test -c user.name=guard \
        commit -q --allow-empty -m init \
   && env "${GITUNSET[@]}" git -C "$T/primary" worktree add -q "$T/wt" -b guard-test-wt; then
    mkdir -p "$T/primary/local"
    cp "$T/device-identity.md" "$T/primary/local/device-identity.md"
    # -u, because the suite exports KIOSK_IDENTITY_FILE globally and this case
    # is about the DEFAULT resolution path -- with the override in place it would
    # pass without the primary tree ever being consulted.
    TENV=("${GITUNSET[@]}" -u KIOSK_IDENTITY_FILE "CLAUDE_PROJECT_DIR=$T/wt")
    t "worktree prod OTA"     BLOCK "$(b "just kiosk-ota host=root@$PROD")"
    t "worktree prod reboot"  BLOCK "$(b "ssh root@$PROD reboot")"
    t "worktree prod suppress" BLOCK "$(b "ssh root@$PROD uptime 2>/dev/null")"
    t "worktree bench OTA"    ALLOW "$(b "just kiosk-ota host=root@$BENCH")"
    TENV=()
else
    fail=$((fail+1))
    printf 'FAIL expected=BLOCK got=-      git worktree fixture could not be built -- worktree resolution NOT measured\n'
fi

echo "--- fail-open: no identity map (a fresh clone, or CI) ---"
# The prod rules cannot fire without the map, and that is deliberate: a guard
# that blocked every device command on a checkout with no local/ would be turned
# off. The map's absence is a documented degradation, not a silent one --
# CLAUDE.md and CONTRIBUTING.md both say the guard is only as good as the map.
KIOSK_IDENTITY_FILE="$T/does-not-exist.md" t "prod op, no map" ALLOW "$(b "just kiosk-ota host=root@$PROD")"
KIOSK_IDENTITY_FILE="$T/does-not-exist.md" t "boot write, no map" BLOCK "$(b 'echo x > /boot/cmdline.txt')"
# Degraded, but not SILENT. Without the notice, "the prod rules found nothing to
# block" and "the prod rules were switched off entirely" are the same output.
printf '%s' "$(b "just kiosk-ota host=root@$PROD")" > "$T/nomap.json"
notice=$(KIOSK_IDENTITY_FILE="$T/does-not-exist.md" "$G" < "$T/nomap.json" 2>&1 > /dev/null)
case "$notice" in
    *INERT*) r="ok  "; pass=$((pass+1)) ;;
    *)       r="FAIL"; fail=$((fail+1)) ;;
esac
printf '%s expected=NOTICE                   no-map fail-open announces itself on stderr\n' "$r"

echo
printf 'pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
