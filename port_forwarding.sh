#!/bin/bash
echo "port_forwarding.sh"
echo "Version 1.3"
# Copyright (C) 2020 Private Internet Access, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Verify required utilities and CA certificate
for cmd in curl jq base64; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required dependency '$cmd' is missing. Please install it and try again."
    exit 1
  fi
done

if [[ ! -f "./ca.rsa.4096.crt" ]]; then
  echo "Missing ./ca.rsa.4096.crt in the current directory."
  echo "Please run this script from your PIA-NetworkManager-GUI-Support directory."
  exit 1
fi

# Check if the mandatory environment variables are set.
if [[ ! $PF_GATEWAY || ! $PIA_TOKEN || ! $PF_HOSTNAME ]]; then
  echo "This script requires 3 env vars:"
  echo "  PF_GATEWAY  - the IP of your gateway"
  echo "  PF_HOSTNAME - name of the host used for SSL/TLS certificate verification"
  echo "  PIA_TOKEN   - the token you use to connect to the vpn services"
  echo
  echo "An easy solution is to run get_region_and_token_NM_GUI.sh"
  echo "as it will obtain the active gateway, hostname, and token automatically."
  echo "Original PIA reference repo:"
  echo "https://github.com/pia-foss/manual-connections"
  exit 1
fi

# Curl request: getSignature
# Captures stdout and stderr cleanly without eval race conditions
getSig () {
  local err_file
  err_file=$(mktemp)

  echo "\$ curl -s -m 5 \\"
  echo "    --connect-to \"$PF_HOSTNAME::$PF_GATEWAY:\" \\"
  echo "    --cacert \"ca.rsa.4096.crt\" \\"
  echo "    -G --data-urlencode \"token=${PIA_TOKEN}\" \\"
  echo "    \"https://${PF_HOSTNAME}:19999/getSignature\""

  payload_and_signature=$(curl --verbose -m 5 \
    --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
    --cacert "ca.rsa.4096.crt" \
    -G --data-urlencode "token=${PIA_TOKEN}" \
    "https://${PF_HOSTNAME}:19999/getSignature" 2>"$err_file")

  t_err=$(<"$err_file")
  rm -f "$err_file"
}

# Function: Attempt to correct PIA SSL cert name drift
getCorrectedSSLCertName () {
  echo "Attempting to correct PIA SSL cert name drift..."

  if [[ "$t_err" != *"CN="* ]]; then
    echo "No SSL 'CN=' field found in curl output (request may have timed out or been refused)."
    echo "Curl stderr:"
    echo "$t_err"
    exit 1
  fi

  local f="${t_err#*CN=}"       # strip everything up to CN=
  f="${f%%[;,[:space:]]*}"       # strip trailing ; , or whitespace/newline
  PF_HOSTNAME="$f"

  echo "Corrected PIA SSL Cert Name: $PF_HOSTNAME"
  echo "Retrying getSignature with corrected PIA SSL Cert Name $PF_HOSTNAME..."
}

# Get the payload and the signature from the PF API.
if [[ ! $PAYLOAD_AND_SIGNATURE ]]; then
  echo "Getting new signature..."
  getSig
else
  payload_and_signature="$PAYLOAD_AND_SIGNATURE"
  echo "Using the following payload_and_signature from the env var:"
fi

# Check if the payload and the signature are OK.
# If they are not OK, try updating the SSL cert name.
if [ "$(echo "$payload_and_signature" | jq -r '.status' 2>/dev/null)" != "OK" ]; then
  echo "The payload_and_signature variable does not contain an OK status."
  getCorrectedSSLCertName
  getSig
fi

# Verify initial or secondary curl request via .status "OK"
if [ "$(echo "$payload_and_signature" | jq -r '.status' 2>/dev/null)" != "OK" ]; then
  echo "Failed to obtain a valid signature from getSignature. Exiting."
  exit 1
fi

# Extract signature and base64-decoded payload fields
signature="$(echo "$payload_and_signature" | jq -r '.signature')"
payload="$(echo "$payload_and_signature" | jq -r '.payload')"
port="$(echo "$payload" | base64 -d | jq -r '.port')"
expires_at="$(echo "$payload" | base64 -d | jq -r '.expires_at')"

echo "The signature is OK.

--> The port is $port and it will expire on $expires_at. <--

Trying to bind the port..."

# Repeat bindPort request every 15 minutes to keep the port alive
while true; do
  bind_port_response="$(curl -Gs -m 5 \
    --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
    --cacert "ca.rsa.4096.crt" \
    --data-urlencode "payload=${payload}" \
    --data-urlencode "signature=${signature}" \
    "https://${PF_HOSTNAME}:19999/bindPort")"
  echo "$bind_port_response"

  export bind_port_response
  if [ "$(echo "$bind_port_response" | jq -r '.status' 2>/dev/null)" != "OK" ]; then
    echo "The API did not return OK when trying to bind port. Exiting."
    exit 1
  fi
  echo "Port $port refreshed on $(date). This port will expire on $(date --date="$expires_at")"

  # sleep 15 minutes
  sleep 900
done

