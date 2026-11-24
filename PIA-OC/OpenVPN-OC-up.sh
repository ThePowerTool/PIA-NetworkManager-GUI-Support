#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/PIA-OC.conf"
set -u

V6_DATA="${SCRIPT_DIR}/pia-v6-servers.dat"
PROXY_BINARY="/root/.cargo/bin/sslocal"
SS_CONFIG="${SCRIPT_DIR}/NM-PIA-OC.json"
TEMPLATE="${SCRIPT_DIR}/PIA-OC-Template.ovpn"
RUNTIME_PROFILE="/tmp/PIA-OC-active.ovpn"

# CLI Arguments with short-slug defaults
BRIDGE_TAG="${1:-Seattle}"
EXIT_ARG="${2:-czech}"

if [ "$BRIDGE_TAG" = "-h" ] || [ "$BRIDGE_TAG" = "--help" ]; then
    echo "Usage: $0 [BRIDGE_ARG] [EXIT_ARG]"
    echo "  Default: $0 Seattle czech"
    echo "  Note: Short slugs try '<slug>.privacy.network' first, then automatically"
    echo "        fall back to the region's '.pvt.site' FQDN from pia-v6-servers.dat."
    echo "  Run ./list-PIA-OC-options.sh to view all valid arguments."
    exit 0
fi

# Build ordered list of exit host candidates
EXIT_CANDIDATES=()
if [[ "$EXIT_ARG" == *.* ]]; then
    EXIT_CANDIDATES+=("$EXIT_ARG")
