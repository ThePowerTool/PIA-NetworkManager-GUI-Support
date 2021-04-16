#!/bin/bash
#
# Install OpenVPN profiles in NetworkManager for PIA
#
# To reload gnome UI with updated profile filenames
# ]# nmcli con reload
#
# New Servers URL:
# https://serverlist.piaservers.net/vpninfo/servers/v4
#
# Note:  There are 2 request (generateToken, getSignature) required
#        to initiate port forwarding.
#        generateToken requires live data (from the New Servers URL)
#        GetSignature requires static data provided by this script
#           via /var/log/pia-v4-at-install.dat
#
# support for ./.pia-credentials is provided.  As can be seen, below,
# .pia-credentials must be created with only 2 lines.  The 1st line
# must contain only the pia username and the 2nd, your password.

error() {
	echo $@ >&2
	exit 255
}

if [ "$(whoami)" != "root" ]; then
	error "This script needs to be run as root. Try again with 'sudo $0'"
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
  echo "This script will run without your passsword."
  echo "This is more secure but can be onorus requiring"
  echo "password entry via the NM-GUI."
  echo "* You may rerun this script to provide a password. *"
fi
echo
export PIA_PASS

: <<'END'
pkgerror="Failed to install the required packages, aborting."

##
# Debian-based distributions
if command -v apt-get 2>&1 >/dev/null; then
	installpkg=()

	if ! dpkg -l python2.7 | grep -q '^ii'; then
		installpkg+=(python2.7)
	fi

	if ! dpkg -l network-manager-openvpn | grep -q '^ii'; then
		installpkg+=(network-manager-openvpn)
	fi

	if [ ! -z "$installpkg" ]; then
		apt-get install ${installpkg[@]} || error $pkgerror
	fi

##
# RHEL-based distributions
elif command -v rpm 2>&1 >/dev/null; then
	installpkg=()

	if ! rpm -q python 2>&1 >/dev/null; then
		installpkg+=(python)
	fi

	if ! rpm -q NetworkManager-openvpn 2>&1 >/dev/null; then
		installpkg+=(NetworkManager-openvpn)
	fi

	if [ ! -z "$installpkg" ]; then
		if which dnf; then
			dnf install ${installpkg[@]} || error "$pkgerror"
		else
			yum install ${installpkg[@]} || error "$pkgerror"
		fi
	fi

##
# ArchLinux
elif command -v pacman 2>&1 >/dev/null; then
	installpkg=()

	if ! pacman -Q python2 2>/dev/null; then
		installpkg+=(python2)
	fi

	if ! pacman -Q networkmanager-openvpn 2>/dev/null; then
		installpkg+=(networkmanager-openvpn)
	fi

	if [ ! -z "$installpkg" ]; then
		pacman -S ${installpkg[@]} || error "$pkgerror"
	fi
fi

END

##
# Ask questions

echo -n "PIA username (pNNNNNNN): "
if [ -z "$PIA_USER" ];then
        read PIA_USER
fi
echo "$PIA_USER"

if [ -z "$PIA_USER" ]; then
	error "Username is required, aborting."
fi

######################################################################
# Port Forwarding Select
# set to "true" or "false" to match data key .port_forward content
echo -n "Will you require port forwarding Y/n (Y): "
read pia_pf

case "$pia_pf" in
        Y|y|yes|"")
                pia_pf="true"
                PIA_st="PIApf" # set PIA_servicetype designator [for profile]
                echo "Yes"
                ;;

        N|n|no)
                pia_pf="false"
                PIA_st="PIA"   # set PIA_servicetype (no to port forwarding)
                echo "No *****Port Forwarding will not be available*****"
                ;;
        *)
                error "You must select "Y" or "n" for port forwarding."
esac
######################################################################
echo -n "Connection method UDP/tcp (UDP): "
read pia_tcp

case "$pia_tcp" in
	U|u|UDP|udp|"")
		pia_tcp=no
		;;
	T|t|TCP|tcp)
		pia_tcp=yes
		;;
	*)
		error "Connection protocol must be UDP or TCP."
