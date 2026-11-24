#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/PIA-OC.conf"
# Master deployment script for PIA Obfuscated NetworkManager Profiles (Fedora 42)
# Uses O-PIA- prefix to stay isolated from PIA-* and PIApf-* GUI profiles

set -euo pipefail

SS_JSON="${SCRIPT_DIR}/NM-PIA-OC.json"
CRED_FILE="/root/.pia-auth"
CONN_DIR="${SCRIPT_DIR}/O-PIA-NMprofiles"
EXIT_HOST="${1:-czech-republic.pvt.site}"

if [ ! -d "$CONN_DIR" ]; then
    echo "ERROR: Missing directory ${CONN_DIR}"
    exit 1
fi

if [ ! -f "$CRED_FILE" ]; then
    echo "ERROR: Credential file not found at $CRED_FILE (expected line 1: user, line 2: pass)."
    exit 1
fi

chmod 600 "$CRED_FILE"
PIA_USER=$(sed -n '1p' "$CRED_FILE" | tr -d '\r\n')
PIA_PASS=$(sed -n '2p' "$CRED_FILE" | tr -d '\r\n')

if [ -z "$PIA_USER" ] || [ -z "$PIA_PASS" ]; then
    echo "ERROR: Username or password missing in $CRED_FILE."
    exit 1
fi

# Clean up only existing O-PIA-* profiles (leaves PIA-* and PIApf-* untouched)
rm -f "${CONN_DIR}"/O-PIA-*.nmconnection

# Read every configured bridge tag and local port directly from NM-PIA-OC.json
jq -r '
    . as $root |
    .servers[] |
    .tag as $t |
    ($root.locals[] | select(.server == $t) | .local_port) as $lp |
    "\($t)\t\(.server)\t\($lp)"
' "$SS_JSON" | while IFS=$'\t' read -r name ss_ip local_port; do
    prof_name="O-PIA-Czech-via-${name}"
    file_path="${CONN_DIR}/${prof_name}.nmconnection"

    echo "Generating profile: ${prof_name} (SOCKS 127.0.0.1:${local_port} -> SS ${ss_ip} -> ${EXIT_HOST})..."

    cat << PROFILE_EOF > "$file_path"
[connection]
id=${prof_name}
uuid=$(uuidgen)
type=vpn
autoconnect=false

[vpn]
auth=SHA256
ca=/etc/openvpn/pia-ca.rsa.4096.crt
cipher=AES-256-GCM
data-ciphers=AES-256-GCM:AES-128-GCM:AES-256-CBC
comp-lzo=no
connection-type=password
mssfix=1400
password-flags=0
port=501
proto-tcp=yes
remote=${EXIT_HOST}
remote-cert-tls=server
socks-proxy=127.0.0.1
socks-proxy-port=${local_port}
tun-mtu=1500
username=${PIA_USER}
service-type=org.freedesktop.NetworkManager.openvpn

[vpn-secrets]
password=${PIA_PASS}

[ipv4]
method=auto
route1=${ss_ip}/32,192.168.1.1

[ipv6]
method=disabled
PROFILE_EOF

    chmod 600 "$file_path"
done

echo "Done! All O-PIA-* profiles deployed to ${CONN_DIR}"

