#!/bin/sh
# WireGuard tunnel from the gateway to the Oracle Cloud VM (terraform/oci):
# offsite backups and outside monitoring. The gateway has a dynamic public IP
# (behind the home router), so it connects out and keeps the tunnel up: no port
# forwarding on either router.
#
# Run on the gateway as root. Safe to re-run, no reboot.
#   1. sh wireguard-oci.sh
#      installs WireGuard, creates the gateway key (kept on the gateway) and
#      prints its public key (gateway_wg_public_key in terraform/oci)
#   2. OCI_ENDPOINT=<offsite_public_ip> OCI_PUBKEY=<VM public key> sh wireguard-oci.sh
#      adds the VM as peer
set -e

WG_ADDR=10.99.0.1/24
OCI_WG_IP=10.99.0.2
OCI_PORT=51820
# Home uplink path MTU 1460 minus 80 bytes of WireGuard overhead
MTU=1380
# Home network (wan side): may SSH to the VM
HOME_NET=192.168.50.0/24

command -v wg >/dev/null || { apk update && apk add wireguard-tools kmod-wireguard luci-proto-wireguard; }
# netifd loads protocol handlers when it starts: restart it once after the install
ubus call network get_proto_handlers | grep -q '"wireguard"' || /etc/init.d/network restart

KEY=$(uci -q get network.wg_oci.private_key || true)
[ -n "$KEY" ] || KEY=$(wg genkey)

uci set network.wg_oci=interface
uci set network.wg_oci.proto='wireguard'
uci set network.wg_oci.private_key="$KEY"
uci set network.wg_oci.mtu="$MTU"
uci -q delete network.wg_oci.addresses || true
uci add_list network.wg_oci.addresses="$WG_ADDR"

if [ -n "$OCI_ENDPOINT" ] && [ -n "$OCI_PUBKEY" ]; then
  uci -q delete network.oci_vm || true
  uci set network.oci_vm=wireguard_wg_oci
  uci set network.oci_vm.description='Oracle Cloud VM (offsite)'
  uci set network.oci_vm.public_key="$OCI_PUBKEY"
  uci set network.oci_vm.endpoint_host="$OCI_ENDPOINT"
  uci set network.oci_vm.endpoint_port="$OCI_PORT"
  uci set network.oci_vm.persistent_keepalive='25'
  uci set network.oci_vm.route_allowed_ips='1'
  uci add_list network.oci_vm.allowed_ips="$OCI_WG_IP/32"
fi

# Zone for the tunnel: nothing from the VM into home networks (rules added
# per service later), cluster LAN and home network may reach the VM
uci -q delete firewall.oci || true
uci set firewall.oci=zone
uci set firewall.oci.name='oci'
uci set firewall.oci.network='wg_oci'
uci set firewall.oci.input='REJECT'
uci set firewall.oci.output='ACCEPT'
uci set firewall.oci.forward='REJECT'
uci set firewall.oci.mtu_fix='1'

uci -q delete firewall.lan_oci || true
uci set firewall.lan_oci=forwarding
uci set firewall.lan_oci.src='lan'
uci set firewall.lan_oci.dest='oci'

uci -q delete firewall.home_ssh_oci || true
uci set firewall.home_ssh_oci=rule
uci set firewall.home_ssh_oci.name='Allow-Home-SSH-OCI'
uci set firewall.home_ssh_oci.src='wan'
uci set firewall.home_ssh_oci.src_ip="$HOME_NET"
uci set firewall.home_ssh_oci.dest='oci'
uci set firewall.home_ssh_oci.dest_ip="$OCI_WG_IP"
uci set firewall.home_ssh_oci.proto='tcp'
uci set firewall.home_ssh_oci.dest_port='22'
uci set firewall.home_ssh_oci.target='ACCEPT'

# Outside monitoring (Gatus on the VM, ansible/offsite_monitoring.yml): only
# these targets, only from the VM. Arguments: name, destination, protocol, port
monitoring_rule() {
  uci -q delete "firewall.$1" || true
  uci set "firewall.$1=rule"
  uci set "firewall.$1.name=Allow-OCI-Monitoring-$1"
  uci set "firewall.$1.src=oci"
  uci set "firewall.$1.src_ip=$OCI_WG_IP"
  uci set "firewall.$1.dest=lan"
  uci set "firewall.$1.dest_ip=$2"
  uci set "firewall.$1.proto=$3"
  uci set "firewall.$1.dest_port=$4"
  uci set "firewall.$1.target=ACCEPT"
}
monitoring_rule mon_dns 10.0.0.11 'tcp udp' 53      # bind9 (names for the checks)
monitoring_rule mon_grafana 10.0.0.68 tcp 443       # Envoy gateway (Grafana)
monitoring_rule mon_k3s 10.0.0.10 tcp 6443          # k3s API (kube-vip)
monitoring_rule mon_vault 10.0.0.11 tcp 8200        # Vault
monitoring_rule mon_rustfs 10.0.0.11 tcp 9091       # RustFS S3

uci commit network
uci commit firewall
ifup wg_oci
/etc/init.d/firewall reload

echo "gateway WireGuard public key: $(echo "$KEY" | wg pubkey)"
