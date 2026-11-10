# Hardware and network

## Hosts

| Host | IP | Role |
|---|---|---|
| gateway | 10.0.0.1 / 192.168.50.200 | OpenWrt router: firewall/NAT, DHCP, DNS forwarder, NTP, WireGuard to the Oracle Cloud VMs ([metal/openwrt](../metal/openwrt/README.md)) |
| pimaster | 10.99.0.3 (WireGuard) | Control host: Ansible runner, secrets, Terraform state. Oracle Cloud VM (Always Free, Frankfurt) ([control host](control-host.md)) |
| node1 | 10.0.0.11 | External services: bind9 (authoritative DNS), Vault, RustFS (S3), certbot, offsite backup push |
| node2, node3 | 10.0.0.12–13 | k3s etcd-only servers (no API server). node3 boots from a USB SSD and is a Longhorn storage node |
| node4 | 10.0.0.14 | k3s worker, boots from SD card, no Longhorn |
| node5 | 10.0.0.15 | k3s worker, boots from a USB SSD, Longhorn storage node |
| node6 | 10.0.0.16 | Pi 4 8 GB, boots from a USB SSD. The only k3s API server (+ etcd), tainted. k3s API virtual IP 10.0.0.10 (kube-vip). |
| offsite | 10.99.0.2 (WireGuard) | Oracle Cloud VM (Always Free, Frankfurt): offsite backup copy, outside monitoring ([offsite](offsite.md)) |

[Cluster 2.0](plans/cluster-2.0.md): this node layout runs since 2026-11-06, with Loki, Tempo, Rancher and Hubble on it. Istio was removed on 2026-11-07: node6 has no CPU left for it.

## IP plan

10.0.0.0/24: .1 gateway, .10 k3s API (kube-vip), .11-.19 nodes, .64/26 Cilium LoadBalancer pool (.68 Envoy gateway), .150-.249 DHCP.

10.99.0.0/24 (WireGuard, the gateway dials out to both VMs): .1 gateway, .2 offsite, .3 pimaster, .16/28 remote clients of pimaster (laptop .18, phone .19).

Ansible logs in to the nodes as `ansible` (passwordless sudo); no node accepts root SSH ([access](control-host.md#access-to-the-hosts)).

DNS domain: `homelab.yekvitka.net`, served by bind9 on node1; the gateway forwards it. external-dns publishes cluster records through RFC 2136.

## Storage

- node1, node2 and node4 boot Ubuntu 24.04 from SD card. node3, node5 and node6 boot from a USB SSD (bootloader default `BOOT_ORDER=0xf41`: SD first, then USB, so a node boots the SSD with no SD card inserted).
- node1 SSD: `/storage` for RustFS and Vault data (formatted by cloud-init, mounted by label `DATA`).
- Longhorn uses `/storage` on each node's own disk, created by cloud-init. It runs only on the SSD nodes, labeled `node_storage=longhorn` (`k3s_longhorn_storage: true` in host_vars). One replica per volume: no redundancy, Velero backs the volumes up daily. Stale replica data left on a node (Longhorn orphans) is deleted automatically after 5 minutes.
- The USB-SATA adapters (Realtek RTL9201) time out with UAS under write load: UAS is disabled with `rpi_usb_storage_quirks` (`ansible/host_vars/node1.yml`, `node5.yml`). node3's and node6's adapters (Initio, `13fd:5917`) run UAS without a quirk.
