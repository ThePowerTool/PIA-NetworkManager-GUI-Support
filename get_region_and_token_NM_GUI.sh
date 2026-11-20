#!/bin/bash
echo "get_region_and_token_NM_GUI.sh"
echo "Version 1.3"
#
# Important Note:
#   This code is not intended for use by anyone.
#   This code is strictly for testing purposes.
#   Only use this code if you are very familiar with PIA, the PIA API, and
#    bash scripting.
#   Using this code you accept full responsibility for *anything* that happens.
#   That said:  Have fun!!! :-)

# With a PIA NetworkManager profile this script may hopefully
# be used to request port forwarding.

# This script is not intended to work with the PIA manual connection script and
# will fail and exit if a manual connection is detected.

# Prerequisites:
# - Must be launched as root
# - Must be launched from the directory containing ca.rsa.4096.crt and port_forwarding.sh
# - /var/log/pia-v6-at-install.dat must exist (created by pia_NM_profiles_install.sh)
# - Optional ./.pia-credentials (2 lines: line 1 = username, line 2 = password)

# Only allow script to run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script needs to be run as root. Try again with 'sudo $0'"
  exit 1
fi

# Verify required utilities
for cmd in curl jq nmcli ip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required dependency '$cmd' is missing. Please install it and try again."
    exit 1
  fi
done

# Verify NetworkManager profiles were installed
if [[ ! -f /var/log/pia-v6-at-install.dat ]]; then
  echo "Installation of NetworkManager profiles not found."
  echo "/var/log/pia-v6-at-install.dat should have been created by pia_NM_profiles_install.sh."
  exit 1
fi

# Verify Next-Gen CA certificate and port_forwarding.sh exist in current directory
if [[ ! -f ./ca.rsa.4096.crt || ! -f ./port_forwarding.sh ]]; then
  echo "Missing ./ca.rsa.4096.crt or ./port_forwarding.sh in the current directory."
  echo "Please run this script from your PIA-NetworkManager-GUI-Support directory."
  exit 1
fi

# Check for ./.pia-credentials. If found, load username and password
if [[ -f ./.pia-credentials ]]; then
  chmod 600 ./.pia-credentials 2>/dev/null
  mapfile -t creds < ./.pia-credentials
  PIA_USER="${creds[0]}"
  PIA_PASS="${creds[1]}"
  echo ".pia-credentials found (loaded credentials for user: $PIA_USER)"
fi

# Get username & password
if [ -z "$PIA_USER" ]; then
  echo
  read -rp "PIA username (pNNNNNNN): " PIA_USER
fi

if [ -z "$PIA_USER" ]; then
  echo "Username is required, aborting."
  exit 1
fi
echo
export PIA_USER

if [ -z "$PIA_PASS" ]; then
  read -rsp "PIA password: " PIA_PASS
  echo
fi

if [ -z "$PIA_PASS" ]; then
  echo "Password is required, aborting."
  exit 1
fi
echo
export PIA_PASS

###################################################
# Prep:
# Verify connection (via pid, tun0, tun06)
declare -a adapter
adapter=("tun0" "tun06")
pid_filepath="/opt/piavpn-manual/pia_pid"
echo "Checking for ${#adapter[*]} potential adapter(s)..."
x=0
while [ "$x" -lt "${#adapter[*]}" ]; do
  notfound="Device \"${adapter[$x]}\" does not exist."
  echo -n "Checking for adapter $x = ${adapter[$x]}: "
  adapter_check="$(ip a s "${adapter[$x]}" 2>&1)"
  if [ "$adapter_check" = "$notfound" ]; then
    echo "$adapter_check"
  else
    exitflag[$x]="${adapter[$x]} found!"
    echo "${exitflag[$x]}"
  fi
  ((x++))
done

# Verify connection (manual via pid)
if [ -f "$pid_filepath" ]; then
  exitflag[2]="$pid_filepath *found*"
fi

# Display exit flags (VPN connection status)
for index in "${!exitflag[@]}"; do
  if [ "${exitflag[$index]}" != "" ]; then
    echo "$index: ${exitflag[$index]}"
  fi
done

# Manual connection detected exitflag status:
if [[ "${exitflag[1]}" = "tun06 found!" && "${exitflag[2]}" = "/opt/piavpn-manual/pia_pid *found*" ]]; then
  echo "This script does not support the PIA manual connection script."
  echo "Why do you find yourself here?"
  exit 0
fi

# Check exitflag array for VPN
if [ "${!exitflag[*]}" = "" ]; then
  echo "No VPN connections found."
  exit 0
fi

# End Prep: connection status verified
###################################################