esac
if [ "$pia_tcp" = "no" ];then echo "UDP selected";fi
if [ "$pia_tcp" = "yes" ];then echo "tcp selected";fi

echo -n "Strong encryption Y/n (Y): "
read pia_strong

case "$pia_strong" in
	Y|y|yes|"")
		pia_cert=ca.rsa.4096.crt
		pia_cipher=AES-256-CBC
		pia_auth=SHA256

		if [ "$pia_tcp" = "yes" ]; then
			pia_port=501
		else
			pia_port=1197
		fi
		;;

	N|n|no)
		pia_cert=ca.rsa.2048.crt
		pia_cipher=AES-128-CBC
		pia_auth=SHA1

		if [ "$pia_tcp" = "yes" ]; then
			pia_port=502
		else
			pia_port=1198
		fi
		;;
	*)
		error "Strong encryption must be on or off."
esac

if [ "$pia_cert" = "ca.rsa.4096.crt" ];then echo -n "Strong encryption selected.  Using ";fi
if [ "$pia_cert" = "ca.rsa.2048.crt" ];then echo -n "Using default ";fi
echo "$pia_cipher, $pia_auth."

##
# Download and install
test -d /etc/openvpn || mkdir /etc/openvpn
curl -sS -o "/etc/openvpn/pia-$pia_cert" \
	"https://www.privateinternetaccess.com/openvpn/$pia_cert" \
	|| error "Failed to download OpenVPN CA certificate, aborting."
curl -sS -o "./ca.rsa.4096.crt" \
        "https://www.privateinternetaccess.com/openvpn/ca.rsa.4096.crt" \
        || error "Failed to download OpenVPN CA certificate, aborting."

IFS=$(echo)
servers=$(curl -Ss "https://serverlist.piaservers.net/vpninfo/servers/v4" | head -1)

# Save the v4 downloaded and used during install as a static file
# for getSignature requests via port_forwarding.sh
echo $servers > "/var/log/pia-v4-at-install.dat"

if [ -z "$servers" ]; then
	error "Failed to download server list, aborting."
fi

groups=$(echo $servers | jq -r '.groups')

rm -f "/etc/NetworkManager/system-connections/PIA"*

# Set $pia_protocol to actual protocol then pull server data
# 1st, exit on invalid $pia_tcp string
if ! [[ "$pia_tcp" = "yes" || "$pia_tcp"="no" ]]; then echo "pia_tcp=$pia_tcp <--should be yes or no. Exiting!";exit 0;fi

if [ "$pia_tcp" = "yes" ]; then 
    pia_protocol="tcp"
    pia_prot_port=$(echo $groups | jq -r '.ovpntcp[0].ports[]')
    servers="$( echo $servers |
        jq --argjson PF_SUPP "$pia_pf" -r '.regions[] | select(.port_forward==$PF_SUPP) |
        .servers.ovpntcp[0].ip+":"+.name' )"
fi

if [ "$pia_tcp" = "no" ]; then 
    pia_protocol="udp"
    pia_prot_port=$(echo $groups | jq -r '.ovpnudp[0].ports[]')
    servers="$( echo $servers |
        jq --argjson PF_SUPP "$pia_pf" -r '.regions[] | select(.port_forward==$PF_SUPP) |
        .servers.ovpnudp[0].ip+":"+.name' )"
fi

echo "$servers" | while read server; do
	host=$(echo "$server" | cut -d: -f1)
	name="$PIA_st-"$(echo "$server" | cut -d: -f2)
	nmfile="/etc/NetworkManager/system-connections/$name"

        # loop to add each port (multiple via "remote=" in profile)
        remote=$(echo $pia_prot_port | while read f;do echo "remote=$host $f $pia_protocol";done)

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
$remote
cipher=$pia_cipher
auth=$pia_auth
connection-type=password
password-flags=0
port=$pia_port
proto-tcp=$pia_tcp
ca=/etc/openvpn/pia-$pia_cert

[vpn-secrets]
password=$PIA_PASS

[ipv4]
method=auto
EOF
        chmod 0600 "$nmfile"
done

nmcli connection reload || \
	error "Failed to reload NetworkManager connections: installation was complete, but may require a restart to be effective."

echo "Installation is complete!"
