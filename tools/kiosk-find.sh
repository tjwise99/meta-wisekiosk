#!/usr/bin/env bash
# Find a Raspberry Pi on a LAN whose address you do not know.
#
#   tools/kiosk-find.sh 192.0.2.0/24
#
# What identifies a Pi is its MAC, and a MAC is visible only to a host on the
# same broadcast domain. So the script first decides which L2 view it has, then
# says which one it used -- the three differ in what a miss means:
#
#   windows   this host is WSL and the Windows host is on the target LAN. Sweep
#             and read the neighbour table from the Windows side. WSL2 sits
#             behind NAT, so its own table never holds a LAN peer no matter how
#             many packets cross it; only Windows sees the ARP replies.
#   local     an interface on this host is inside the CIDR. Sweep, then read
#             `ip neigh` (`arp -a` where iproute2 is absent).
#   none      no L2 view of that subnet. The sweep still runs, but it can only
#             report which addresses answer -- it cannot say what they are.
#
# Interop that answers the opening probe and then dies mid-run is demoted to
# `none` as well (exit 3), because that is what it is. Reporting the empty
# result of calls that never ran as "nothing answered ARP" is a claim about the
# LAN, and it was observed false with the board sitting on it.
#
# The sweep pings every address to provoke the ARP exchange. Ping replies are
# not the answer and are discarded: the answer is the neighbour entry each
# exchange leaves behind, which appears even for a host that drops ICMP.
#
# A miss is not absence. A device missing from the router's client list may
# simply hold a static or long-lived lease, a board may carry an OUI newer than
# the list below, and a host asleep during the sweep leaves no entry. The whole
# neighbour table is printed on a miss for exactly that reason.
set -uo pipefail

CIDR=${1:?usage: kiosk-find.sh <cidr>, e.g. 192.0.2.0/24}

# Raspberry Pi Trading / Raspberry Pi Foundation OUIs. Ordered oldest first;
# a board absent from this list is not necessarily not a Pi, so a miss means
# "look at the whole neighbour table", not "it is not there".
OUIS="b8:27:eb dc:a6:32 e4:5f:01 28:cd:c1 2c:cf:67"

# Where the Windows system directory is mounted. WSL's mount point is
# configurable, and pointing this somewhere that does not exist is also how the
# no-interop path gets exercised on a machine that has interop.
WINDIR=${WINDIR_MNT:-/mnt/c/Windows}
PS_EXE="$WINDIR/System32/WindowsPowerShell/v1.0/powershell.exe"
ARP_EXE="$WINDIR/System32/ARP.EXE"

case "$CIDR" in
    *.*.*.*/24) ;;
    *) echo "only a /24 is swept: give <a.b.c.0>/24, not $CIDR" >&2; exit 2 ;;
esac
PREFIX=${CIDR%.*/24}

# --- probes ---------------------------------------------------------------

# Run a PowerShell script read from stdin. -EncodedCommand takes UTF-16LE
# base64, which is the one form that survives the trip through two shells and a
# Windows command line without any quoting rule applying to it.
win_ps() {
    local enc
    enc=$(iconv -f UTF-8 -t UTF-16LE | base64 -w0) || return 1
    timeout 90 "$PS_EXE" -NoProfile -NonInteractive -EncodedCommand "$enc" 2>/dev/null | tr -d '\r'
}

# Connect and drop. bash opens /dev/tcp itself, so this needs nothing installed;
# `timeout` is what bounds a filtered port, which otherwise hangs for the
# kernel's full SYN retry.
tcp_open() {
    timeout 4 bash -c 'exec 3<>/dev/tcp/$1/$2' _ "$1" "$2" 2>/dev/null
}

# The banner is whatever the server volunteers before we say anything. Reading
# it is not a login attempt and leaves no session behind.
tcp_banner() {
    timeout 5 bash -c '
        exec 3<>/dev/tcp/$1/$2 || exit 1
        IFS= read -r -t 3 line <&3
        printf "%s" "$line"
    ' _ "$1" "$2" 2>/dev/null | tr -d '\r'
}

# Same probe from the Windows side, for a port WSL's NAT cannot reach.
win_tcp_open() {
    local r
    r=$(win_ps <<PSEOF
\$c = New-Object System.Net.Sockets.TcpClient
if (\$c.ConnectAsync('$1', $2).Wait(4000) -and \$c.Connected) { Write-Output 'open' }
\$c.Close()
PSEOF
    )
    [ "$r" = "open" ]
}

