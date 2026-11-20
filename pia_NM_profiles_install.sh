#!/bin/bash
echo "./pia_NM_profiles_install.sh"
echo "Version 1.1"
#
# Install OpenVPN profiles in NetworkManager for PIA and
# prepare for subsequent port-forwarding requests
#
# Note: While this script finishes by reloading the profiles, to manually 
#       reload desktop UI with updated profile filenames use:
#   sudo nmcli connection reload
#
# Servers URL (Official PIA manual-connections endpoint):
#   https://serverlist.piaservers.net/vpninfo/servers/v6
#
# Note: There are 2 requests (generateToken, getSignature) required
#       to initiate port forwarding.
#       - generateToken requires live data (from the Servers URL)
#       - getSignature requires static data provided by this script
#         via /var/log/pia-v6-at-install.dat
#
# Support for ./.pia-credentials is provided. If used, .pia-credentials
# must be created with only 2 lines:
#   Line 1: PIA username (e.g., p1234567)
#   Line 2: PIA password

set -o pipefail

error() {
    echo "$*" >&2
    exit 255
}

if [ "$(id -u)" -ne 0 ]; then
    error "This script needs to be run as root. Try again with 'sudo $0'"
fi

# Verify required runtime utilities are installed
for cmd in curl jq nmcli uuidgen; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required dependency '$cmd' is missing. Please install it and try again."
    fi
done

# Check for ./.pia-credentials. If found, load username and password
if [[ -f ./.pia-credentials ]]; then
    chmod 600 ./.pia-credentials 2>/dev/null
    mapfile -t creds < ./.pia-credentials
    PIA_USER="${creds[0]}"
    PIA_PASS="${creds[1]}"
    echo ".pia-credentials found (loaded credentials for user: $PIA_USER)"
fi

# Get username & password if not loaded from file
if [ -z "$PIA_USER" ]; then
    echo
    read -rp "PIA username (pNNNNNNN): " PIA_USER
fi

if [ -z "$PIA_USER" ]; then
    error "Username is required, aborting."
fi
echo

if [ -z "$PIA_PASS" ]; then
    read -rsp "PIA password (leave blank to prompt via NetworkManager GUI): " PIA_PASS
    echo
fi

if [ -z "$PIA_PASS" ]; then
    echo "Running without a stored password."
    echo "This is more secure, but NetworkManager GUI will prompt you when connecting."
    echo "* You may rerun this script at any time to store a password. *"
fi
echo

######################################################################
# Port Forwarding Select
# Set to "true" or "false" to match JSON key .port_forward
read -rp "Will you require port forwarding Y/n (Y): " pia_pf

case "$pia_pf" in
    Y|y|yes|"")
        pia_pf="true"
        PIA_st="PIApf" # Prefix for port-forwarding enabled profiles
        echo "Yes (prefix: $PIA_st-)"
        ;;
    N|n|no)
        pia_pf="false"
        PIA_st="PIA"   # Prefix for standard profiles
        echo "No (prefix: $PIA_st-) ***** Port Forwarding will not be available *****"
        ;;
    *)
        error "You must select 'Y' or 'n' for port forwarding."
        ;;
esac

######################################################################
# Protocol Select
read -rp "Connection method UDP/tcp (UDP): " pia_tcp

case "$pia_tcp" in
    U|u|UDP|udp|"")
        pia_tcp="no"
        pia_protocol="udp"
        echo "UDP selected"
        ;;
    T|t|TCP|tcp)
        pia_tcp="yes"
        pia_protocol="tcp"
        echo "TCP selected"
        ;;
    *)
        error "Connection protocol must be UDP or TCP."
        ;;
esac

######################################################################
# Encryption Select
read -rp "Strong encryption Y/n (Y): " pia_strong

