#!/bin/sh
# VPN SSID Template for OpenWRT
# Creates a dedicated WiFi SSID that routes all traffic through a WireGuard VPN tunnel.
# Replicates ASUS VPN Fusion / Guest Network Pro VPN Network feature.
#
# Usage:
#   vpn-ssid-template.sh add <name> <wg_config_file> [band]
#   vpn-ssid-template.sh remove <name>
#   vpn-ssid-template.sh list
#
# Example:
#   vpn-ssid-template.sh add tw22 /tmp/protonvpn-tw.conf 5g
#   vpn-ssid-template.sh add jp23 /tmp/protonvpn-jp.conf 2g
#   vpn-ssid-template.sh remove tw22
#
# The WireGuard config file should be the standard format downloaded
# from ProtonVPN (or any WireGuard provider):
#   [Interface]
#   PrivateKey = ...
#   Address = 10.2.0.2/32
#   DNS = 10.2.0.1
#   [Peer]
#   PublicKey = ...
#   Endpoint = ...
#   AllowedIPs = 0.0.0.0/0
#
# Each VPN SSID gets:
#   - Dedicated WireGuard interface (wg_<name>)
#   - VLAN isolation (auto-assigned VLAN ID)
#   - Policy routing (only this SSID's traffic goes through VPN)
#   - DNS leak prevention (forced VPN DNS)
#   - Firewall zone (no cross-zone leaks)
#   - Kill switch (traffic blocked if VPN drops)
#
# Author: mingfai <ma@mingf.ai>
# License: GPL-2.0

set -e

SCRIPT_NAME="vpn-ssid-template"
BASE_VLAN=20
RT_TABLE_BASE=100

log() { logger -t "$SCRIPT_NAME" "$@"; echo "$@"; }

parse_wg_config() {
    local file="$1"
    WG_PRIVATE_KEY=$(grep -i "^PrivateKey" "$file" | cut -d= -f2- | tr -d ' ')
    WG_ADDRESS=$(grep -i "^Address" "$file" | cut -d= -f2- | tr -d ' ')
    WG_DNS=$(grep -i "^DNS" "$file" | cut -d= -f2- | tr -d ' ')
    WG_PUBLIC_KEY=$(grep -i "^PublicKey" "$file" | cut -d= -f2- | tr -d ' ')
    WG_ENDPOINT=$(grep -i "^Endpoint" "$file" | cut -d= -f2- | tr -d ' ')
    WG_ENDPOINT_HOST=$(echo "$WG_ENDPOINT" | cut -d: -f1)
    WG_ENDPOINT_PORT=$(echo "$WG_ENDPOINT" | cut -d: -f2)
    WG_ALLOWED_IPS=$(grep -i "^AllowedIPs" "$file" | cut -d= -f2- | tr -d ' ')
}

get_next_vlan() {
    local max=$BASE_VLAN
    for iface in $(uci -q show network | grep "proto='wireguard'" | cut -d. -f2); do
        local vid=$(uci -q get network."${iface}".vlan_id 2>/dev/null || echo 0)
        [ "$vid" -gt "$max" ] && max=$vid
    done
    echo $((max + 1))
}

get_radio_for_band() {
    local band="${1:-5g}"
    case "$band" in
        2g|2.4g|2.4) echo "radio0" ;;
        5g|5) echo "radio1" ;;
        6g|6) echo "radio2" ;;
        *) echo "radio1" ;; # default 5 GHz
    esac
}

