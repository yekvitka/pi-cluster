# OpenWrt gateway

The cluster gateway is a Raspberry Pi running OpenWrt. It is not managed by Ansible.

| Interface | Port | Address | Network |
|---|---|---|---|
| LAN (`br-lan`) | eth0 → cluster switch | 10.0.0.1/24 | cluster LAN |
| WAN (`wwan`) | built-in Wi-Fi (client) | 192.168.50.200/24 | home network |

Services provided by the gateway:

- Routing, firewall and NAT (cluster LAN → home network)
- DHCP for 10.0.0.0/24: static leases for node1–node5, dynamic pool 10.0.0.150–10.0.0.249 (10.0.0.64/26 is reserved for Kubernetes LoadBalancer IPs, 10.0.0.10 for the k3s API)
- DNS forwarder: `homelab.yekvitka.com` and `0.10.in-addr.arpa` go to bind9 on node1 (10.0.0.11), everything else to 1.1.1.1 / 8.8.8.8
- NTP server on the LAN

Everything else runs on node1 (bind9, Vault, RustFS S3, iSCSI SAN). The k3s API is the kube-vip virtual IP 10.0.0.10 on node2–node4.

## Install

1. Download the OpenWrt factory image for Raspberry Pi 4 (`bcm27xx/bcm2711`) from https://firmware-selector.openwrt.org and write it to the SD card or USB disk.
2. Boot the Pi with eth0 connected to a laptop and open http://192.168.1.1. Set a root password.
3. Add the pimaster public key to `/etc/dropbear/authorized_keys` (System → Administration → SSH-Keys). The setup script disables password login once a key is present.
4. Copy and run the setup script:

   ```shell
   scp -O metal/openwrt/gateway-setup.sh root@192.168.1.1:/tmp/
   ssh root@192.168.1.1 "WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>' sh /tmp/gateway-setup.sh"
   ```

   Optional overrides: `HOME_ROUTER` (default 192.168.50.1), `HOME_NET`, `WAN_IP`, `WIFI_COUNTRY` (default PL).

5. The gateway reboots. Move eth0 to the cluster switch. It is now reachable at 10.0.0.1 and 192.168.50.200.

## Firewall

Default zones are kept: `lan → wan` accepted and masqueraded, `wan → lan` rejected. These rules allow traffic from the home network (192.168.50.0/24) only:

| Rule | Destination | Ports |
|---|---|---|
| `allow_wan_ssh`, `allow_wan_luci`, `allow_wan_dns` | gateway | 22, 443, 53 |
| `allow_wan_lan_ssh` | cluster LAN | 22 (Ansible from pimaster) |
| `allow_wan_lan_web` | cluster LAN | 80, 443 (ingress) |
| `allow_wan_k3s_api` | 10.0.0.10 | 6443 (kube-vip → k3s API) |
| `allow_wan_vault` | node1 | 8200 |
| `allow_wan_rustfs` | node1 | 9091, 9092 (RustFS API, console) |

## pimaster and home network access

Traffic from the home network is routed, not NATed, so pimaster needs a route to the cluster LAN through the gateway. Add it on the home router (all home devices), or on pimaster only:

```shell
# pimaster (netplan), under the home network interface
routes:
  - to: 10.0.0.0/24
    via: 192.168.50.200
```

To resolve cluster names from pimaster, use the gateway (192.168.50.200) as DNS server for `homelab.yekvitka.com`.

## Static leases

Nodes configure their static IPs in cloud-init (`metal/rpi/cloud-init/nodes/network-config`). The DHCP static leases bound to the MAC addresses in `ansible/inventory.yml` keep those addresses reserved. When a node or MAC changes, update both the inventory and `gateway-setup.sh`, then re-run the script.

## LuCI TLS certificate

`make openwrt-certbot-tls` (repo root) requests a Let's Encrypt certificate for `gateway.homelab.yekvitka.com` and deploys it with `script/openwrt-deploy-tls.sh`.
