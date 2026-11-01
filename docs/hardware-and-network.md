# Hardware and network

## Hosts

| Host | IP | Role |
|---|---|---|
| gateway | 10.0.0.1 / 192.168.50.200 | OpenWrt router: firewall/NAT, DHCP, DNS forwarder, NTP, WireGuard to the offsite VM ([metal/openwrt](../metal/openwrt/README.md)) |
| pimaster | 192.168.50.100 / 10.0.0.20 | Ansible control node, VM on the shared home/cluster segment ([control host](control-host.md)) |
| node1 | 10.0.0.11 | External services: bind9 (authoritative DNS), Vault, RustFS (S3), certbot, offsite backup push |
| node2–node4 | 10.0.0.12–14 | k3s control plane (embedded etcd). k3s API virtual IP 10.0.0.10 (kube-vip). node3 boots from a USB SSD and is a Longhorn storage node |
| node5 | 10.0.0.15 | k3s worker, boots from a USB SSD, Longhorn storage node |
| offsite | 10.99.0.2 (WireGuard) | Oracle Cloud VM (Always Free, Frankfurt): offsite backup copy, outside monitoring ([offsite](offsite.md)) |

Next: [Cluster 2.0](plans/cluster-2.0.md), a highly available control plane on two Pi 4 8 GB nodes (node6, node7), every node on an SSD.

## IP plan

10.0.0.0/24: .1 gateway, .10 k3s API (kube-vip), .11-.19 nodes, .20 pimaster, .64/26 Cilium LoadBalancer pool (.68 Envoy gateway), .150-.249 DHCP.

DNS domain: `homelab.yekvitka.net`, served by bind9 on node1; the gateway forwards it. external-dns publishes cluster records through RFC 2136.

## Storage

- node1, node2 and node4 boot Ubuntu 24.04 from SD card. node3 and node5 boot from a USB SSD (bootloader default `BOOT_ORDER=0xf41`: SD first, then USB, so a node boots the SSD with no SD card inserted).
- node1 SSD: `/storage` for RustFS and Vault data (formatted by cloud-init, mounted by label `DATA`).
- Longhorn uses `/storage` on each node's own disk, created by cloud-init. It runs only on the SSD nodes, labeled `node_storage=longhorn` (`k3s_longhorn_storage: true` in host_vars). One replica per volume: no redundancy, Velero backs the volumes up daily.
- The USB-SATA adapters (Realtek RTL9201) time out with UAS under write load: UAS is disabled with `rpi_usb_storage_quirks` (`ansible/host_vars/node1.yml`, `node5.yml`). node3's adapter (Initio, `13fd:5917`) runs UAS without a quirk.

The centralized iSCSI SAN (node1 serving one LUN per k3s node) is disabled (`centralized_san: false`): Longhorn on iSCSI over a single USB SSD stalled the nodes. `ansible/configure_centralized_san.yml` and `ansible/vars/centralized_san/` are kept, not part of upstream.
