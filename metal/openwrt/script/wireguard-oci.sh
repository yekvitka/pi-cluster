#!/bin/sh
# WireGuard tunnel from the gateway to the Oracle Cloud VMs (terraform/oci):
# offsite (backups, outside monitoring) and, optionally, pimaster (the control
# host and the hub for remote access clients). The gateway has a dynamic public
# IP (behind the home router), so it connects out to each VM and keeps the
# tunnel up: no port forwarding on either router.
#
# Run on the gateway as root. Safe to re-run, no reboot.
#   1. sh wireguard-oci.sh
#      installs WireGuard, creates the gateway key (kept on the gateway) and
#      prints its public key (gateway_wg_public_key in terraform/oci)
#   2. OCI_ENDPOINT=<offsite_public_ip> OCI_PUBKEY=<offsite public key> sh wireguard-oci.sh
#      PIMASTER_ENDPOINT=<pimaster_public_ip> PIMASTER_PUBKEY=<pimaster public key> sh wireguard-oci.sh
#      add the VMs as peers. Later runs keep a peer whose variables are not set
set -e

WG_ADDR=10.99.0.1/24
OCI_WG_IP=10.99.0.2
PIMASTER_WG_IP=10.99.0.3
# Remote access clients (laptop, phone): they connect to pimaster, which
# forwards them through this tunnel. Same access as pimaster (ctl_* rules)
REMOTE_NET=10.99.0.16/28
OCI_PORT=51820
# Home uplink path MTU 1460 minus 80 bytes of WireGuard overhead
MTU=1380
# Home network (wan side): may SSH to the VM
HOME_NET=192.168.50.0/24

OCI_ENDPOINT=${OCI_ENDPOINT:-$(uci -q get network.oci_vm.endpoint_host || true)}
OCI_PUBKEY=${OCI_PUBKEY:-$(uci -q get network.oci_vm.public_key || true)}
PIMASTER_ENDPOINT=${PIMASTER_ENDPOINT:-$(uci -q get network.pimaster_vm.endpoint_host || true)}
PIMASTER_PUBKEY=${PIMASTER_PUBKEY:-$(uci -q get network.pimaster_vm.public_key || true)}

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

# Arguments: uci section, description, endpoint, public key, allowed IPs...
wg_peer() {
  section=$1 description=$2 endpoint=$3 pubkey=$4
  shift 4
  if [ -z "$endpoint" ] || [ -z "$pubkey" ]; then
    return 0
  fi
  uci -q delete "network.$section" || true
  uci set "network.$section=wireguard_wg_oci"
  uci set "network.$section.description=$description"
  uci set "network.$section.public_key=$pubkey"
  uci set "network.$section.endpoint_host=$endpoint"
  uci set "network.$section.endpoint_port=$OCI_PORT"
  uci set "network.$section.persistent_keepalive=25"
  uci set "network.$section.route_allowed_ips=1"
  for ip in "$@"; do
    uci add_list "network.$section.allowed_ips=$ip"
  done
}
wg_peer oci_vm 'Oracle Cloud VM (offsite)' "$OCI_ENDPOINT" "$OCI_PUBKEY" "$OCI_WG_IP/32"
wg_peer pimaster_vm 'Oracle Cloud VM (pimaster)' "$PIMASTER_ENDPOINT" "$PIMASTER_PUBKEY" "$PIMASTER_WG_IP/32" "$REMOTE_NET"

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

# Home network to the VM: SSH and the Gatus UI (ansible/offsite_monitoring.yml)
uci -q delete firewall.home_ssh_oci || true
uci -q delete firewall.home_oci || true
uci set firewall.home_oci=rule
uci set firewall.home_oci.name='Allow-Home-OCI'
uci set firewall.home_oci.src='wan'
uci set firewall.home_oci.src_ip="$HOME_NET"
uci set firewall.home_oci.dest='oci'
uci set firewall.home_oci.dest_ip="$OCI_WG_IP"
uci set firewall.home_oci.proto='tcp'
uci set firewall.home_oci.dest_port='22 8080'
uci set firewall.home_oci.target='ACCEPT'

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

# LuCI on the gateway itself (certificate expiry check): input rule, no dest
uci -q delete firewall.mon_luci || true
uci set firewall.mon_luci=rule
uci set firewall.mon_luci.name='Allow-OCI-Monitoring-mon_luci'
uci set firewall.mon_luci.src='oci'
uci set firewall.mon_luci.src_ip="$OCI_WG_IP"
uci set firewall.mon_luci.proto='tcp'
uci set firewall.mon_luci.dest_port='443'
uci set firewall.mon_luci.target='ACCEPT'

# pimaster and its remote access clients: the same rules as the home network
# (gateway-setup.sh fw_rule). Arguments: name, protocol, ports, destination in
# the cluster LAN ("any": the whole LAN, empty: the gateway itself)
ctl_rule() {
  uci -q delete "firewall.$1" || true
  uci set "firewall.$1=rule"
  uci set "firewall.$1.name=Allow-OCI-Control-$1"
  uci set "firewall.$1.src=oci"
  uci add_list "firewall.$1.src_ip=$PIMASTER_WG_IP"
  uci add_list "firewall.$1.src_ip=$REMOTE_NET"
  uci set "firewall.$1.proto=$2"
  uci set "firewall.$1.dest_port=$3"
  if [ -n "$4" ]; then
    uci set "firewall.$1.dest=lan"
    [ "$4" = "any" ] || uci set "firewall.$1.dest_ip=$4"
  fi
  uci set "firewall.$1.target=ACCEPT"
}
ctl_rule ctl_ssh tcp 22                         # gateway
ctl_rule ctl_luci tcp 443
ctl_rule ctl_dns tcpudp 53
ctl_rule ctl_lan_ssh tcp 22 any                 # Ansible, SSH to the nodes
ctl_rule ctl_lan_web tcp '80 443' any           # Envoy gateway (web UIs)
ctl_rule ctl_k3s_api tcp 6443 10.0.0.10         # k3s API (kube-vip)
ctl_rule ctl_vault tcp 8200 10.0.0.11           # Vault
ctl_rule ctl_rustfs tcp '9091 9092' 10.0.0.11   # RustFS API, console

# Rules of the earlier remote access through the offsite VM: the ctl_* rules
# replace them
for rule in remote_ssh remote_luci remote_dns remote_lan_ssh remote_lan_web remote_k3s_api remote_vault remote_rustfs; do
  uci -q delete "firewall.$rule" || true
done

uci commit network
uci commit firewall
ifup wg_oci
/etc/init.d/firewall reload

echo "gateway WireGuard public key: $(echo "$KEY" | wg pubkey)"
