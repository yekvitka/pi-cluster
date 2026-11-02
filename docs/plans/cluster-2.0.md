# Cluster 2.0

Goal: run everything enabled today plus Rancher, logs (Loki), traces (Tempo, OpenTelemetry), the Istio mesh (Kiali) and Kafka on the hardware already bought: the Pi 4 4 GB nodes, one new Pi 4 8 GB node (node6) and an SSD in every Pi. One pod per service, no workload replicas, no further spending.

Status (2026-11-02): phase 0 done (repo ready, nothing applied to the nodes). node6 and the SSDs are ordered. The earlier design with a second 8 GB node (node7) is dropped: node6 becomes the only API server.

## Why

The 4 GB control-plane nodes run the k3s server with 1.0-1.9 GB each (measured 2026-11-02: node2 1.9, node4 1.6, node3 1.0 GB). Rancher made every API server keep about 0.7 GB more (its resource types and watches) and node3 thrashed until it hung (2026-10-30). More workers do not help: the cost lands on every API server. With node6 as the only API server, only the 8 GB node pays it, and the 4 GB nodes shed the API server load as well: about 0.5 GB for an etcd-only server, 0.15 GB for an agent.

## Target architecture

| Node | IP (eth0 / Wi-Fi) | Hardware | k3s role | Runs |
|---|---|---|---|---|
| node6 | 10.0.0.16 / 192.168.50.206 | Pi 4 8 GB, SSD | the only API server + etcd, tainted | API server, scheduler, controllers, kube-vip, Rancher |
| node2 | 10.0.0.12 / 192.168.50.202 | Pi 4 4 GB, SSD (reinstalled at conversion) | etcd only (`k3s_etcd_only`) | stateless pods: Loki read/gateway/caches, OpenTelemetry collector, istiod, Kiali, operators |
| node3 | 10.0.0.13 / 192.168.50.203 | Pi 4 4 GB, SSD | etcd only + Longhorn | Loki write and backend, Tempo (volumes) |
| node4 | 10.0.0.14 / 192.168.50.204 | Pi 4 4 GB, SSD (reinstalled at conversion) | worker + Longhorn | Kafka broker (volume) |
| node5 | 10.0.0.15 / 192.168.50.205 | Pi 4 4 GB, SSD | worker + Longhorn | Prometheus, Alertmanager, Grafana |
| node1 | 10.0.0.11 / 192.168.50.201 | Pi 4 4 GB, SSD for data | outside the cluster | Vault, RustFS, bind9, certbot, offsite backup push (unchanged) |
| gateway | 10.0.0.1 / 192.168.50.200 | Pi 4, OpenWrt | router | NAT, DNS forwarder, WireGuard to the Oracle VM (unchanged) |
| pimaster | 10.0.0.20 / 192.168.50.100 | VM | control host | Ansible runner |

- **etcd**: 3 members, node6 + node2 + node3, all on SSDs. Survives one member down.
- **API**: node6 only, behind the kube-vip address 10.0.0.10 (kept, so a second API server can join later without changes). Cilium reaches the API through the k3s local load balancer (`127.0.0.1:6444`) on every node.
- **node6 down**: running pods keep running and serving, and kubelets restart crashed containers; nothing can be deployed, changed or rescheduled, and Flux and Rancher stop. etcd keeps the data on node2 + node3. Recovery: bring node6 back from its SSD, or rejoin node2 as a full server (about 30 minutes, Rancher off).
- **Workloads**: one pod each; DaemonSets one per node. Longhorn one replica per volume (Velero daily, offsite nightly). Pods with volumes run on the Longhorn nodes (`node_storage=longhorn`): node3, node4, node5.

IP plan (10.0.0.0/24): .1 gateway, .10 k3s API (kube-vip), .11-.19 nodes, .20 pimaster, .64/26 Cilium LoadBalancer pool (.68 Envoy gateway), .150-.249 DHCP.

### Memory budget

Free memory per node after the role changes, with today's workloads (k3s and pod usage measured 2026-11-02; etcd-only and agent k3s estimated at 0.5 and 0.15 GB). Service sizes come from the memory requests and limits in the repo.

| Node | Free | Planned services | Left (estimate) |
|---|---|---|---|
| node6 | ~4.8 GB | Rancher: 1.5 GB pod + ~0.7 GB on the k3s server | ~2.5 GB, headroom for the only API server |
| node2 | ~2.7 GB | Loki read, gateway, caches; OpenTelemetry collector; istiod, Kiali; Strimzi operator; descheduler, Hubble relay/UI, tofu-controller | ~0.7 GB |
| node3 | ~2.6 GB | Loki write and backend; Tempo | ~1.1 GB |
| node4 | ~2.5 GB | Longhorn; Kafka broker | ~0.9 GB |
| node5 | ~1.0 GB | monitoring, unchanged | ~0.9 GB |

