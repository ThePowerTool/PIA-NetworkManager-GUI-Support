#!/bin/bash
# Displays local & live status of the PIA-OC obfuscated tunnel and verifies
# whether the current public IP/location matches the last recorded session log.

red='\033[0;31m'
grn='\033[0;32m'
nc='\033[0m' # No Color

HISTORY_LOG="/var/log/pia-cipher-history.log"
TRACE_TMP=$(mktemp /tmp/pia-oc-trace.XXXXXX)
trap 'rm -f "$TRACE_TMP"' EXIT

# Kick off external trace lookup in the background immediately so network latency   
# overlaps with local daemon, interface, route, and DNS checks below.
curl -fsS --max-time 6 https://1.1.1.1/cdn-cgi/trace > "$TRACE_TMP" 2>/dev/null &
CURL_PID=$!

echo "======================================================================"
echo " PIA-OC TUNNEL STATUS"
echo "======================================================================"

# 1. Check background daemons
SS_PID=$(pgrep -x sslocal | head -n 1)
OVPN_PID=$(pgrep -x openvpn | head -n 1)

if [ -n "$SS_PID" ]; then
    SS_CMD=$(ps -p "$SS_PID" -o args= | grep -oE '\-s [^ ]+' | awk '{print $2}')
    echo "  Shadowsocks Proxy : ACTIVE (PID $SS_PID -> Bridge ${SS_CMD:-unknown})"
else
    echo "  Shadowsocks Proxy : STOPPED"
fi

if [ -n "$OVPN_PID" ]; then
    echo "  OpenVPN Daemon    : ACTIVE (PID $OVPN_PID)"
else
    echo "  OpenVPN Daemon    : STOPPED"
fi

# 2. Check tun0 interface & split-tunnel routing
if ip link show dev tun0 >/dev/null 2>&1; then
    TUN_IP=$(ip -4 -o addr show dev tun0 | awk '{print $4}')
    echo "  Virtual Interface : tun0 UP (${TUN_IP:-no IPv4})"
else
    echo "  Virtual Interface : tun0 DOWN"
fi

if ip route show | grep -q "^0\.0\.0\.0/1 dev tun0" && ip route show | grep -q "^128\.0\.0\.0/1 dev tun0"; then
    echo "  Split-Tunnel Route: ACTIVE (0.0.0.0/1 & 128.0.0.0/1 -> tun0)"
else
    echo "  Split-Tunnel Route: INACTIVE (traffic using standard default gateway)"
fi

# 3. Check DNS lock via systemd-resolved
if ip link show dev tun0 >/dev/null 2>&1; then
    DNS_INFO=$(resolvectl status tun0 2>/dev/null | awk -F': ' '/Current DNS Server|DNS Domain/ {print $2}' | paste -sd ' ' -)
    echo "  DNS Leak Lock     : ${DNS_INFO:-unconfigured}"
fi

# 4. Read Last Session Log & Wait for Background Curl Trace to Complete
LAST_LOG=""
LOG_IP=""
LOG_LOC=""
if [ -f "$HISTORY_LOG" ] && [ -s "$HISTORY_LOG" ]; then
    LAST_LOG=$(tail -n 1 "$HISTORY_LOG")
    LOG_IP=$(echo "$LAST_LOG" | sed -nE 's/.*PublicIP: ([^ ]+) \(([A-Z]+)\).*/\1/p')
    LOG_LOC=$(echo "$LAST_LOG" | sed -nE 's/.*PublicIP: ([^ ]+) \(([A-Z]+)\).*/\2/p')
fi

# Barrier: ensure background curl process has exited and flushed its output before reading
wait "$CURL_PID" 2>/dev/null
TRACE_OUT=$(cat "$TRACE_TMP")

if [ -n "$TRACE_OUT" ]; then
    CUR_IP=$(echo "$TRACE_OUT" | awk -F= '/^ip=/ {print $2}')
    CUR_LOC=$(echo "$TRACE_OUT" | awk -F= '/^loc=/ {print $2}')

    if [ -n "$LOG_IP" ] && [ "$CUR_IP" = "$LOG_IP" ] && [ "$CUR_LOC" = "$LOG_LOC" ]; then
        MATCH_FLAG="${grn}MATCH${nc} (Last Session Log)"
    elif [ -z "$LOG_IP" ]; then
        MATCH_FLAG="NO_LOG (no prior session entry to compare)"
    else
        MATCH_FLAG="${red}MISMATCH${nc} (expected ${LOG_IP} (${LOG_LOC}))"
    fi

    echo -e "  Live Exit Check   : ${CUR_IP:-unknown} | loc: ${CUR_LOC:-unknown} | Flag: $MATCH_FLAG"
else
    echo -e "  Live Exit Check   : ${red}FAILED${nc} (curl timed out or unreachable)"
fi

# 5. Display Last Session Log at the end
echo "----------------------------------------------------------------------"
if [ -n "$LAST_LOG" ]; then
    echo "  Last Session Log  :"
    echo "    $LAST_LOG"
else
    echo "  Last Session Log  : (none recorded yet)"
fi
echo "======================================================================"

