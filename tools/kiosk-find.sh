#!/usr/bin/env bash
# Find a Raspberry Pi on a LAN whose address you do not know.
#
#   tools/kiosk-find.sh 192.0.2.0/24
#
# Sweeps the /24 with one-packet pings to populate the local ARP cache, then
# reads that cache back for Raspberry Pi OUIs. The pings are backgrounded and
# their results discarded on purpose -- the answer is the ARP entry each one
# leaves behind, not whether it replied.
#
# A device missing from the router's client list is not necessarily offline:
# those lists are built from DHCP leases, so a static or long-leased host can be
# invisible there and perfectly reachable here.
set -uo pipefail

CIDR=${1:?usage: kiosk-find.sh <cidr>, e.g. 192.0.2.0/24}

# Raspberry Pi Trading / Raspberry Pi Foundation OUIs. Ordered oldest first;
# a board absent from this list is not necessarily not a Pi, so a miss means
# "look at the whole ARP table", not "it is not there".
OUIS="b8:27:eb dc:a6:32 e4:5f:01 28:cd:c1 2c:cf:67"

case "$CIDR" in
    *.*.*.*/24) ;;
    *) echo "only a /24 is swept: give <a.b.c.0>/24, not $CIDR" >&2; exit 2 ;;
esac
PREFIX=${CIDR%.*/24}

command -v arp > /dev/null || { echo "arp not installed on this host" >&2; exit 2; }

echo "sweeping $PREFIX.1-254 ..."
for i in $(seq 1 254); do
    ping -c1 -W1 "$PREFIX.$i" > /dev/null 2>&1 &
done
wait

# `arp -a` prints MACs colon-separated on Linux and dash-separated on some
# other hosts; matching either keeps this working off a Windows-ish shell too.
pattern=$(printf '%s' "$OUIS" | tr ' ' '\n' | sed 's/:/[:-]/g' | paste -sd'|' -)
hits=$(arp -a | grep -Ei "$pattern") || true

if [ -z "$hits" ]; then
    echo "no Raspberry Pi OUI in the ARP cache for $PREFIX.0/24"
    echo "the full cache follows -- a newer board may carry an OUI this list predates"
    arp -a
    exit 1
fi
printf '%s\n' "$hits"
