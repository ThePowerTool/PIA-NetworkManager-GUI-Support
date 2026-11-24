#!/bin/bash

echo "Quick One-Line Status Commands"

# Check tun0 + active routes
ip -brief addr show tun0 && ip route show | grep -E "0\.0\.0\.0/1|128\.0\.0\.0/1"

# Check DNS lock
resolvectl status tun0

# Check both daemons (sslocal, openvpn)
pgrep -a "sslocal|openvpn"
