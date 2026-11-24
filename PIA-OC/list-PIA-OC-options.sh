#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/PIA-OC.conf"
# Lists available PIA Shadowsocks Entry Bridges and OpenVPN TCP Exit POPs
# formatted as clean, suffix-free CLI arguments for OpenVPN-OC-up.sh

SS_CONFIG="${SCRIPT_DIR}/NM-PIA-OC.json"
V6_DATA="${SCRIPT_DIR}/pia-v6-servers.dat"

FILTER=""
PF_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --pf)
            PF_ONLY=true
            ;;
        -h|--help)
            echo "Usage: $0 [--pf] [search_filter]"
            echo "  --pf            Show only Exit POPs that support port forwarding"
            echo "  search_filter   Filter Exit POPs by slug, name, or DNS (e.g., 'uk', 'czech', 'us')"
            exit 0
            ;;
        *)
            FILTER="$arg"
            ;;
    esac
done

echo "======================================================================"
echo " 1. SHADOWSOCKS ENTRY BRIDGES (Argument 1 - from NM-PIA-OC.json)"
echo "======================================================================"
if [ -f "$SS_CONFIG" ]; then
    printf "  %-16s %-18s %s\n" "BRIDGE_ARG" "BRIDGE_IP" "LOCAL_PORT"
    printf "  %-16s %-18s %s\n" "----------" "---------" "----------"
    jq -r '
        . as $root |
        .servers[] |
        .tag as $t |
        ($root.locals[] | select(.server == $t) | .local_port) as $lp |
        "\($t)\t\(.server)\t\($lp)"
    ' "$SS_CONFIG" | while IFS=$'\t' read -r tag ip lport; do
        printf "  %-16s %-18s %s\n" "$tag" "$ip" "$lport"
    done
else
    echo "  [!] Missing $SS_CONFIG"
fi

echo ""
echo "======================================================================"
echo " 2. PIA EXIT POPs (Argument 2 - from ${V6_DATA})"
echo "======================================================================"
if [ -f "$V6_DATA" ]; then
    printf "  %-24s %-6s %s\n" "EXIT_ARG" "PF" "REGION NAME"
    printf "  %-24s %-6s %s\n" "--------" "--" "-----------"
    jq -r --arg f "$FILTER" --argjson pf "$PF_ONLY" '
        .regions[]

        | select(.offline | not)
        | select(.servers.ovpntcp != null and (.servers.ovpntcp | length > 0))
        | select(if $pf then .port_forward == true else true end)

        | (.id | gsub("_"; "-")) as $slug
        | select(
            if $f != "" then
                (($slug | ascii_downcase | contains($f | ascii_downcase)) or
                 (.name | ascii_downcase | contains($f | ascii_downcase)) or
                 (.dns | ascii_downcase | contains($f | ascii_downcase)))
            else true end
        )
        | "\($slug)\t\(if .port_forward then "yes" else "no" end)\t\(.name)"
    ' "$V6_DATA" | sort | while IFS=$'\t' read -r slug pf_flag rname; do
        printf "  %-24s %-6s %s\n" "$slug" "$pf_flag" "$rname"
    done
else
    echo "  [!] Missing $V6_DATA (run ./update-PIA-OC-servers.sh)"
fi

echo ""
echo "======================================================================"
echo " EXAMPLE USAGE & DOMAIN SUFFIX NOTES:"
echo "   ./OpenVPN-OC-up.sh Seattle czech"
echo "   ./OpenVPN-OC-up.sh UK-London swiss"
echo "   ./OpenVPN-OC-up.sh Amsterdam austria.pvt.site"
echo ""
echo "   * Short args (no dots) auto-append '.privacy.network' (recommended;"
echo "     load-balances across healthy regional POP nodes)."
echo "   * Full FQDNs (with dots, e.g., '.pvt.site' or '.privacy.network')"
echo "     pass through as-is (note: some '.pvt.site' nodes time out on 501)."
echo "======================================================================"