case "$pia_strong" in
    Y|y|yes|"")
        pia_cert="ca.rsa.4096.crt"
        pia_cipher="AES-256-CBC"
        pia_auth="SHA256"
        if [ "$pia_tcp" = "yes" ]; then
            pia_port=501
        else
            pia_port=1197
        fi
        echo -n "Strong encryption selected. Using "
        ;;
    N|n|no)
        pia_cert="ca.rsa.2048.crt"
        pia_cipher="AES-128-CBC"
        pia_auth="SHA1"
        if [ "$pia_tcp" = "yes" ]; then
            pia_port=502
        else
            pia_port=1198
        fi
        echo -n "Standard encryption selected. Using "
        ;;
    *)
        error "Strong encryption must be 'Y' or 'n'."
        ;;
esac
echo "$pia_cipher, $pia_auth (port $pia_port)."

######################################################################
# Download CA certificates and v6 server list
mkdir -p /etc/openvpn
curl -fsS -o "/etc/openvpn/pia-$pia_cert" \
    "https://www.privateinternetaccess.com/openvpn/$pia_cert" \
    || error "Failed to download OpenVPN CA certificate ($pia_cert), aborting."

# Also save ca.rsa.4096.crt locally for port_forwarding.sh / get_region_and_token_NM_GUI.sh
curl -fsS -o "./ca.rsa.4096.crt" \
    "https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt" \
    || error "Failed to download ca.rsa.4096.crt, aborting."

servers_raw=$(curl -fsS "https://serverlist.piaservers.net/vpninfo/servers/v6" | head -n 1)

if [ -z "$servers_raw" ]; then
    error "Failed to download v6 server list, aborting."
fi

# Save the v6 JSON downloaded during install as a static file
# for getSignature requests via port_forwarding.sh
echo "$servers_raw" > "/var/log/pia-v6-at-install.dat"
chmod 644 "/var/log/pia-v6-at-install.dat"

# Filter regions by port-forwarding support and online status
filtered_servers=$(echo "$servers_raw" | jq --argjson PF_SUPP "$pia_pf" -r '
    .regions[]

    | select(.port_forward == $PF_SUPP and (.offline | not))
    | "\(.dns):\(.name)"
')

if [ -z "$filtered_servers" ]; then
    error "No matching online servers found in the v6 server list, aborting."
fi

# Remove only existing profiles matching the selected prefix ($PIA_st-)
rm -f "/etc/NetworkManager/system-connections/${PIA_st}-"*

# Configure password block depending on whether PIA_PASS was supplied
if [ -n "$PIA_PASS" ]; then
    pw_flag="0"
    vpn_secrets_block=$'\n[vpn-secrets]\npassword='"$PIA_PASS"
else
    pw_flag="1"
    vpn_secrets_block=""
fi

count=0
while IFS=: read -r host_fqname region_name; do
    [ -z "$host_fqname" ] && continue

    # Sanitize slashes in region names if any exist
    safe_region="${region_name//\//-}"
    name="${PIA_st}-${safe_region}"
    nmfile="/etc/NetworkManager/system-connections/${name}.nmconnection"

    cat <<EOF > "$nmfile"
[connection]
id=$name
uuid=$(uuidgen)
type=vpn
autoconnect=false

[vpn]
service-type=org.freedesktop.NetworkManager.openvpn
username=$PIA_USER
comp-lzo=no
remote=$host_fqname $pia_port $pia_protocol
cipher=$pia_cipher
auth=$pia_auth
connection-type=password
password-flags=$pw_flag
port=$pia_port
proto-tcp=$pia_tcp
ca=/etc/openvpn/pia-$pia_cert
$vpn_secrets_block

[ipv4]
method=auto
EOF
    chmod 0600 "$nmfile"
    ((count++))
done <<< "$filtered_servers"

nmcli connection reload || \
    error "Failed to reload NetworkManager connections: installation completed, but may require a NetworkManager restart."

echo "Installation is complete! Installed $count NetworkManager profiles (${PIA_st}-*)."