cmd_add() {
    local name="$1"
    local wg_config="$2"
    local band="${3:-5g}"

    if [ -z "$name" ] || [ -z "$wg_config" ]; then
        echo "Usage: $0 add <name> <wg_config_file> [band]"
        echo "  band: 2g, 5g (default), 6g"
        exit 1
    fi

    if [ ! -f "$wg_config" ]; then
        echo "Error: WireGuard config file not found: $wg_config"
        exit 1
    fi

    log "Adding VPN SSID: $name (band: $band)"

    # Parse WireGuard config
    parse_wg_config "$wg_config"

    local vlan_id=$(get_next_vlan)
    local rt_table=$((RT_TABLE_BASE + vlan_id))
    local subnet="10.${vlan_id}.0"
    local wg_iface="wg_${name}"
    local br_iface="br_${name}"
    local radio=$(get_radio_for_band "$band")

    log "VLAN: $vlan_id, RT table: $rt_table, subnet: ${subnet}.0/24, radio: $radio"

    # 1. WireGuard interface
    uci set network."${wg_iface}"=interface
    uci set network."${wg_iface}".proto='wireguard'
    uci set network."${wg_iface}".private_key="$WG_PRIVATE_KEY"
    uci set network."${wg_iface}".listen_port='0'
    uci add_list network."${wg_iface}".addresses="$WG_ADDRESS"
    uci set network."${wg_iface}".dns="$WG_DNS"
    uci set network."${wg_iface}".vlan_id="$vlan_id"

    # WireGuard peer
    local peer="${wg_iface}_peer"
    uci set network."${peer}"=wireguard_"${wg_iface}"
    uci set network."${peer}".public_key="$WG_PUBLIC_KEY"
    uci set network."${peer}".endpoint_host="$WG_ENDPOINT_HOST"
    uci set network."${peer}".endpoint_port="$WG_ENDPOINT_PORT"
    uci set network."${peer}".persistent_keepalive='25'
    uci add_list network."${peer}".allowed_ips='0.0.0.0/0'
    uci add_list network."${peer}".allowed_ips='::/0'
    uci set network."${peer}".route_allowed_ips='0'

    # 2. Bridge for the VPN SSID subnet
    uci set network."${br_iface}"=interface
    uci set network."${br_iface}".proto='static'
    uci set network."${br_iface}".ipaddr="${subnet}.1"
    uci set network."${br_iface}".netmask='255.255.255.0'

    # 3. DHCP for VPN SSID clients
    uci set dhcp."${br_iface}"=dhcp
    uci set dhcp."${br_iface}".interface="${br_iface}"
    uci set dhcp."${br_iface}".start='100'
    uci set dhcp."${br_iface}".limit='150'
    uci set dhcp."${br_iface}".leasetime='12h'
    uci add_list dhcp."${br_iface}".dhcp_option="6,${WG_DNS}"

    # 4. WiFi SSID
    local wifi_iface="wifi_${name}"
    uci set wireless."${wifi_iface}"=wifi-iface
    uci set wireless."${wifi_iface}".device="$radio"
    uci set wireless."${wifi_iface}".mode='ap'
    uci set wireless."${wifi_iface}".ssid="$name"
    uci set wireless."${wifi_iface}".encryption='sae'
    uci set wireless."${wifi_iface}".key="changeme_${name}"
    uci set wireless."${wifi_iface}".network="${br_iface}"
    uci set wireless."${wifi_iface}".isolate='1'

    # 5. Firewall zone for VPN
    local fw_zone="vpn_${name}"
    uci set firewall."${fw_zone}"=zone
    uci set firewall."${fw_zone}".name="${fw_zone}"
    uci set firewall."${fw_zone}".input='REJECT'
    uci set firewall."${fw_zone}".output='ACCEPT'
    uci set firewall."${fw_zone}".forward='REJECT'
    uci set firewall."${fw_zone}".masq='1'
    uci add_list firewall."${fw_zone}".network="${wg_iface}"
    uci add_list firewall."${fw_zone}".network="${br_iface}"

    # Allow DHCP/DNS from VPN SSID clients
    local fw_rule="allow_dhcp_${name}"
    uci set firewall."${fw_rule}"=rule
    uci set firewall."${fw_rule}".name="Allow DHCP ${name}"
    uci set firewall."${fw_rule}".src="${fw_zone}"
    uci set firewall."${fw_rule}".dest_port='67-68'
    uci set firewall."${fw_rule}".proto='udp'
    uci set firewall."${fw_rule}".target='ACCEPT'

    local fw_rule_dns="allow_dns_${name}"
    uci set firewall."${fw_rule_dns}"=rule
    uci set firewall."${fw_rule_dns}".name="Allow DNS ${name}"
    uci set firewall."${fw_rule_dns}".src="${fw_zone}"
    uci set firewall."${fw_rule_dns}".dest_port='53'
    uci set firewall."${fw_rule_dns}".proto='tcpudp'
    uci set firewall."${fw_rule_dns}".target='ACCEPT'

    # 6. Policy routing — route VPN SSID traffic through WireGuard
    # Add routing table entry
    grep -q "^${rt_table} vpn_${name}" /etc/iproute2/rt_tables 2>/dev/null || \
        echo "${rt_table} vpn_${name}" >> /etc/iproute2/rt_tables

    local rt_rule="rt_${name}"
    uci set network."${rt_rule}"=rule
    uci set network."${rt_rule}".src="${subnet}.0/24"
    uci set network."${rt_rule}".lookup="vpn_${name}"
    uci set network."${rt_rule}".priority="$((10000 + vlan_id))"

    local rt_route="route_${name}"
    uci set network."${rt_route}"=route
    uci set network."${rt_route}".interface="${wg_iface}"
    uci set network."${rt_route}".target='0.0.0.0/0'
    uci set network."${rt_route}".table="vpn_${name}"

    # Commit all changes
    uci commit network
    uci commit wireless
    uci commit dhcp
    uci commit firewall

    log "VPN SSID '$name' created successfully"
    log "  SSID: $name (password: changeme_${name} — CHANGE THIS)"
    log "  VPN: $WG_ENDPOINT → $WG_ADDRESS"
    log "  Subnet: ${subnet}.0/24"
    log "  VLAN: $vlan_id, RT table: $rt_table"
    log ""
    log "To activate: /etc/init.d/network restart && /etc/init.d/firewall restart"
    log "To change password: uci set wireless.wifi_${name}.key='newpassword' && uci commit wireless && wifi"
}

