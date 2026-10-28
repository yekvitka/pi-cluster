# Pi Cluster

Homelab K3s cluster on Raspberry Pis, automated with Ansible and FluxCD.

Fork of [ricsanfre/pi-cluster](https://github.com/ricsanfre/pi-cluster). Architecture, playbooks and Flux layout follow upstream; see the upstream documentation at https://picluster.ricsanfre.com for how each component works. This README covers only what differs here.

## Hardware and roles

| Host | IP | Role |
|---|---|---|
| gateway | 10.0.0.1 / 192.168.50.200 | OpenWrt router: firewall/NAT, DHCP, DNS forwarder, NTP ([metal/openwrt](metal/openwrt/README.md)) |
| pimaster | 192.168.50.100 | Ansible control node (VM on the home network, route to 10.0.0.0/24 via the gateway) |
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
- Optional centralized iSCSI SAN on node1, disabled (above).
- Ansible connects as `root`; SSH key from `metal/rpi/cloud-init/root.pub`.
- Rancher added as a Flux platform app (`kubernetes/platform/rancher`), at `https://rancher.homelab.yekvitka.net`.
- k3s held on 1.36.x: Rancher 2.15 supports Kubernetes < 1.37 (`.github/renovate.json5`).
- Only core and monitoring platform apps are enabled in `kubernetes/clusters/prod/infra/kustomization.yaml`. The other upstream apps stay in `kubernetes/platform/` and can be re-enabled there.
- Sized for 4 GB Raspberry Pis with a single worker: control plane nodes (node2–node4) keep the `NoSchedule` taint (etcd on SD cards), so apps run on node5. Logs (Loki, Fluentd, Fluent Bit), traces (Tempo, OpenTelemetry collector) and Velero are disabled. Rancher runs on node3 with a 1200 MiB memory limit (`kubernetes/platform/rancher/app/overlays/prod/values.yaml`).

### Known limits (4 GB Raspberry Pis)

- Rancher deploys its own controllers (Fleet, CAPI, Turtles, webhook, system-upgrade-controller) with tolerations for the control plane taint. On 4 GB control plane nodes with etcd on SD cards this exhausts them: the Rancher HelmRelease is suspended in the cluster until the control plane nodes have SSDs or more memory.
- kube-prometheus-stack as configured (Prometheus limit 1800Mi) does not fit next to the core apps on node5: its HelmRelease is suspended until Prometheus gets a memory limit below node5's free memory or a bigger worker is added.

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
