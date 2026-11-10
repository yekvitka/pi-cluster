# OpenWrt gateway

The cluster gateway is a Raspberry Pi running OpenWrt. It is not managed by Ansible.

| Interface | Port | Address | Network |
|---|---|---|---|
| LAN (`br-lan`) | eth0 → switch (shared with the home network) | 10.0.0.1/24 | cluster LAN |
| WAN (`wwan`) | built-in Wi-Fi (client) | 192.168.50.200/24 | home network |

Services provided by the gateway:

- Routing, firewall and NAT (cluster LAN → home network)
- DHCP for 10.0.0.0/24: disabled by default (`LAN_DHCP=0`). The cluster LAN and the home network share one switch, so a second DHCP server would answer home devices; nodes use static IPs. With `LAN_DHCP=1` (dedicated cluster switch): static leases for node1–node6, dynamic pool 10.0.0.150–10.0.0.249 (10.0.0.64/26 is reserved for Kubernetes LoadBalancer IPs, 10.0.0.10 for the k3s API)
- DNS forwarder: `homelab.yekvitka.net` and `0.10.in-addr.arpa` go to bind9 on node1 (10.0.0.11), everything else to 1.1.1.1 / 8.8.8.8
- NTP server on the LAN
- Prometheus node exporter on the LAN interface (`script/node-exporter.sh`)

Everything else runs on node1 (bind9, Vault, RustFS S3). The k3s API is the kube-vip virtual IP 10.0.0.10 on node2–node4.

## Install

### Preconfigured image (recommended)

`build-image.sh` downloads the official OpenWrt image (default 25.12.6), verifies it and adds `gateway-setup.sh` as a first-boot script, the pimaster SSH key and a root password (generated in `~/.secrets/openwrt-root-password`, needed for LuCI). The gateway boots directly on 10.0.0.1 and 192.168.50.200.

```shell
sudo WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>' metal/openwrt/build-image.sh
```

Write `metal/openwrt/img/openwrt-<version>-gateway.img` to the SD card with dd or Raspberry Pi Imager. If the Pi already runs Linux with root SSH, `flash-remote.sh` overwrites its SD card in place and reboots it (destructive):

```shell
metal/openwrt/flash-remote.sh root@192.168.50.200 metal/openwrt/img/openwrt-25.12.6-gateway.img
```

If the Wi-Fi radio is not ready on first boot, the uplink is skipped (`logread | grep gateway-setup`) while the LAN side is configured: connect at 10.0.0.1 and re-run `gateway-setup.sh`.

### Manual

1. Download the OpenWrt factory image for Raspberry Pi 4 (`bcm27xx/bcm2711`) from https://firmware-selector.openwrt.org and write it to the SD card or USB disk.
2. Boot the Pi with eth0 connected to a laptop and open http://192.168.1.1. Set a root password.
3. Add the pimaster public key to `/etc/dropbear/authorized_keys` (System → Administration → SSH-Keys). The setup script disables password login once a key is present.
4. Copy and run the setup script:

   ```shell
   scp -O metal/openwrt/gateway-setup.sh root@192.168.1.1:/tmp/
   ssh root@192.168.1.1 "DOMAIN='<dns_domain>' WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>' sh /tmp/gateway-setup.sh"
   ```

   `DOMAIN` is `dns_domain` from `ansible/group_vars/all.yml` (`build-image.sh` reads it on its own). Optional overrides: `HOME_ROUTER` (default 192.168.50.1), `HOME_NET`, `WAN_IP`, `WIFI_COUNTRY` (default PL), `WIFI_BAND` (default 5g), `LAN_DHCP` (default 0), `ZONENAME` and `TIMEZONE` (default Europe/Warsaw).

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

pimaster sits on the shared segment with a cluster LAN address (10.0.0.20) and uses the gateway (10.0.0.1) as DNS server: see [pimaster](../../docs/control-host.md).

Other home devices reach the cluster through the gateway. Traffic from the home network is routed, not NATed, so they need a route to the cluster LAN. Add it on the home router (all home devices), or per device:

```shell
# netplan, under the home network interface
routes:
  - to: 10.0.0.0/24
    via: 192.168.50.200
```

To resolve cluster names, use the gateway (192.168.50.200) as DNS server for `homelab.yekvitka.net`.

## Static leases

Nodes configure their static IPs in cloud-init (`metal/rpi/cloud-init/nodes/network-config`). The DHCP static leases bound to the MAC addresses in `ansible/inventory.yml` keep those addresses reserved. When a node or MAC changes, update both the inventory and `gateway-setup.sh`, then re-run the script.

## WireGuard tunnel to the Oracle Cloud VMs

`script/wireguard-oci.sh` connects the gateway (10.99.0.1) to the VMs in Oracle Cloud (`terraform/oci`): the offsite VM (10.99.0.2) and, optionally, the control host pimaster (10.99.0.3, with its remote access clients 10.99.0.16/28). The gateway initiates the tunnel to each VM and keeps it up (keepalive 25s), so the dynamic home IP needs no port forwarding. MTU 1380 (home uplink path MTU 1460). The gateway private key stays on the gateway (`/etc/config/network`).

```shell
ssh root@10.0.0.1 'sh -s' < metal/openwrt/script/wireguard-oci.sh    # 1. install, print the gateway public key
ssh root@10.0.0.1 "OCI_ENDPOINT=<offsite_public_ip> OCI_PUBKEY=<offsite public key> sh -s" < metal/openwrt/script/wireguard-oci.sh   # 2. add the offsite peer
ssh root@10.0.0.1 "PIMASTER_ENDPOINT=<pimaster_public_ip> PIMASTER_PUBKEY=<pimaster public key> sh -s" < metal/openwrt/script/wireguard-oci.sh   # 3. optional: add the pimaster peer
```

Re-runs keep each peer whose variables are not set.

Firewall zone `oci`:

- Input and forward are rejected, and `lan` → `oci` is allowed.
- From the home network (192.168.50.0/24), SSH and the Gatus UI (tcp 22, 8080) to the offsite VM are allowed.
- From the offsite VM into the cluster LAN, only the outside monitoring targets are allowed (`mon_*` rules): bind9 10.0.0.11:53, Envoy gateway 10.0.0.68:443, k3s API 10.0.0.10:6443, Vault 10.0.0.11:8200, RustFS 10.0.0.11:9091.
- pimaster and its clients get the home network's access (`ctl_*` rules): SSH, LuCI and DNS on the gateway; SSH and web to the LAN; the k3s API; Vault; RustFS.

The first install restarts netifd once (it loads protocol handlers at start), a few seconds without uplink.

## Node exporter

`script/node-exporter.sh` installs the Lua node exporter (base metrics, board info, Wi-Fi uplink, network stats, SoC temperature, filesystems) and binds it to the LAN interface on port 9100: kube-prometheus-stack scrapes `gateway.homelab.yekvitka.net:9100`, the home network cannot reach it. Safe to re-run.

```shell
ssh root@10.0.0.1 'sh -s' < metal/openwrt/script/node-exporter.sh
```

## LuCI TLS certificate

`make openwrt-certbot-tls` (repo root, as `pimaster`) requests a Let's Encrypt certificate for `gateway.homelab.yekvitka.net` (IONOS DNS-01) and deploys it with `script/openwrt-deploy-tls.sh` to `root@10.0.0.1` (`REMOTE_HOST` overrides it). Renewal is automatic since `make configure-cert-renewal`: certbot on node1 renews it and pushes it to the gateway (`script/luci-cert-receiver.sh`, see [docs/certificates.md](../../docs/certificates.md)); this target is only needed for a first install.
