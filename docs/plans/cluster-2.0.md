# Cluster 2.0

Goal: a highly available control plane on two Raspberry Pi 4 8 GB nodes, every node booting from an SSD, and the services the 4 GB control plane could not carry: logs (Loki) and Rancher. One pod per service, no workload replicas.

Status (2026-11-01): phase 0 done (repo ready, nothing applied to the nodes). node6 hardware ordered, node7 planned.

## Why

The 4 GB control-plane nodes (node2-node4) run the k3s server with 1.3-1.9 GB each. Rancher made every API server keep about 0.7 GB more (its resource types and watches) and node3 thrashed until it hung (2026-10-30). More workers do not help: the cost lands on every API server. Two 8 GB control-plane nodes carry it, and the 4 GB nodes become workers or an etcd-only member.

## Target architecture

| Node | IP (eth0 / Wi-Fi) | Hardware | k3s role | Runs |
|---|---|---|---|---|
| node6 | 10.0.0.16 / 192.168.50.206 | Pi 4 8 GB, SSD | control plane + etcd, tainted | API server, scheduler, controllers, kube-vip, Rancher (1 pod on node6 or node7) |
| node7 | 10.0.0.17 / 192.168.50.207 | Pi 4 8 GB, SSD | control plane + etcd, tainted | same as node6 |
| node3 | 10.0.0.13 / 192.168.50.203 | Pi 4 4 GB, SSD | etcd only (`k3s_etcd_only`) + Longhorn | Loki write and backend (volumes), stateless pods |
| node5 | 10.0.0.15 / 192.168.50.205 | Pi 4 4 GB, SSD | worker + Longhorn | Prometheus, Alertmanager, Grafana |
| node2 | 10.0.0.12 / 192.168.50.202 | Pi 4 4 GB, SSD (reinstalled at conversion) | worker | stateless pods (Loki read/gateway/caches, controllers) |
| node4 | 10.0.0.14 / 192.168.50.204 | Pi 4 4 GB, SSD (reinstalled at conversion) | worker | stateless pods |
| node1 | 10.0.0.11 / 192.168.50.201 | Pi 4 4 GB, SSD | outside the cluster | Vault, RustFS, bind9, certbot, offsite backup push |
| gateway | 10.0.0.1 / 192.168.50.200 | Pi, OpenWrt | router | NAT, DNS forwarder, WireGuard to the Oracle VM |
| pimaster | 10.0.0.20 / 192.168.50.100 | VM (to be replaced) | control host | Ansible runner |

- **etcd**: 3 members, node6 + node7 + node3, all on SSDs. Survives one member down.
- **API**: node6 + node7 behind the kube-vip address 10.0.0.10. Cilium reaches the API through the k3s local load balancer (`127.0.0.1:6444`) on every node, which follows the available API servers.
- **Workloads**: one pod each; DaemonSets one per node. Longhorn one replica per volume (Velero daily, offsite nightly).
- **Longhorn storage nodes** (`node_storage=longhorn`): node3, node5. More can be added (`k3s_longhorn_storage: true`) once their SSDs are in.

IP plan (10.0.0.0/24): .1 gateway, .10 k3s API (kube-vip), .11-.19 nodes, .20 pimaster, .64/26 Cilium LoadBalancer pool (.68 Envoy gateway), .150-.249 DHCP.

### Memory budget (estimates)

| Node | k3s | System pods | Planned workloads | Free |
|---|---|---|---|---|
| node6 / node7 (8 GB) | ~2.0-2.5 GB (reserved 2560Mi) | ~0.4 GB | Rancher ~1.7 GB on one of them | ~2.5-4 GB |
| node3 (etcd only) | ~0.45 GB (reserve 768Mi) | ~0.4 GB + Longhorn ~0.35 | Loki write + backend ~0.6 GB | ~1.5 GB |
| node2, node4 (workers) | ~0.2 GB | ~0.4 GB | Loki read, gateway, caches ~0.7 GB, controllers | ~2 GB each |
| node5 (worker) | ~0.15 GB | ~0.4 GB + Longhorn | monitoring ~1.2 GB | ~1.1 GB |

Measure after each phase; the reservations (`k3s_kube_reserved_memory`) follow the measured k3s usage.

## Services

| Service | Status | Placement |
|---|---|---|
| Everything enabled today | running | unchanged (monitoring stays on worker + storage nodes) |
| Loki P1: Simple Scalable, one pod per component, S3 on RustFS (`k3s-loki`), chunks and results caches, 7 days retention | prepared, `loki-app` not enabled | write and backend on storage nodes, the rest anywhere |
| Fluent Bit straight to Loki (no Fluentd, no Elasticsearch) | prepared, `fluent-app` not enabled | every node |
| Rancher 2.15 in the cluster, route `rancher.homelab.yekvitka.net` | prepared, `rancher-app` not enabled | control-plane nodes, limit 1536Mi |
| Elasticsearch, Kafka, Istio/Kiali, Keycloak, Tempo, OpenTelemetry, Fluentd | dropped for now | - |

## Phase 0: repo preparation (done)

