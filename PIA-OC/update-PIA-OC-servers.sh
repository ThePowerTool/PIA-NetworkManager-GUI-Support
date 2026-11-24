#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/PIA-OC.conf"
# Fetches live PIA v6 server data to update /root/PIA-OC/pia-v6-servers.dat (Exit POPs)
# and validates /root/PIA-OC/NM-PIA-OC.json (Shadowsocks Entry Bridges).

set -euo pipefail

API_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"
V6_DATA="${SCRIPT_DIR}/pia-v6-servers.dat"
SS_CONFIG="${SCRIPT_DIR}/NM-PIA-OC.json"

for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' is required. Install it with: sudo dnf install -y $cmd"
        exit 1
    fi
done

echo "Fetching latest v6 server list from PIA..."
RAW_JSON=$(curl -fsS --max-time 15 "$API_URL" | head -n 1)

if [ -z "$RAW_JSON" ] || ! echo "$RAW_JSON" | jq -e '.regions | length > 0' >/dev/null 2>&1; then
    echo "ERROR: Failed to fetch valid JSON from $API_URL"
    exit 1
fi

# 1. Update /root/PIA-OC/pia-v6-servers.dat atomically (keeps /var/log/pia-v6-at-install.dat untouched)
echo "$RAW_JSON" > "${V6_DATA}.tmp"
chmod 600 "${V6_DATA}.tmp"
mv "${V6_DATA}.tmp" "$V6_DATA"

TOTAL_REGIONS=$(jq '.regions | length' "$V6_DATA")
TCP_EXIT_POPS=$(jq '[.regions[] | select((.offline | not) and (.servers.ovpntcp | length > 0))] | length' "$V6_DATA")
echo "[OK] Updated $V6_DATA ($TOTAL_REGIONS total regions, $TCP_EXIT_POPS online OpenVPN TCP Exit POPs)"

# 2. Validate /root/PIA-OC/NM-PIA-OC.json (PIA does not expose SS bridges in public v6 JSON)
if [ -f "$SS_CONFIG" ] && jq -e '.servers | length > 0' "$SS_CONFIG" >/dev/null 2>&1; then
    BRIDGE_COUNT=$(jq '.servers | length' "$SS_CONFIG")
    echo "[OK] Verified $SS_CONFIG ($BRIDGE_COUNT Shadowsocks entry bridges configured)"
else
    echo "[WARN] $SS_CONFIG is missing or invalid JSON!"
    exit 1
fi

