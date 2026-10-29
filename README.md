# Pi Cluster

Homelab K3s cluster on Raspberry Pis, automated with Ansible and FluxCD.

Fork of [ricsanfre/pi-cluster](https://github.com/ricsanfre/pi-cluster). Architecture, playbooks and Flux layout follow upstream; see the upstream documentation at https://picluster.ricsanfre.com for how each component works. This README covers only what differs here.

## Hardware and roles

| Host | IP | Role |
|---|---|---|
| gateway | 10.0.0.1 / 192.168.50.200 | OpenWrt router: firewall/NAT, DHCP, DNS forwarder, NTP ([metal/openwrt](metal/openwrt/README.md)) |
| pimaster | 192.168.50.100 / 10.0.0.16 | Ansible control node (VM on the shared home/cluster segment, see [pimaster](#pimaster-control-host)) |
| node1 | 10.0.0.11 | External services: bind9 (authoritative DNS), Vault, RustFS (S3) |
| node2–node4 | 10.0.0.12–14 | K3s control plane (embedded etcd). k3s API virtual IP 10.0.0.10 (kube-vip) |
| node5 | 10.0.0.15 | K3s worker, boots from a USB SSD |

DNS domain: `homelab.yekvitka.net` (Let's Encrypt certificates via IONOS DNS-01).

### Storage

- node1–node4 boot Ubuntu 24.04 from SD card. node5 boots from a USB SSD.
- node1 SSD: `/storage` for RustFS and Vault data (formatted by cloud-init, mounted by label `DATA`).
- Longhorn uses `/storage` on each node's own disk, created by cloud-init. With the control plane tainted, node5's SSD is the only Longhorn disk (one replica per volume).
- The USB-SATA adapters (Realtek RTL9201) time out with UAS under write load: UAS is disabled with `rpi_usb_storage_quirks` (`ansible/host_vars/node1.yml`, `node5.yml`).

The centralized iSCSI SAN (node1 serving one LUN per k3s node) is disabled (`centralized_san: false`): Longhorn on iSCSI over a single USB SSD stalled the nodes. `ansible/configure_centralized_san.yml` and `ansible/vars/centralized_san/` are kept, not part of upstream.

## Differences from upstream

- 5 Raspberry Pis + OpenWrt gateway; no x86 nodes, no PXE server.
- BCM2835 hardware watchdog enabled on every Pi (`rpi_watchdog_sec`, basic_setup role): a hung node reboots itself.
- Optional centralized iSCSI SAN on node1, disabled (above).
- Ansible connects as `root`; SSH key from `metal/rpi/cloud-init/root.pub`.
- Rancher available as a Flux platform app (`kubernetes/platform/rancher`), not enabled in prod (see Known limits).
- k3s held on 1.36.x: Rancher 2.15 supports Kubernetes < 1.37 (`.github/renovate.json5`).
- Only core and monitoring platform apps are enabled in `kubernetes/clusters/prod/infra/kustomization.yaml`. The other upstream apps stay in `kubernetes/platform/` and can be re-enabled there.
- Sized for 4 GB Raspberry Pis with a single worker: node2 keeps the control plane `NoSchedule` taint (etcd only), node3 and node4 also run light, stateless workloads (`k3s_control_plane_taint: false` in their host_vars). Longhorn runs on workers only (`node_type=worker`), so pods with Longhorn volumes (Prometheus, Alertmanager, Grafana) are pinned to node5. The kubelet reserves memory for k3s and the OS (`k3s_kubelet_config`: 1700Mi on the control plane, 600Mi on workers, plus 300Mi system) and evicts pods below 300Mi free. Logs (Loki, Fluentd, Fluent Bit) and traces (Tempo, OpenTelemetry collector) are disabled. Velero backs up the cluster daily at 04:00 (30 days) to RustFS: resources to the `k3s-velero` bucket, Longhorn volumes as Longhorn backups to `k3s-longhorn`. k3s etcd snapshots (every 12h, last 5) are kept on each server and uploaded to the `k3s-etcd` bucket; k3s reads the S3 settings from the `kube-system/k3s-etcd-snapshot-s3-config` secret (External Secrets, Vault `s3/etcd`). Rancher is not enabled.

### Known limits (4 GB Raspberry Pis)

- Rancher deploys its own controllers (Fleet, CAPI, Turtles, webhook, system-upgrade-controller) with tolerations for the control plane taint. On 4 GB control plane nodes with etcd on SD cards this exhausts them, so `rancher-app` is removed from `kubernetes/clusters/prod/infra/kustomization.yaml` until the control plane nodes have SSDs or more memory. Its files stay in `kubernetes/platform/rancher` (bundled catalogs, 10 minute startup probe, 1200Mi limit).
- Prometheus has a 700Mi memory limit (512Mi request), below node5's free memory: it is OOM-killed and restarted instead of hanging the node. In prod it keeps memory under the limit with a 60s scrape interval, 6h / 1GB retention and trimmed kubelet histograms (`app/overlays/prod/values.yaml`).

## pimaster (control host)

Ubuntu 24.04 VM, not managed by Ansible. The cluster LAN and the home network share one switch, so pimaster has an address on both and reaches the nodes directly, without the gateway route. Netplan replaces the installer config (cloud-init network config is disabled in `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`):

```yaml
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s1:
      dhcp4: false
      addresses:
      - 192.168.50.100/24
      - 10.0.0.16/24
      nameservers:
        addresses:
        - 10.0.0.1
        search:
        - homelab.yekvitka.net
      routes:
      - to: 0.0.0.0/0
        via: 192.168.50.1
        metric: 100
      - to: 0.0.0.0/0
        via: 10.0.0.1
        metric: 200
```

DNS comes only from the gateway, as on the nodes. The home router hands out its own IPv6 DNS servers, so a networkd drop-in ignores them:

```ini
# /etc/systemd/network/10-netplan-enp0s1.network.d/no-ipv6-dns.conf
[IPv6AcceptRA]
UseDNS=false
UseDomains=false

[DHCPv6]
UseDNS=false
UseDomains=false
```

Apply with `sudo netplan apply`, check with `resolvectl status enp0s1`.

Disk: 32 GB. The Ubuntu installer gives the root LV only half of the volume group. Extend it to the whole VG:

```shell
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```

## Build

1. Gateway: [metal/openwrt/README.md](metal/openwrt/README.md).
2. SD cards: put the pimaster public key in `metal/rpi/cloud-init/root.pub`, then from `metal/rpi`:

   ```shell
   make img/ubuntu-24.04.5-preinstalled-server-arm64+raspi.img.xz
   make burn-image USB=/dev/sdX
   export WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>'   # wlan0 backup uplink
   make prepare-node1 USB=/dev/sdX SSD1_ID=<node1 SSD1 /dev/disk/by-id name>
   make prepare-node2 USB=/dev/sdX   # node3..node5 the same way
   ```

   Nodes get 10.0.0.1N on eth0 (DNS from the gateway) and 192.168.50.20N on wlan0.

3. Only with `centralized_san: true`: set node1 SSD2 in `ansible/vars/centralized_san/centralized_san_target.yml`.
4. From the repo root on pimaster:

   ```shell
   make prepare-ansible   # ansible runner + secret files (IONOS API key)
   make init              # os-upgrade, node setup, DNS, Vault/RustFS, SAN, k3s, Flux bootstrap
   ```

Rancher bootstrap password:

```shell
kubectl get secret -n cattle-system bootstrap-secret -o go-template='{{ .data.bootstrapPassword | base64decode }}'
```

## License

MIT, see [LICENSE](LICENSE). Original work © ricsanfre.