# --- pick the L2 view -----------------------------------------------------

view=none
if [ -x "$PS_EXE" ] && [ -x "$ARP_EXE" ]; then
    # Interop can be installed and still not answer -- the WSL vsock relay drops
    # out and every .exe then fails identically to one not being there.
    # Presence of the file proves nothing; a table coming back does. The outage
    # is usually seconds, and demoting a run to reachability-only over one
    # dropped call throws away the only view that can name a board, so it is
    # retried before being believed.
    for attempt in 1 2 3; do
        probe=$(timeout 30 "$ARP_EXE" -a 2>/dev/null | tr -d '\r')
        if printf '%s' "$probe" | grep -q 'Interface:'; then
            view=windows
            break
        fi
        [ "$attempt" -lt 3 ] && sleep 5
    done
    [ "$view" = windows ] || \
        echo "warning: Windows interop is present but not answering after 3 tries -- falling back" >&2
fi
if [ "$view" = none ]; then
    # A /24 view exists iff some interface address shares the three octets.
    if ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 \
        | grep -qx "$PREFIX\.[0-9]*"; then
        view=local
    fi
fi

# Both start "yes" and only the windows path can clear them: the up-front probe
# proves interop answered once, not that it will answer for the two calls that
# carry the result.
sweep_answered=yes
table_answered=yes

echo "sweeping $PREFIX.1-254 (L2 view: $view) ..."

# --- sweep ----------------------------------------------------------------

if [ "$view" = windows ]; then
    # One asynchronous ping per address, all in flight at once: a serial sweep
    # of 254 addresses at a one-second timeout is four minutes, and this is two.
    replies=$(win_ps <<PSEOF
\$t = foreach (\$i in 1..254) {
    (New-Object System.Net.NetworkInformation.Ping).SendPingAsync('$PREFIX.' + \$i, 1000)
}
[System.Threading.Tasks.Task]::WaitAll(\$t)
Write-Output (@(\$t | Where-Object { \$_.Result.Status -eq 'Success' }).Count)
PSEOF
    )
    case "$replies" in
        ''|*[!0-9]*)
            sweep_answered=no
            echo "warning: the Windows sweep did not report a count -- interop may have dropped mid-run" >&2 ;;
        *) echo "  $replies of 254 answered" ;;
    esac
else
    # Every ping in flight at once, and each one that answers appends its own
    # address: 254 sequential probes at a one-second timeout is four minutes,
    # which is long enough that the sweep reads as a hang.
    RESPONDERS=$(mktemp)
    trap 'rm -f "$RESPONDERS"' EXIT
    for i in $(seq 1 254); do
        ( ping -c1 -W1 "$PREFIX.$i" > /dev/null 2>&1 && echo "$PREFIX.$i" >> "$RESPONDERS" ) &
    done
    wait
    echo "  $(wc -l < "$RESPONDERS") of 254 answered"
fi

# --- read the neighbour table --------------------------------------------

# Normalised to "<ip> <mac>", MACs lower-case and colon-separated whatever the
# source spelled them. Matching an OUI against the whole line instead would let
# an interface header or a hostname satisfy the pattern.
case "$view" in
    windows)
        # A table that arrived carries the interface header, whether or not it
        # holds a single entry. Nothing at all means the call failed, and an
        # empty table and a failed call are the same string once awk has run --
        # so the distinction is made here, on the raw output, while it exists.
        raw=$(timeout 30 "$ARP_EXE" -a 2>/dev/null | tr -d '\r')
        case "$raw" in *Interface:*) ;; *) table_answered=no ;; esac
        table=$(printf '%s\n' "$raw" \
            | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 ~ /^[0-9a-fA-F-]{17}$/ {print $1, $2}')
        source_desc="Windows ARP cache ($ARP_EXE -a)"
        ;;
    local)
        if command -v ip > /dev/null; then
            table=$(ip neigh show 2>/dev/null \
                | awk '{for (i=1;i<NF;i++) if ($i=="lladdr") print $1, $(i+1)}')
            source_desc="ip neigh"
        elif command -v arp > /dev/null; then
            table=$(arp -an 2>/dev/null \
                | awk '{ip=$2; gsub(/[()]/,"",ip); for (i=1;i<NF;i++) if ($i=="at") print ip, $(i+1)}')
            source_desc="arp -an"
        else
            echo "an interface is inside $CIDR but neither ip nor arp is installed" >&2
            exit 2
        fi
        ;;
    none)
        table=""
        source_desc="none"
        ;;