DaemonSets on every node (Fluent Bit ~40 MB, Istio ztunnel and CNI ~60 MB) are included. In total ~13.6 GB free, ~7.3 GB planned.

Measure after each phase and stop adding services when a 4 GB node has less than 0.5 GB available. The reservations (`k3s_kube_reserved_memory`) follow the measured k3s usage.

## Services

| Service | Memory (estimate) | Status | Placement and notes |
|---|---|---|---|
| Everything enabled today | measured | running | unchanged (monitoring stays on node5) |
| Rancher 2.15, route `rancher.homelab.yekvitka.net` | ~2.2 GB with the API server load | prepared, `rancher-app` not enabled | node6, limit 1536Mi |
| Loki P1: Simple Scalable, one pod per component, S3 on RustFS (`k3s-loki`), chunks and results caches, 7 days retention; Fluent Bit straight to Loki (no Fluentd) | ~1.1 GB | prepared, `loki-app` and `fluent-app` not enabled | write and backend on node3, the rest on node2 |
| Tempo + OpenTelemetry collector | ~1.0 GB | prod overlays; `tempo-app` prepared, collector Kustomization to add | Tempo on node3 (volume); single binary if memory is tight |
| Istio ambient (istiod, ztunnel, CNI) + Kiali | ~0.8 GB | prod overlays; Kustomizations to add, Cilium `istio-config` component (`cni.exclusive: false`) | changes pod networking next to Cilium: dev cluster first; Kiali logs in with a service account token |
| Kafka: Strimzi operator, one KRaft broker | ~1.8 GB | prod overlays (operator, cluster, Kafdrop, Schema Registry); Kustomizations to add | broker on node4 (volume); Kafdrop and Schema Registry only when used, Kafdrop through port-forward until it gets a basic-auth route |
| descheduler, Hubble relay/UI, tofu-controller | ~0.4 GB | disabled (commit 01f0c657) | descheduler needs a policy that does not pack evicted pods onto the emptiest node (why it was removed); tofu-controller only once Terraform runs in Flux (today it runs from the runner) |

Removed from the repo (2026-11-02): the Elastic stack (~2.5 GB, does not fit; Loki covers logs) and Keycloak (its operator fails on arm64), with their Terraform modules, Vault secrets and the OIDC route settings. Web UIs use basic auth at the gateway.

## Phase 0: repo preparation (done)

