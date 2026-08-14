#!/usr/bin/env bash
# What the kiosk's browser is doing, inferred from TCP state alone.
#
#   tools/kiosk-tcp-state.sh <kiosk-address> [port]
#
# Run this ON THE MACHINE SERVING THE PAGE. netstat only sees sockets local to
# the host it runs on, so pointing it at the kiosk from a third machine reports
# nothing and reads exactly like a kiosk that is not connecting.
#
# This is the read of last resort: the kiosk's correct display is a black
# background, so "working", "browser crashed", "JavaScript threw" and "X never
# started" are indistinguishable from the room. Socket state is definite.
#
#   no connections                        browser not running, or not attempting
#   1, ending FIN_WAIT_2 / TIME_WAIT      fetched the HTML only -- scripts never
#                                         ran, so a parse failure or an ignored
#                                         module
#   3, then closed                        fetched HTML and JS, but the scripts
#                                         did not execute -- CSP, or an early
#                                         throw
#   1 ESTABLISHED, sustained              rendering, one multiplexed socket.
#                                         The healthy state
#
# "1" appears twice with opposite meanings: a single connection that CLOSES is
# failure, one that STAYS established is success. State and persistence
# discriminate, not the count -- and when the count is what you are reading, ask
# what the right count is. A row reading "many established, sustained" as a
# health signal once hid the largest bring-up cost on this device for a whole
# session; it was one connection per module against a six-per-origin limit.
set -uo pipefail

ADDR=${1:?usage: kiosk-tcp-state.sh <kiosk-address> [port]}
PORT=${2:-8080}

command -v netstat > /dev/null || { echo "netstat not installed on this host" >&2; exit 2; }

# The state is the last field of a netstat TCP row. Counting local addresses
# instead answers a different question and produces a table that never matches
# the one above.
out=$(netstat -an | grep "^tcp" | grep "$ADDR" | grep ":$PORT" | awk '{print $NF}' | sort | uniq -c)

echo "$ADDR:$PORT  $(date '+%H:%M:%S')"
if [ -z "$out" ]; then
    echo "  no connections"
else
    printf '%s\n' "$out" | sed 's/^/  /'
fi

# Deliberately no exit-code verdict: every line above is evidence for a human,
# and a script that decided "healthy" from one sample would be asserting
# persistence it never observed. Run it twice, seconds apart.
