#!/bin/sh
# OpenWrt gateway configuration for the pi-cluster
#
# Run on the gateway (Raspberry Pi with OpenWrt) as root:
#   WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>' sh gateway-setup.sh
#
# Safe to re-run: every section it manages is named and recreated.
# The gateway reboots at the end and comes back on 10.0.0.1 (LAN) and
# 192.168.50.200 (WAN, home Wi-Fi).

set -e

: "${WIFI_SSID:?set WIFI_SSID}"
: "${WIFI_KEY:?set WIFI_KEY}"

WIFI_COUNTRY="${WIFI_COUNTRY:-PL}"
# Band of the home access point (2g, 5g)
WIFI_BAND="${WIFI_BAND:-5g}"
# 0: no DHCP server on the LAN. eth0 shares the segment with the home network,
# a second DHCP server would answer home devices. Nodes use static IPs.
LAN_DHCP="${LAN_DHCP:-0}"
# 1: do not reboot at the end (first boot from /etc/uci-defaults)
NO_REBOOT="${NO_REBOOT:-0}"
HOME_NET="${HOME_NET:-192.168.50.0/24}"
HOME_ROUTER="${HOME_ROUTER:-192.168.50.1}"
WAN_IP="${WAN_IP:-192.168.50.200}"
LAN_IP="10.0.0.1"
DOMAIN="homelab.yekvitka.com"
# node1: bind9 (authoritative DNS), Vault, RustFS (S3)
NODE1="10.0.0.11"
# k3s API virtual IP (kube-vip on node2-node4)
K3S_API_VIP="10.0.0.10"

########################
# System
########################
uci set system.@system[0].hostname='gateway'
uci set system.@system[0].zonename='Europe/Warsaw'
uci set system.@system[0].timezone='CET-1CEST,M3.5.0,M10.5.0/3'

# NTP server for the cluster LAN only
uci set system.ntp.enabled='1'
uci set system.ntp.enable_server='1'
uci set system.ntp.interface='lan'

# No RTC on the Pi: keep a recent timestamp so the clock restarts close to real time
grep -q keepingtime /etc/crontabs/root 2>/dev/null || \
  echo '*/5 * * * * touch /etc/keepingtime' >> /etc/crontabs/root

########################
# Network
########################
# LAN: eth0 (br-lan) -> cluster switch
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask='255.255.255.0'

# WAN: built-in Wi-Fi as client of the home network
uci -q delete network.wwan || true
uci set network.wwan=interface
uci set network.wwan.proto='static'
uci set network.wwan.ipaddr="$WAN_IP"
uci set network.wwan.netmask='255.255.255.0'
uci set network.wwan.gateway="$HOME_ROUTER"

# On first boot the radio can show up after uci-defaults start: wait for it
if ! uci -q get wireless.radio0 >/dev/null; then
  i=0
  while [ $i -lt 30 ] && [ -z "$(ls /sys/class/ieee80211/ 2>/dev/null)" ]; do
    sleep 1
    i=$((i + 1))
  done
  wifi config || true
fi

if uci -q get wireless.radio0 >/dev/null; then
  uci set wireless.radio0.disabled='0'
  uci set wireless.radio0.country="$WIFI_COUNTRY"
  uci set wireless.radio0.band="$WIFI_BAND"
  uci set wireless.radio0.channel='auto'
  # Remove the default access point, the radio is used only as uplink
  uci -q delete wireless.default_radio0 || true
  uci -q delete wireless.wwan || true
  uci set wireless.wwan=wifi-iface
  uci set wireless.wwan.device='radio0'
  uci set wireless.wwan.mode='sta'
  uci set wireless.wwan.network='wwan'
  uci set wireless.wwan.ssid="$WIFI_SSID"
  uci set wireless.wwan.encryption='psk2'
  uci set wireless.wwan.key="$WIFI_KEY"
else
  # The rest still applies: the gateway stays reachable on the LAN (10.0.0.1)
  echo "WARNING: radio0 not found, Wi-Fi uplink not configured. Re-run this script." >&2
  logger -t gateway-setup "radio0 not found, Wi-Fi uplink not configured"
fi