- `k3s_cluster_init_node` (vars/picluster.yml, `node2` today): the server that starts a cluster is explicit. Before, the first host of `k3s_master` ran `cluster-init`: a new node listed first would have created a second cluster.
- `k3s_etcd_only` (host_vars): etcd-only servers (`disable-apiserver`, `disable-controller-manager`, `disable-scheduler`).
- `k3s_kube_reserved_memory` (host_vars): kubelet reservation per node (node6/node7 2560Mi; etcd-only 768Mi; defaults 1700Mi servers, 600Mi agents).
- Workers get `node_storage=longhorn` only with `k3s_longhorn_storage: true` (node5 set explicitly). Before, every worker became a Longhorn node, also without an SSD.
- Prometheus, Alertmanager and Grafana pinned to `node_type=worker` + `node_storage=longhorn`; Velero prefers nodes without Longhorn.
- k3s upgrade plans select servers by the `etcd` role (etcd-only servers have no `control-plane` label).
- `host_vars/node6.yml`, `host_vars/node7.yml`, `metal/rpi` `prepare-node6` / `prepare-node7`.
- Loki P1 overlay, Fluent Bit `loki` component, Rancher app (all not enabled); `k3s-loki` excluded from the offsite copy.
- pimaster moved to 10.0.0.20.

## Phases

Rules for every phase: a fresh etcd snapshot before any etcd change (`k3s etcd-snapshot save --name pre-<phase>` on a server), etcd never below 3 members, one change at a time, the user approves each etcd step. Converting a server: drain, `systemctl disable --now k3s`, `kubectl delete node` (k3s removes its etcd member), wipe or reinstall, rejoin. Runbook details: [docs/runbooks/node-ssd-migration.md](../runbooks/node-ssd-migration.md).

| Phase | Change | etcd members | Validation | Rollback |
|---|---|---|---|---|
| 1 | node6: flash the SSD from node1 (`dd` by `/dev/disk/by-id`, cloud-init from `metal/rpi` templates, network-config from a node's netplan with the IPs changed), boot without SD, EEPROM check, inventory + DHCP lease (MAC) + bind9 records, `update.yml`, `setup_picluster.yml --tags node`, load test | 3 | SSH, `vcgencmd get_throttled` = `0x0` under load | reflash |
| 2 | node6 joins as a full server (`k3s_install.yml --limit node6`) | 4 | `Ready`, `EtcdIsVoter`, VIP can move to node6 | delete node6, wipe |
| 3 | node7, same as phases 1-2 | 5 | as above | as above |
| 4 | node3 to etcd only (`k3s_etcd_only: true`, reserve 768Mi): remove, wipe `/var/lib/rancher/k3s/server/db`, rejoin | 5 → 4 → 5 | voter again, Cilium healthy on node3 (API through 6444), Longhorn node `Ready` | rejoin as a full server |
| 5 | node2 to worker: remove from etcd, reinstall on its SSD as an agent | 5 → 4 | `Ready`, no etcd role | rejoin as a server |
| 6 | node4 to worker, same as node2 | 4 → 3 (node3, node6, node7) | 3 voters, API on node6 + node7, VIP fails over when one is cordoned and stopped | rejoin |
| 7 | `k3s_cluster_init_node` to node6; measure memory, adjust reservations | 3 | numbers vs budget | revert variables |
| 8 | Loki P1 + Fluent Bit: add `loki-app.yaml`, `fluent-app.yaml` to the prod kustomization | 3 | logs in Grafana, write/backend volumes on storage nodes | remove from the list |
| 9 | Rancher: add `rancher-app.yaml` | 3 | UI, k3s memory on node6/node7 | remove from the list |
| 10 | Gatus checks (Rancher), docs, CLAUDE.md | 3 | everything green | - |

If node7 arrives later: phases 1-2, then 4 (node3 etcd only, members node2, node3, node4, node6), and phases 5-6 wait for node7 so etcd stays at 3+ members. Rancher waits for both 8 GB nodes.

Inventory change for phase 1 (`ansible/inventory.yml`): add node6/node7 to `picluster`, `raspberrypi` and `k3s_master` (after node2-node4 until they leave), keep `k3s_cluster_init_node` on a running server. Workers move to `k3s_worker` when converted.

## Hardware notes

- SSD on a USB adapter with UAS; a timeout under load needs `rpi_usb_storage_quirks` (host_vars).
- Power: official 15 W supply, or a USB-C PD port of the shared charger with a short 3 A cable; accept only with `get_throttled` = `0x0` under load (`make get-pi-status`). All nodes on one charger is a single point of failure.
- Cooling: heatsink case or fan (throttling at ~80 °C).
- Boot: with no SD card the Pi 4 bootloader (default `BOOT_ORDER=0xf41`) boots from USB; check the EEPROM version at first boot.
- node1 to SSD boot: separate runbook (Vault, RustFS and bind9 move with it).

## Risks

- Two API servers and three etcd members: one 8 GB node can fail. Both 8 GB nodes on the same charger can fail together.
- Rancher's memory on the control plane: measured before enabling, limit 1536Mi, reservations 2560Mi.
- Each etcd conversion has a short window at 4 members; a snapshot exists before each.