# serverlist_from_install must be from the initial PIA NM install
serverlist_from_install="$(cat /var/log/pia-v6-at-install.dat)"

# Get active VPN profile name from nmcli
PIAnmname=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="vpn" && $1 ~ /^PIApf-/ {print $1; exit}')
if [ -z "$PIAnmname" ]; then
  # Fallback to first active VPN connection to give a helpful message
  PIAnmname=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="vpn" {print $1; exit}')
fi
echo "PIAnmname=$PIAnmname"

# Verify "Yes" was selected during initial installation of profiles:
if [[ ! "${PIAnmname:0:6}" = "PIApf-" ]]; then
  echo "The active NetworkManager VPN profile ($PIAnmname)"
  echo "does not appear to be a profile installed with support for port forwarding."
  echo "You may need to connect to a 'PIApf-*' profile or re-run pia_NM_profiles_install.sh selecting 'Y' for port forwarding."
  exit 0
fi

PIAname="${PIAnmname:6}" # Remove the "PIApf-" prefix
echo "PIAname='$PIAname'"

# Query install-time v6 JSON (matching sanitized region name)
oip="$(echo "$serverlist_from_install" | jq --arg R_NAME "$PIAname" -r '.regions[] | select((.name | gsub("/"; "-")) == $R_NAME) | .servers.ovpntcp[0].ip')"
ocn="$(echo "$serverlist_from_install" | jq --arg R_NAME "$PIAname" -r '.regions[] | select((.name | gsub("/"; "-")) == $R_NAME) | .servers.ovpntcp[0].cn')"
mip="$(echo "$serverlist_from_install" | jq --arg R_NAME "$PIAname" -r '.regions[] | select((.name | gsub("/"; "-")) == $R_NAME) | .servers.meta[0].ip')"
mcn="$(echo "$serverlist_from_install" | jq --arg R_NAME "$PIAname" -r '.regions[] | select((.name | gsub("/"; "-")) == $R_NAME) | .servers.meta[0].cn')"

echo "ovpntcp[0].ip=$oip"
echo "ovpntcp[0].cn=$ocn"
echo "meta[0].ip=$mip"
echo "meta[0].cn=$mcn"

echo "Sending token request to PIA API..."

# Display example curl command (with password redacted)
echo "\$ curl -s --location --request POST \\"
echo "  \"https://www.privateinternetaccess.com/api/client/v2/token\" \\"
echo "  --form \"username=$PIA_USER\" \\"
echo "  --form \"password=<PASSWORD>\""

generateTokenResponse=$(curl -s --location --request POST \
  "https://www.privateinternetaccess.com/api/client/v2/token" \
  --form "username=$PIA_USER" \
  --form "password=$PIA_PASS")

PIA_TOKEN="$(echo "$generateTokenResponse" | jq -r '.token // empty' 2>/dev/null)"

if [ -z "$PIA_TOKEN" ]; then
  echo "Could not get a token. Please check your account credentials."
  echo "Response: $generateTokenResponse"
  echo
  echo "You can also try debugging by manually running the curl command:"
  echo "\$ curl -vs --location --request POST \"https://www.privateinternetaccess.com/api/client/v2/token\" \\"
  echo "  --form \"username=$PIA_USER\" \\"
  echo "  --form \"password=<PASSWORD>\""
  exit 1
fi

echo "Token acquired! This token will expire in 24 hours."
echo

# Obtain local VPN gateway IP from NetworkManager (e.g., 10.x.x.1)
PF_GATEWAY=$(nmcli -g IP4.GATEWAY connection show "$PIAnmname")

echo "PIA_TOKEN=$PIA_TOKEN"
echo "PF_GATEWAY=$PF_GATEWAY"
echo "meta.cn=$mcn"

if [[ -z "$PF_GATEWAY" || -z "$mcn" || "$mcn" == "null" ]]; then
  echo "Error: Missing PF_GATEWAY or PF_HOSTNAME (meta.cn). Cannot start port_forwarding.sh."
  exit 1
fi

# Show execute command for port_forwarding.sh
echo "
This script only supports PIA PF servers.
Starting procedure to enable port forwarding by running the following command:
\$ PIA_TOKEN=\"$PIA_TOKEN\" \\
  PF_GATEWAY=\"$PF_GATEWAY\" \\
  PF_HOSTNAME=\"$mcn\" \\
  ./port_forwarding.sh
"

# Launch port_forwarding.sh with required environment variables
PIA_TOKEN="$PIA_TOKEN" \
  PF_GATEWAY="$PF_GATEWAY" \
  PF_HOSTNAME="$mcn" \
  ./port_forwarding.sh

