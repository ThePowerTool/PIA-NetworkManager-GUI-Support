#!/bin/bash
echo "get_region_and_token_NM_GUI.sh"
echo "Version 1.0"
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
# this script must be launched by root
# this script must be launched from within ~/git/PIA-NetworkManager-GUI-Support
# the pia-NewServers-nm v5 output (pia-v5-at-install.dat) must be in /var/log
# support for ./.pia-credentials is provided.  As can be seen, below,
# .pia-credentials must be created with only 2 lines.  The 1st line
# must contain only the pia username and 2nd, your password.

# Only allow script to run as
if [ "$(whoami)" != "root" ]; then
  echo "This script needs to be run as root. Try again with 'sudo $0'"
  exit 1
fi

# Verify NetworkManager profiles were installed
if [[ ! -f /var/log/pia-v5-at-install.dat ]];
   then echo "Installation of NetworkManager profiles not found."
        echo "/var/log/pia-v5-at-install.dat should have been created."
   exit 0
fi
# Check for ./.pia-credentials.  If found, load username and password
if [[ -f ./.pia-credentials ]]; then
   while
     read a
     read b
   do
     PIA_USER="$a"
     PIA_PASS="$b"
     echo ".pia-credentials found"
     echo "PIA_USER=$PIA_USER"
     echo "PIA_PASS=$PIA_PASS"
   done < ./.pia-credentials
fi

# Get username & password
if [ -z "$PIA_USER" ]; then
   echo
   echo -n "PIA username (pNNNNNNN): "
   read PIA_USER
fi

if [ -z "$PIA_USER" ]; then
  echo "Username is required, aborting."
  exit 1
fi
echo
export PIA_USER

if [ -z "$PIA_PASS" ]; then
   echo -n "PIA password: "
   read -s PIA_PASS
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
# verify connection (via pid, tun0, tun06)
declare -a adapter
adapter=("tun0" "tun06")
pid_filepath="/opt/piavpn-manual/pia_pid"
echo "checking for ${#adapter[*]} potential adapter[s]"
x=0
while [ "$x" -lt "${#adapter[*]}" ]; do
  notfound="Device \"${adapter[$x]}\" does not exist."
  echo -n "checking for adapter $x = ${adapter[$x]}: "
  adapter_check="$( ip a s ${adapter[$x]} 2>&1 )"
  if [ "$adapter_check" = "$notfound" ]; then
     echo "$adapter_check"
     else
      exitflag[$x]="${adapter[$x]} found!"
      echo "${exitflag[$x]}"
  fi
  ((x++))
done

# verify connection (manual via pid)
if [ -f "$pid_filepath" ]; then exitflag[2]="$pid_filepath *found*";fi

# display exit flags (vpn connection status)
for index in ${!exitflag[*]}
do
  if [ "${exitflag[$index]}" != "" ]; then
  echo "$index: ${exitflag[$index]}"
  fi
done

# Manual connection detected exitflag status:
# 1: tun06 found!
# 2: /opt/piavpn-manual/pia_pid *found*
if [[ "${exitflag[1]}" = "tun06 found!" && "${exitflag[2]}" = "/opt/piavpn-manual/pia_pid *found*" ]]
   then
     echo "This script does not support the PIA manual connection script."
     echo "Why do you find yourself here?"
     exit 0
fi

# check exitflag array for VPN
if [ "${!exitflag[*]}" = "" ]; then echo "No VPN connections found."; exit 0;fi

# End Prep: connection status verified
###################################################

# Get Server Name and detail
# Note: serverlist_url must be the current list for the generateToken request
serverlist_url='https://serverlist.piaservers.net/vpninfo/servers/v5'

# Note: serverlist_from_install must be from the initial pia nm install
#       serverlist (saved as "/var/log/pia-v5-at-install.dat")
serverlist_from_install="$(cat /var/log/pia-v5-at-install.dat)"

# get Live Regional Data (lrd)
lrd="$(curl -s https://serverlist.piaservers.net/vpninfo/servers/v5 | head -1)"

# Get NM Profile Name from nmcli name, remove PIA prefix (to match v5 db region.name)
PIAnmname=$(nmcli -g name connection show | head -1)
echo "PIAnmname=$PIAnmname" # (e.g. "PIApf-Name") the nm profile name

# Verify "Yes" selected during initial installation of profiles:
if [[ ! "${PIAnmname:0:6}" = "PIApf-" ]];
    then
    echo "The NetworkManager profile $PIAnmname"
    echo "does not appear to be a profile installed with support for port forwarding."
    echo "You may need to re-run the profile installation selecting \"yes\""
    echo "for port forwarding."
    exit 0