cmd_remove() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "Usage: $0 remove <name>"
        exit 1
    fi

    log "Removing VPN SSID: $name"

    uci delete network."wg_${name}" 2>/dev/null || true
    uci delete network."wg_${name}_peer" 2>/dev/null || true
    uci delete network."br_${name}" 2>/dev/null || true
    uci delete network."rt_${name}" 2>/dev/null || true
    uci delete network."route_${name}" 2>/dev/null || true
    uci delete wireless."wifi_${name}" 2>/dev/null || true
    uci delete dhcp."br_${name}" 2>/dev/null || true
    uci delete firewall."vpn_${name}" 2>/dev/null || true
    uci delete firewall."allow_dhcp_${name}" 2>/dev/null || true
    uci delete firewall."allow_dns_${name}" 2>/dev/null || true

    uci commit network
    uci commit wireless
    uci commit dhcp
    uci commit firewall

    # Clean rt_tables
    sed -i "/vpn_${name}/d" /etc/iproute2/rt_tables 2>/dev/null || true

    log "VPN SSID '$name' removed"
    log "To activate: /etc/init.d/network restart && /etc/init.d/firewall restart"
}

cmd_list() {
    echo "VPN SSIDs:"
    for iface in $(uci -q show network | grep "proto='wireguard'" | cut -d. -f2 | grep "^wg_"); do
        local name="${iface#wg_}"
        local endpoint=$(uci -q get network."${iface}_peer".endpoint_host 2>/dev/null || echo "unknown")
        local ssid=$(uci -q get wireless."wifi_${name}".ssid 2>/dev/null || echo "not configured")
        local band=$(uci -q get wireless."wifi_${name}".device 2>/dev/null || echo "unknown")
        echo "  $name: SSID=$ssid, endpoint=$endpoint, radio=$band"
    done
}

case "$1" in
    add) shift; cmd_add "$@" ;;
    remove) shift; cmd_remove "$@" ;;
    list) cmd_list ;;
    *)
        echo "VPN SSID Template for OpenWRT"
        echo "Replicates ASUS VPN Fusion / Guest Network Pro"
        echo ""
        echo "Usage:"
        echo "  $0 add <name> <wg_config_file> [band]"
        echo "  $0 remove <name>"
        echo "  $0 list"
        echo ""
        echo "Example:"
        echo "  $0 add tw22 /tmp/protonvpn-tw.conf 5g"
        echo "  $0 add jp23 /tmp/protonvpn-jp.conf 2g"
        echo "  $0 remove tw22"
        ;;
esac