- `k3s_cluster_init_node` (vars/picluster.yml, `node2` today): the server that starts a cluster is explicit. Before, the first host of `k3s_master` ran `cluster-init`: a new node listed first would have created a second cluster.
- `k3s_etcd_only` (host_vars): etcd-only servers (`disable-apiserver`, `disable-controller-manager`, `disable-scheduler`).
- `k3s_kube_reserved_memory` (host_vars): kubelet reservation per node (node6 3072Mi as the only API server with Rancher's load; etcd-only 768Mi; defaults 1700Mi servers, 600Mi agents).
- Workers get `node_storage=longhorn` only with `k3s_longhorn_storage: true` (node5 set explicitly). Before, every worker became a Longhorn node, also without an SSD.
- Prometheus, Alertmanager and Grafana pinned to `node_type=worker` + `node_storage=longhorn`; Velero prefers nodes without Longhorn.
- k3s upgrade plans select servers by the `etcd` role (etcd-only servers have no `control-plane` label).
- `host_vars/node6.yml`, `metal/rpi` `prepare-node6`; `host_vars/node7.yml` and `prepare-node7` kept for a possible second 8 GB node.
- Loki P1 overlay, Fluent Bit `loki` component, Rancher app (all not enabled); `k3s-loki` excluded from the offsite copy.
- pimaster moved to 10.0.0.20.

## Phases

Rules for every phase: a fresh etcd snapshot before any etcd change (`k3s etcd-snapshot save --name pre-<phase>` on a server), etcd never below 3 members, one change at a time, the user approves each etcd step. Converting a server: drain, `systemctl disable --now k3s`, `kubectl delete node` (k3s removes its etcd member), wipe or reinstall, rejoin. Runbook details: [docs/runbooks/node-ssd-migration.md](../runbooks/node-ssd-migration.md).

| Phase | Change | etcd members | Validation | Rollback |
|---|---|---|---|---|
| 1 | node6: flash the SSD from node1 (`dd` by `/dev/disk/by-id`, cloud-init from `metal/rpi` templates, network-config from a node's netplan with the IPs changed), boot without SD, EEPROM check, inventory + DHCP lease (MAC) + bind9 records, `update.yml`, `setup_picluster.yml --tags node`, load test | 3 | SSH, `vcgencmd get_throttled` = `0x0` under load | reflash |
| 2 | node6 joins as a full server (`k3s_install.yml --limit node6`) | 3 → 4 | `Ready`, `EtcdIsVoter`, VIP can move to node6 | delete node6, wipe |
| 3 | node3 to etcd only (`k3s_etcd_only: true`, reserve 768Mi): remove, wipe `/var/lib/rancher/k3s/server/db`, rejoin | 4 → 3 → 4 | voter again, Cilium healthy on node3 (API through 6444), Longhorn node `Ready` | rejoin as a full server |
| 4 | node2 to etcd only: remove, reinstall on its SSD, rejoin with `k3s_etcd_only: true` | 4 → 3 → 4 | voter, no API server on node2 | rejoin as a full server |
| 5 | node4 to worker + Longhorn (`k3s_longhorn_storage: true`): remove from etcd, reinstall on its SSD as an agent, move to `k3s_worker` | 4 → 3 (node6, node2, node3) | 3 voters, API only on node6, VIP on node6, Longhorn node `Ready` | rejoin as a server |
| 6 | `k3s_cluster_init_node` to node6; measure memory, adjust reservations | 3 | numbers vs budget | revert variables |
| 7 | Loki + Fluent Bit: add `loki-app.yaml`, `fluent-app.yaml` to the prod kustomization | 3 | logs in Grafana, write/backend volumes on node3 | remove from the list |
| 8 | Rancher: add `rancher-app.yaml` | 3 | UI, k3s memory on node6 before and after | remove from the list |
| 9 | Tempo + OpenTelemetry collector | 3 | traces in Grafana, Tempo volume on node3 | remove from the list |
| 10 | Istio ambient + Kiali with the Cilium `istio-config` component, on the dev cluster first | 3 | pod traffic and Gateway routes unchanged, Kiali graph | remove; Cilium component off |
| 11 | Kafka: Strimzi operator + one broker | 3 | broker `Ready` on node4, produce and consume a test topic | remove from the list |
| 12 | descheduler (safer policy), Hubble relay/UI, tofu-controller (only if used) | 3 | no evictions onto full nodes | disable |
| 13 | Gatus checks (Rancher), docs, CLAUDE.md | 3 | everything green | - |

Phases 7-12: measure after each and stop at the 0.5 GB rule.

Inventory change for phase 1 (`ansible/inventory.yml`): add node6 to `picluster`, `raspberrypi` and `k3s_master` (after node2-node4), keep `k3s_cluster_init_node` on a running server until phase 6. node2 and node3 stay in `k3s_master` as etcd-only servers; node4 moves to `k3s_worker` in phase 5.

If a second 8 GB node is added later, it joins as a second API server (phases 1-2 with `host_vars/node7.yml` and `prepare-node7`): API high availability behind 10.0.0.10, and node2 can become a worker.

## Spare SD cards

Every Pi moves to an SSD. The freed SD cards hold no cluster data (slow random writes, they wear out):

- Gateway spare: the same OpenWrt image plus a config backup (`sysupgrade -b`) on a second card. The gateway is the only Pi still booting from SD.
- Offline copy of the keys, encrypted: Vault unseal keys, restic password, SSH keys (today only in `~/.secrets` on pimaster).
- Rescue cards: Ubuntu with the cloud-init keys. With `BOOT_ORDER=0xf41` a Pi boots an inserted SD card before its SSD: insert one only to repair, never leave it in.

## Hardware notes

- SSD on a USB adapter with UAS; a timeout under load needs `rpi_usb_storage_quirks` (host_vars).
- Power: official 15 W supply, or a USB-C PD port of the shared charger with a short 3 A cable; accept only with `get_throttled` = `0x0` under load (`make get-pi-status`). All nodes on one charger is a single point of failure: node6 gets its own supply.
- Cooling: heatsink case or fan (throttling at ~80 °C).
- Boot: with no SD card the Pi 4 bootloader (default `BOOT_ORDER=0xf41`) boots from USB; check the EEPROM version at first boot.
- node1 to SSD boot: optional, separate runbook (Vault, RustFS and bind9 move with it).

## Risks

- One API server: with node6 down, nothing can change (running workloads continue) until it is back or node2 rejoins as a server.
- Three etcd members: one can fail.
- The 4 GB nodes are planned down to 0.7-1.1 GB free: a failed node's pods cannot move elsewhere (one pod per service, accepted).
- Rancher's memory on node6: measured before and after, limit 1536Mi, reservation 3072Mi.
- Istio ambient changes pod networking next to Cilium: dev cluster first, removable.
- Kafka is CPU-heavy for a Pi 4: one broker, measured.
- Each etcd conversion has a short window at 4 members; a snapshot exists before each.