fi

len=${#PIAnmname}
PIAname=${PIAnmname:6:$len} # Remove the "PIApf-" prefix
echo "PIAname='$PIAname'"   # now just "Name" (region.name from v5 data structure)

# with the correct Name (data structure region.name) from the profile get variables

# get ovpntcp.ip, ovpntcp.cn, meta.ip, meta.cn from the initial install serverlist (v5) $serverlist_from_install
oip="$(echo $serverlist_from_install | jq --arg R_NAME "$PIAname" -r '.regions[] | select(.name==$R_NAME) | .servers.ovpntcp[0].ip')"
ocn="$(echo $serverlist_from_install | jq --arg R_NAME "$PIAname" -r '.regions[] | select(.name==$R_NAME) | .servers.ovpntcp[0].cn')"
mip="$(echo $serverlist_from_install | jq --arg R_NAME "$PIAname" -r '.regions[] | select(.name==$R_NAME) | .servers.meta[0].ip')"
mcn="$(echo $serverlist_from_install | jq --arg R_NAME "$PIAname" -r '.regions[] | select(.name==$R_NAME) | .servers.meta[0].cn')"

# live (current) meta ip, meta cn
lmip="$(echo $lrd | jq --arg R_NAME "$PIAname" -r '.regions[] | select(.name==$R_NAME) | .servers.meta[0].ip')"
lmcn="$(echo $lrd | jq --arg R_NAME "$PIAname" -r '.regions[] | select(.name==$R_NAME) | .servers.meta[0].cn')"

# note mcn is PF_HOSTNAME (from the original pia script)
echo "ovpntcp.ip=$oip"
echo "ovpntcp.cn=$ocn"
echo "meta[0].ip=$mip"
echo "meta[0].ip=$lmip - live [current] PF_GATEWAY for generateToken req"
echo "meta[0].cn=$mcn"
echo "meta[0].cn=$lmcn - live [current] PF_HOSTNAME for generateToken req"

echo "Sending token request, authenticating with the meta service..."
# This curl req for generateToken uses the live (current) v5 data

# display CL (embedded code in generateTokenResponse, below)
echo $ curl -s -u \"$PIA_USER:$PIA_PASS\" \
  --connect-to \"$lmcn::$lmip:\" \
  --cacert \"ca.rsa.4096.crt\" \
  \"https://$lmcn/authv3/generateToken\"

generateTokenResponse=$(curl -s -u "$PIA_USER:$PIA_PASS" \
  --connect-to "$lmcn::$lmip:" \
  --cacert "ca.rsa.4096.crt" \
  "https://$lmcn/authv3/generateToken")
echo "$generateTokenResponse"

if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
  echo "Could not get a token. Please check your account credentials."
  echo
  echo "You can also try debugging by manually running the curl command:"
  echo $ curl -vs -u \"$PIA_USER:$PIA_PASS\" --cacert ca.rsa.4096.crt \
    --connect-to \"$lmcn::$lmip:\" \
    https://$lmcn/authv3/generateToken
  exit 1
fi

PIA_TOKEN="$(echo "$generateTokenResponse" | jq -r '.token')"
echo "This token will expire in 24 hours.
"

# just making sure this variable doesn't contain some strange string
if [ "$PIA_PF" != true ]; then
  PIA_PF="false"
fi

# PF_GATEWAY for port_forwarding.sh (local gateway e.g. 10.x.x.1)
# obtain local gateway IP from NM via nmcli
gatewayip=$(nmcli con show "PIApf-$PIAname" | grep IP4.GATEWAY)
# e.g.: "IP4.GATEWAY:                            10.20.111.1"
PF_GATEWAY=${gatewayip##I*\ }

echo "PIA_TOKEN=$PIA_TOKEN"
echo "PF_GATEWAY=$PF_GATEWAY"
echo "meta.cn=$mcn"

# Show execute command for the standard PIA script, "port_forwarding.sh"
# Note:  this command can be copied and pasted to a bash CL to run manually
echo "
This script only supports PIA PF servers.
Starting procedure to enable port forwarding by running the following command:
$ PIA_TOKEN=\"$PIA_TOKEN\" \\
  PF_GATEWAY=\"$PF_GATEWAY\" \\
  PF_HOSTNAME=\"$mcn\" \\
  ./port_forwarding.sh
"

# Launch port_forwarding with prefix variables
PIA_TOKEN=$PIA_TOKEN \
  PF_GATEWAY="$PF_GATEWAY" \
  PF_HOSTNAME="$mcn" \
  ./port_forwarding.sh

