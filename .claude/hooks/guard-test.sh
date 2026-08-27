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

export KIOSK_IDENTITY_FILE="$T/device-identity.md"
export KIOSK_SYSFS_ROOT="$T/sys"

pass=0; fail=0
t() { # $1=label $2=expect $3=payload
  out=$(printf '%s' "$3" | "$G" 2>&1); rc=$?
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

echo "--- must BLOCK: rule 1, destructive op aimed at PROD ---"
t "prod OTA by address"   BLOCK "$(b "just kiosk-ota host=root@$PROD")"
t "prod reboot by name"   BLOCK "$(b "just kiosk-reboot host=root@$PHOST")"
t "prod rauc install"     BLOCK "$(b "ssh root@$PROD rauc install /data/update.raucb")"
t "prod bare reboot"      BLOCK "$(b "ssh root@$PROD reboot")"
t "prod reprovision"      BLOCK "$(b "tools/provision.sh device root@$PROD")"
t "prod scp-style target" BLOCK "$(b "just kiosk-send-direct host=root@$PROD:/data")"

echo "--- must BLOCK: rule 2, image write to a non-removable device ---"
t "flash to fixed disk"   BLOCK "$(b 'just flash /dev/sdz')"
t "dd to nvme"            BLOCK "$(b 'dd if=core-image.wic of=/dev/nvme0n1 bs=4M')"
t "dd to virtio disk"     BLOCK "$(b 'dd if=core-image.wic of=/dev/vda bs=4M')"
t "bmaptool to fixed"     BLOCK "$(b 'bmaptool copy core-image.wic.bz2 /dev/sdz')"
t "dd to fixed partition" BLOCK "$(b 'dd if=x.img of=/dev/sdz1')"

echo "--- must BLOCK: rules 3-6 ---"
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
t "exit-echo after pipe"  BLOCK "$(b 'just verify | tail -50 ; echo "exit=$?"')"

echo "--- must ALLOW: the legal variants ---"
t "bench OTA by address"  ALLOW "$(b "just kiosk-ota host=root@$BENCH")"
t "bench OTA by name"     ALLOW "$(b 'just kiosk-ota host=root@fixture-bench')"
# THE regression case. The prod hostname is also the Yocto MACHINE name, so it
# appears three times inside a legitimate bundle path aimed at the BENCH board.
# Splitting the command on '/' would make each of those a bare token equal to
# the prod hostname and false-block every explicit-path delivery.
t "MACHINE name in paths" ALLOW "$(b "just kiosk-send-direct bundle=build/tmp-$PHOST/deploy/images/$PHOST/update-bundle-$PHOST.raucb host=root@$BENCH")"
t "MACHINE= assignment"   ALLOW "$(b "MACHINE=$PHOST just build")"
echo "--- must ALLOW: observing PROD is not destroying it ---"
t "prod soak-summary"     ALLOW "$(b "just soak-summary root@$PROD 24")"
t "prod screenshot"       ALLOW "$(b "just screenshot root@$PROD")"
t "prod backup"           ALLOW "$(b "just kiosk-backup host=root@$PROD")"
t "prod rauc-status"      ALLOW "$(b "just rauc-status root@$PROD")"
t "prod preflight"        ALLOW "$(b "just kiosk-preflight host=root@$PROD")"
echo "--- must ALLOW: rule 2's legal targets ---"
t "flash to card reader"  ALLOW "$(b 'just flash /dev/sdy')"
t "dd to removable part"  ALLOW "$(b 'dd if=x.img of=/dev/sdy1')"
t "flash to mmcblk"       ALLOW "$(b 'just flash /dev/mmcblk0')"
t "README placeholder"    ALLOW "$(b 'just flash /dev/sdX')"
echo "--- must ALLOW: rules 3-6 ---"
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
t "slot rootfs boot"      ALLOW "$(b 'cd /mnt/root/boot && cat /data/uImage-arm1 > uImage')"
t "rauc mark-good"        ALLOW "$(b 'rauc status mark-good booted')"
t "fw_setenv mentioned"   ALLOW "$(b 'echo "re-arm via rauc, not fw_setenv"')"
t "pipe, no exit echo"    ALLOW "$(b 'just verify | tail -50')"
t "heredoc body mentions" ALLOW "$(b "$(printf 'git commit -F - <<EOF\nnote: fw_setenv is refused by the guard\nEOF')")"
t "edit outside the repo" ALLOW "$(e /home/tjwise/elsewhere/NOTES.md)"

echo "--- escape hatch: authorized /boot write ---"
# The marker is read from the COMMAND TEXT, never the environment: this hook runs
# in its own process BEFORE the command executes, so the inline `VAR=1 cmd` prefix
# the block message tells you to type is just text at that point. Both directions
# are exercised, and the second IS the regression -- an earlier guard read the
# variable, passed a test that exported it, and opened the gate in real use.
#
# The payload is a REDIRECT, not `cp`. A `VAR=1 ` prefix moves `cp` off command
# position, so a `cp` payload would be allowed even with the marker check deleted
# -- it would pass while measuring nothing. The redirect rule has no
# command-position anchor, so the ALLOW can only come from the marker.
t "hatch in command text" ALLOW "$(b 'KIOSK_ALLOW_BOOT_WRITE=1 cat /data/cmdline.txt > /boot/cmdline.txt')"
printf '%s' "$(b 'cat /data/cmdline.txt > /boot/cmdline.txt')" > "$T/hatch.json"
KIOSK_ALLOW_BOOT_WRITE=1 "$G" < "$T/hatch.json" > /dev/null 2>&1
rc=$?
if [ $rc -eq 2 ]; then r="ok  "; pass=$((pass+1)); else r="FAIL"; fail=$((fail+1)); fi
printf '%s expected=BLOCK got=%-5s  hatch in ENVIRONMENT only\n' "$r" "$([ $rc -eq 2 ] && echo BLOCK || echo ALLOW)"

echo "--- fail-open: no identity map (a fresh clone, or CI) ---"
# The prod rules cannot fire without the map, and that is deliberate: a guard
# that blocked every device command on a checkout with no local/ would be turned
# off. The map's absence is a documented degradation, not a silent one --
# CLAUDE.md and CONTRIBUTING.md both say the guard is only as good as the map.
KIOSK_IDENTITY_FILE="$T/does-not-exist.md" t "prod op, no map" ALLOW "$(b "just kiosk-ota host=root@$PROD")"
KIOSK_IDENTITY_FILE="$T/does-not-exist.md" t "boot write, no map" BLOCK "$(b 'echo x > /boot/cmdline.txt')"

echo
printf 'pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