esac

table=$(printf '%s\n' "$table" | tr 'A-F' 'a-f' | tr '-' ':' \
    | grep -E "^$PREFIX\.[0-9]+ ([0-9a-f]{2}:){5}[0-9a-f]{2}$" \
    | grep -v ' ff:ff:ff:ff:ff:ff$' | sort -t. -k4 -n -u)

# --- report ---------------------------------------------------------------

# Interop can pass the up-front probe and then die during the run, and the two
# calls that carry the whole result are the sweep and the table read. When the
# table read returned nothing, or the sweep reported no count AND not one
# in-range neighbour came back, "nothing answered ARP" would be an affirmative
# claim about the LAN drawn from calls that never ran. A dead relay explains
# that shape far better than an empty subnet, and it is the shape a live run
# produced with the board sitting on the LAN the whole time. So it degrades to
# the same "no L2 view" verdict as having no interop at all.
if [ "$view" = windows ] && { [ "$table_answered" = no ] || \
    { [ "$sweep_answered" = no ] && [ -z "$table" ]; }; }; then
    if [ "$table_answered" = no ]; then
        why="the neighbour-table read returned nothing at all -- not an empty table, no table"
    else
        why="the sweep reported no count and the neighbour table came back with nothing in range"
    fi
    echo
    echo "the Windows interop this run depends on answered the opening probe and"
    echo "then stopped: $why."
    echo
    echo "This host is WSL, so those calls ARE the L2 view of $CIDR -- WSL2 sits"
    echo "behind NAT and its own neighbour table never holds a LAN peer. Nothing"
    echo "was measured. This is NOT evidence that $CIDR is empty, and a device"
    echo "sitting there right now would produce exactly this output."
    echo
    echo "the outage is usually seconds -- run it again, or run it from a host"
    echo "on that LAN."
    exit 3
fi

if [ "$view" = none ]; then
    echo
    echo "this host has no L2 view of $CIDR: no interface is inside it and no"
    echo "working Windows interop, so nothing here ever sees a MAC from that"
    echo "subnet. Reachability is all that can be measured, and it can only say"
    echo "which addresses answered -- not which of them is a Pi, and not that a"
    echo "silent address is unused."
    echo
    echo "addresses in $CIDR that answered:"
    if [ -s "$RESPONDERS" ]; then
        sort -t. -k4 -n -u "$RESPONDERS" | while read -r ip; do
            printf '  %-15s' "$ip"
            if tcp_open "$ip" 22; then
                printf ' tcp/22 open  %s' "$(tcp_banner "$ip" 22)"
            else
                printf ' tcp/22 no answer'
            fi
            printf '\n'
        done
    else
        echo "  (none -- and a host that drops ICMP answers nothing here either)"
    fi
    echo
    echo "run this from a host on that LAN to identify anything."
    exit 3
fi

pattern=$(printf '%s' "$OUIS" | tr ' ' '\n' | sed 's/^/ /' | paste -sd'|' -)
hits=$(printf '%s\n' "$table" | grep -E "$pattern") || true

if [ -z "$hits" ]; then
    echo
    echo "no Raspberry Pi OUI in $source_desc for $CIDR"
    if [ -z "$table" ]; then
        echo "  $source_desc holds no entry in that range at all -- nothing answered ARP"
    else
        echo "the whole table follows -- a newer board may carry an OUI this list predates"
        printf '%s\n' "$table" | sed 's/^/  /'
    fi
    exit 1
fi

echo
echo "Raspberry Pi OUIs in $source_desc:"
printf '%s\n' "$hits" | while read -r ip mac; do
    printf '  %-15s %s' "$ip" "$mac"
    if tcp_open "$ip" 22; then
        printf '  tcp/22 open  %s' "$(tcp_banner "$ip" 22)"
    elif [ "$view" = windows ] && win_tcp_open "$ip" 22; then
        # Reachable from Windows but not from here: WSL's NAT is in the way, not
        # the device. Saying "closed" would blame the wrong host.
        printf '  tcp/22 open from Windows, not routable from WSL'
    else
        printf '  tcp/22 no answer'
    fi
    printf '\n'
done
echo
echo "an OUI says a Raspberry Pi, not which one -- confirm by logging in."