else
    PRIMARY_HOST="${EXIT_ARG}.privacy.network"
    EXIT_CANDIDATES+=("$PRIMARY_HOST")

    if [ -f "$V6_DATA" ]; then
        FALLBACK_HOST=$(jq -r --arg slug "$EXIT_ARG" '
            .regions[] | select((.id | gsub("_"; "-")) == $slug) | .dns // empty
        ' "$V6_DATA" | head -n 1)

        if [ -n "$FALLBACK_HOST" ] && [ "$FALLBACK_HOST" != "$PRIMARY_HOST" ]; then
            EXIT_CANDIDATES+=("$FALLBACK_HOST")
        fi
    fi
fi

# Extract single bridge server details from NM-PIA-OC.json
BRIDGE_JSON=$(jq -c --arg tag "$BRIDGE_TAG" '.servers[] | select(.tag == $tag)' "$SS_CONFIG")

if [ -z "$BRIDGE_JSON" ]; then
    echo "ERROR: Unknown entry bridge '$BRIDGE_TAG'. Run ./list-PIA-OC-options.sh for valid options."
    exit 1
fi

SS_SERVER_IP=$(echo "$BRIDGE_JSON" | jq -r '.server')
SS_SERVER_PORT=$(echo "$BRIDGE_JSON" | jq -r '.server_port')
SS_PASSWORD=$(echo "$BRIDGE_JSON" | jq -r '.password')
SS_METHOD=$(echo "$BRIDGE_JSON" | jq -r '.method')

# Auto-detect active physical default gateway and interface
DEFAULT_ROUTE=$(ip route show default | grep -v "tun" | head -n 1)
GATEWAY=$(echo "$DEFAULT_ROUTE" | awk '{print $3}')
INTERFACE=$(echo "$DEFAULT_ROUTE" | awk '{print $5}')

if [ -z "$GATEWAY" ] || [ -z "$INTERFACE" ]; then
    echo "ERROR: Could not auto-detect active physical gateway or network interface."
    exit 1
fi

echo "Detected physical gateway $GATEWAY on interface $INTERFACE"

pkill openvpn 2>/dev/null
pkill sslocal 2>/dev/null
sleep 1
pkill -9 openvpn 2>/dev/null
pkill -9 sslocal 2>/dev/null
resolvectl flush-caches >/dev/null 2>&1

echo "Initializing local SOCKS obfuscation proxy engine for $BRIDGE_TAG ($SS_SERVER_IP:$SS_SERVER_PORT)..."
if [ ! -f "$PROXY_BINARY" ]; then
    echo "ERROR: The sslocal binary was not found at $PROXY_BINARY"
    exit 1
fi

nohup "$PROXY_BINARY" \
    -s "${SS_SERVER_IP}:${SS_SERVER_PORT}" \
    -b "127.0.0.1:1080" \
    -k "$SS_PASSWORD" \
    -m "$SS_METHOD" >/var/log/sslocal-pia.log 2>&1 &
sleep 2

if ! ss -tln | grep -q ":1080 "; then
    echo "ERROR: The local shadowsocks client failed to bind to port 1080."
    pkill sslocal 2>/dev/null
    exit 1
fi

# Pin the selected Shadowsocks bridge IP to the physical NIC
ip route replace "${SS_SERVER_IP}/32" via "$GATEWAY" dev "$INTERFACE"

if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: Template not found at $TEMPLATE"
    ip route del "${SS_SERVER_IP}/32" via "$GATEWAY" dev "$INTERFACE" 2>/dev/null
    pkill sslocal 2>/dev/null
    exit 1
fi

CONNECTED=false
ACTIVE_EXIT_HOST=""
TRACE_OUT=""

for EXIT_HOST in "${EXIT_CANDIDATES[@]}"; do
    echo "Attempting route: Local -> [$BRIDGE_TAG ($SS_SERVER_IP:$SS_SERVER_PORT)] -> [$EXIT_HOST:501]"

    sed "s|EXIT_HOST_PLACEHOLDER|${EXIT_HOST}|g" "$TEMPLATE" > "$RUNTIME_PROFILE"
    chmod 600 "$RUNTIME_PROFILE"

    nohup openvpn --config "$RUNTIME_PROFILE" --route-noexec >/var/log/openvpn-pia.log 2>&1 &

    for i in {1..15}; do
        if ip link show dev tun0 >/dev/null 2>&1; then
            break
        fi
        sleep 1
        echo -n "."
    done
    echo ""

    if ! ip link show dev tun0 >/dev/null 2>&1; then
        echo "WARNING: OpenVPN failed to initialize tun0 via $EXIT_HOST."
        pkill openvpn 2>/dev/null
        sleep 1
        pkill -9 openvpn 2>/dev/null
        rm -f "$RUNTIME_PROFILE"
        continue
    fi

    ip route replace 0.0.0.0/1 dev tun0
    ip route replace 128.0.0.0/1 dev tun0

    resolvectl dns tun0 10.0.0.243
    resolvectl domain tun0 "~."
    resolvectl flush-caches

    echo "Testing connection via $EXIT_HOST with 6-second timeout safety rail..."
    TRACE_OUT=$(curl -fsS --max-time 6 https://1.1.1.1/cdn-cgi/trace 2>/dev/null)
    if [ -n "$TRACE_OUT" ]; then
        CONNECTED=true
        ACTIVE_EXIT_HOST="$EXIT_HOST"
        break
    else
        echo "WARNING: Connectivity test failed via $EXIT_HOST! Cleaning up attempt..."
        ip route del 0.0.0.0/1 dev tun0 2>/dev/null
        ip route del 128.0.0.0/1 dev tun0 2>/dev/null
        pkill openvpn 2>/dev/null
        sleep 1
        pkill -9 openvpn 2>/dev/null
        resolvectl revert tun0 2>/dev/null
        rm -f "$RUNTIME_PROFILE"
    fi
done

if [ "$CONNECTED" != true ]; then
    echo "ERROR: All exit candidates failed for '$EXIT_ARG'. Rolling back bridge route and proxy..."
    ip route del "${SS_SERVER_IP}/32" via "$GATEWAY" dev "$INTERFACE" 2>/dev/null
    pkill openvpn 2>/dev/null
    pkill sslocal 2>/dev/null
    rm -f "$RUNTIME_PROFILE"
    exit 1
fi

VPN_PUBLIC_IP=$(echo "$TRACE_OUT" | awk -F= '/^ip=/ {print $2}')
VPN_LOC=$(echo "$TRACE_OUT" | awk -F= '/^loc=/ {print $2}')
TUN_IP=$(ip -4 -o addr show dev tun0 | awk '{print $4}')
CIPHER_USED=$(grep "Data Channel:" /var/log/openvpn-pia.log | tail -n 1 | sed -E "s/.*Data Channel: //; s/'//g")
[ -z "$CIPHER_USED" ] && CIPHER_USED="cipher unknown"

echo "SUCCESS: The obfuscated tunnel is active, stable, and online!"
echo "  Active Exit    : $ACTIVE_EXIT_HOST"
echo "  Public Exit IP : ${VPN_PUBLIC_IP:-unknown} (${VPN_LOC:-unknown})"
echo "  Tunnel IP      : ${TUN_IP:-unknown}"
echo "  Data Channel   : $CIPHER_USED"

echo "$(date -Iseconds) | Bridge: $BRIDGE_TAG ($SS_SERVER_IP) | Exit: $ACTIVE_EXIT_HOST | PublicIP: ${VPN_PUBLIC_IP:-unknown} (${VPN_LOC:-unknown}) | TunIP: ${TUN_IP:-unknown} | $CIPHER_USED" >> /var/log/pia-cipher-history.log