########################
# DHCP / DNS (dnsmasq)
########################
uci set dhcp.@dnsmasq[0].domain="$DOMAIN"
# Do not answer the homelab domain locally: forward it to bind9 on node1
uci -q delete dhcp.@dnsmasq[0].local || true
uci -q delete dhcp.@dnsmasq[0].server || true
uci add_list dhcp.@dnsmasq[0].server="/$DOMAIN/$NODE1"
uci add_list dhcp.@dnsmasq[0].server="/0.10.in-addr.arpa/$NODE1"
uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
uci set dhcp.@dnsmasq[0].noresolv='1'
# Rebind protection would drop private IPs returned for the homelab domain
uci -q delete dhcp.@dnsmasq[0].rebind_domain || true
uci add_list dhcp.@dnsmasq[0].rebind_domain="$DOMAIN"
# Also answer queries from the home network (pimaster), filtered by firewall
uci set dhcp.@dnsmasq[0].localservice='0'

# Dynamic pool 10.0.0.150-249. 10.0.0.64/26 is the Cilium LoadBalancer IP pool
uci set dhcp.lan.start='150'
uci set dhcp.lan.limit='100'
uci set dhcp.lan.leasetime='12h'
if [ "$LAN_DHCP" = "1" ]; then
  uci -q delete dhcp.lan.ignore || true
else
  uci set dhcp.lan.ignore='1'
fi
uci set dhcp.lan.dhcpv4='server'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ra='disabled'

# Static leases: nodes set the same static IPs in cloud-init network-config,
# leases keep the addresses reserved. Keep in sync with ansible/inventory.yml
static_lease() {
  uci -q delete dhcp."$1" || true
  uci set dhcp."$1"=host
  uci set dhcp."$1".name="$1"
  uci set dhcp."$1".mac="$2"
  uci set dhcp."$1".ip="$3"
}
# eth0 MACs (wlan0 is eth0 + 1)
static_lease node1 D8:3A:DD:3B:47:07 10.0.0.11
static_lease node2 D8:3A:DD:3B:46:EC 10.0.0.12
static_lease node3 D8:3A:DD:D4:99:81 10.0.0.13
static_lease node4 D8:3A:DD:D4:8E:FB 10.0.0.14
static_lease node5 D8:3A:DD:3B:47:2E 10.0.0.15

########################
# Firewall
########################
# Attach Wi-Fi uplink to the default wan zone (masquerading lan -> wan)
WAN_ZONE=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'\$/\1/p")
uci -q del_list firewall."$WAN_ZONE".network='wwan' || true
uci add_list firewall."$WAN_ZONE".network='wwan'

# Allow traffic from the home network: $1 id, $2 protocol, $3 ports,
# $4 destination ip in the cluster LAN (empty: the gateway itself)
fw_rule() {
  uci -q delete firewall."$1" || true
  uci set firewall."$1"=rule
  uci set firewall."$1".name="$1"
  uci set firewall."$1".src='wan'
  uci set firewall."$1".src_ip="$HOME_NET"
  uci set firewall."$1".proto="$2"
  uci set firewall."$1".dest_port="$3"
  if [ -n "$4" ]; then
    uci set firewall."$1".dest='lan'
    [ "$4" = "any" ] || uci set firewall."$1".dest_ip="$4"
  fi
  uci set firewall."$1".target='ACCEPT'
}
# Gateway services
fw_rule allow_wan_ssh tcp 22
fw_rule allow_wan_luci tcp 443
fw_rule allow_wan_dns tcpudp 53
# Cluster LAN services
fw_rule allow_wan_lan_ssh tcp 22 any
fw_rule allow_wan_lan_web tcp '80 443' any
fw_rule allow_wan_k3s_api tcp 6443 "$K3S_API_VIP"
fw_rule allow_wan_vault tcp 8200 "$NODE1"
fw_rule allow_wan_rustfs tcp '9091 9092' "$NODE1"

########################
# SSH: key only, once a key is installed
########################
if [ -s /etc/dropbear/authorized_keys ]; then
  uci set dropbear.@dropbear[0].PasswordAuth='off'
  uci set dropbear.@dropbear[0].RootPasswordAuth='off'
fi

uci commit
[ "$NO_REBOOT" = "1" ] && exit 0
echo "Configuration committed. Rebooting: reconnect at $LAN_IP or $WAN_IP"
reboot
