#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/PIA-OC.conf"

SS_CONFIG="${SCRIPT_DIR}/NM-PIA-OC.json"

# Auto-detect active physical default gateway and interface
DEFAULT_ROUTE=$(ip route show default | grep -v "tun" | head -n 1)
GATEWAY=$(echo "$DEFAULT_ROUTE" | awk '{print $3}')
INTERFACE=$(echo "$DEFAULT_ROUTE" | awk '{print $5}')

if [ -n "$GATEWAY" ] && [ -n "$INTERFACE" ]; then
    echo "Detected physical gateway $GATEWAY on interface $INTERFACE"
fi

pkill openvpn 2>/dev/null
pkill sslocal 2>/dev/null
sleep 1
pkill -9 openvpn 2>/dev/null
pkill -9 sslocal 2>/dev/null

ip route del 0.0.0.0/1 2>/dev/null
ip route del 128.0.0.0/1 2>/dev/null

# Un-pin ALL Shadowsocks bridge IPs in NM-PIA-OC.json
if [ -n "$GATEWAY" ] && [ -n "$INTERFACE" ]; then
    for ip in $(jq -r '.servers[].server' "$SS_CONFIG"); do
        ip route del "${ip}/32" via "$GATEWAY" dev "$INTERFACE" 2>/dev/null
    done
fi

resolvectl flush-caches >/dev/null 2>&1
rm -rf /tmp/PIA-OC-active.ovpn
echo "The obfuscated tunnel has been disconnected and network routes restored."

