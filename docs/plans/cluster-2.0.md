# Cluster 2.0

Goal: run everything enabled today plus Rancher, logs (Loki), traces (Tempo, OpenTelemetry), the Istio mesh (Kiali) and Kafka on the hardware already bought: the Pi 4 4 GB nodes, one new Pi 4 8 GB node (node6) and the SSDs already bought: every Pi except node2 and node4 on an SSD. One pod per service, no workload replicas, no further spending.

Status (2026-11-06): phases 1-6 done, the target node layout runs: node6 is the only API server (+ etcd, tainted, `k3s_cluster_init_node`, VIP 10.0.0.10), node2 and node3 are etcd-only, node4 and node5 are workers; etcd has 3 voters (node2, node3, node6). Phases 7 (Loki + Fluent Bit), 8 (Rancher), 9 (Tempo + OpenTelemetry) and 12 (Hubble) run since 2026-11-06. Istio + Kiali (10) and Kafka (11) were removed on 2026-11-07: node6 has no CPU left for them ([why](#istio-and-kafka-removed-2026-11-07)). Next: 13. Not planned any more: descheduler, tofu-controller (user, 2026-11-06). node6 (Pi 4 8 GB) boots from node4's former SSD (Kingston SH103S3120G, Initio adapter, UAS without a quirk); node4 and node2 stay on their SD cards. node6 becomes the only API server; a second 8 GB node is not planned. The [beta](#beta-not-run) did not run: node6 arrived first.

## Why

The 4 GB control-plane nodes run the k3s server with 1.0-1.9 GB each (measured 2026-11-02: node2 1.9, node4 1.6, node3 1.0 GB). Rancher made every API server keep about 0.7 GB more (its resource types and watches) and node3 thrashed until it hung (2026-10-30). More workers do not help: the cost lands on every API server. With node6 as the only API server, only the 8 GB node pays it, and the 4 GB nodes shed the API server load as well: about 0.5 GB for an etcd-only server, 0.15 GB for an agent.

## Target architecture

| Node | IP (eth0 / Wi-Fi) | Hardware | k3s role | Runs |
|---|---|---|---|---|
| node6 | 10.0.0.16 / 192.168.50.206 | Pi 4 8 GB, SSD | the only API server + etcd, tainted | API server, scheduler, controllers, kube-vip, Rancher |
| node2 | 10.0.0.12 / 192.168.50.202 | Pi 4 4 GB, SD card (no SSD) | etcd only (`k3s_etcd_only`) | stateless pods: Loki read/gateway/caches, OpenTelemetry collector, operators |
| node3 | 10.0.0.13 / 192.168.50.203 | Pi 4 4 GB, SSD | etcd only + Longhorn | Loki write and backend, Tempo (volumes) |
| node4 | 10.0.0.14 / 192.168.50.204 | Pi 4 4 GB, SD card (its SSD went to node6) | worker, no Longhorn | stateless pods |
| node5 | 10.0.0.15 / 192.168.50.205 | Pi 4 4 GB, SSD | worker + Longhorn | Prometheus, Alertmanager, Grafana |
| node1 | 10.0.0.11 / 192.168.50.201 | Pi 4 4 GB, SSD for data | outside the cluster | Vault, RustFS, bind9, certbot, offsite backup push (unchanged) |
| gateway | 10.0.0.1 / 192.168.50.200 | Pi 4, OpenWrt | router | NAT, DNS forwarder, WireGuard to the Oracle VM (unchanged) |
| pimaster | 10.0.0.20 / 192.168.50.100 | VM | control host | Ansible runner |

- **etcd**: 3 members, node6 + node2 + node3: node6 and node3 on SSDs, node2 on its SD card. Survives one member down.
- **API**: node6 only, behind the kube-vip address 10.0.0.10 (kept, so a second API server can join later without changes). Cilium reaches the API through the k3s local load balancer (`127.0.0.1:6444`) on every node.
- **node6 down**: running pods keep running and serving, and kubelets restart crashed containers; nothing can be deployed, changed or rescheduled, and Flux and Rancher stop. etcd keeps the data on node2 + node3. Recovery: bring node6 back from its SSD, or rejoin node2 as a full server (about 30 minutes, Rancher off).
- **Workloads**: one pod each; DaemonSets one per node. Longhorn one replica per volume (Velero daily, offsite nightly). Pods with volumes run on the Longhorn nodes (`node_storage=longhorn`): node3, node5.

IP plan (10.0.0.0/24): .1 gateway, .10 k3s API (kube-vip), .11-.19 nodes, .20 pimaster, .64/26 Cilium LoadBalancer pool (.68 Envoy gateway), .150-.249 DHCP.

### Memory budget

Free memory per node after the role changes, with today's workloads (k3s and pod usage measured 2026-11-02; etcd-only and agent k3s estimated at 0.5 and 0.15 GB). Service sizes come from the memory requests and limits in the repo.

| Node | Free | Planned services | Left (estimate) |
|---|---|---|---|
| node6 | ~4.8 GB | Rancher: 1.5 GB pod + ~0.7 GB on the k3s server | ~2.5 GB, headroom for the only API server |
| node2 | ~2.7 GB | Loki read, gateway, caches; OpenTelemetry collector; istiod, Kiali; Strimzi operator; descheduler, Hubble relay/UI, tofu-controller | ~0.7 GB |
| node3 | ~2.6 GB | Loki write and backend; Tempo | ~1.1 GB |
| node4 | ~2.5 GB | stateless pods (no Longhorn without an SSD) | ~2.5 GB, takes stateless pods from node2 if it runs short |
| node5 | ~1.0 GB | monitoring, unchanged | ~0.9 GB |

DaemonSets on every node (Fluent Bit ~40 MB, Istio ztunnel and CNI ~60 MB) are included. In total ~13.6 GB free, ~7.3 GB planned.

Measure after each phase and stop adding services when a 4 GB node has less than 0.5 GB available.

### Measured after phase 5

2026-11-06, today's workloads, before any Cluster 2.0 service:

| Node | Role | k3s | Available |
|---|---|---|---|
| node6 | only API server + etcd | 1.48 GB | 5.6 GB |
| node2 | etcd only (SD) | 0.30 GB (was 1.43) | 2.5 GB (most of node4's pods moved here) |
| node3 | etcd only + Longhorn | 0.32 GB (was 1.15) | 2.7 GB |
| node4 | worker (SD) | 0.19 GB (was 1.44) | 3.0 GB |
| node5 | worker + Longhorn + monitoring | 0.15 GB | 1.3 GB |

About 15 GB available in total, ~1.4 GB more than the estimate. Reservations unchanged: 768Mi on the etcd-only servers (k3s 0.3 GB, etcd grows with load), 3072Mi on node6 until Rancher is measured. The reservations (`k3s_kube_reserved_memory`) follow the measured k3s usage.

## Services

| Service | Memory (estimate) | Status | Placement and notes |
|---|---|---|---|
| Everything enabled today | measured | running | unchanged (monitoring stays on node5) |
| Rancher 2.15, route `rancher.homelab.yekvitka.net` | ~2.2 GB with the API server load | prepared, `rancher-app` not enabled | node6, limit 1536Mi |
| Loki P1: Simple Scalable, one pod per component, S3 on RustFS (`k3s-loki`), chunks and results caches, 7 days retention; Fluent Bit straight to Loki | ~1.1 GB | prepared, `loki-app` and `fluent-app` not enabled | write and backend on node3, the rest on node2 |
| Tempo + OpenTelemetry collector | ~1.0 GB | prod overlays; `tempo-app` prepared, collector Kustomization to add | Tempo on node3 (volume); single binary if memory is tight |
| Istio ambient (istiod, ztunnel, CNI) + Kiali | ~0.8 GB | removed 2026-11-07 (never installed in prod); prod overlays kept | changes pod networking next to Cilium: dev cluster first; Kiali logs in with a service account token |
| Kafka: Strimzi operator, one KRaft broker | ~1.8 GB | removed 2026-11-07 (ran on node6 from 2026-11-06); prod overlays kept | broker on node6 with its volume on node6's SSD (Longhorn tolerates the control-plane taint, StorageClass `longhorn-kafka` keeps the replica local): node3 and node5 have no 1.8 GB left, node4 has no SSD; Kafdrop and Schema Registry only when used, Kafdrop through port-forward until it gets a basic-auth route |
| descheduler, Hubble relay/UI, tofu-controller | ~0.4 GB | not deployed | descheduler needs a policy that does not pack evicted pods onto the emptiest node (why it was removed); tofu-controller only once Terraform runs in Flux (today it runs from the runner) |


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

## Beta (not run)

Planned until node6 arrived (commit 40e0d94): node2 the only API server, node3 and node4 etcd-only on 2 etcd members during each conversion. node6 arrived on 2026-11-06 before B1 ran, so the phases below run in full, each conversion with 4 etcd members. B1's host_vars change for node3 is phase 3.

## Phases

Rules for every phase: a fresh etcd snapshot before any etcd change (`k3s etcd-snapshot save --name pre-<phase>` on a server), etcd never below 3 members, one change at a time, the user approves each etcd step. Converting a server: drain, `systemctl disable --now k3s`, `kubectl delete node` (k3s removes its etcd member), wipe or reinstall, rejoin. Runbook details: [docs/runbooks/node-ssd-migration.md](../runbooks/node-ssd-migration.md).

| Phase | Change | etcd members | Validation | Rollback |
|---|---|---|---|---|
| 1 | node6: write Ubuntu to node6's own SSD (never node1's `DATA` SSD: Vault and RustFS) by `/dev/disk/by-id`, from node6 booted from a temporary SD card or from another host; cloud-init from the `metal/rpi` templates; boot without SD, EEPROM check, inventory + DHCP lease (MAC) + bind9 records, `update.yml`, `setup_picluster.yml --tags node`, load test. Done 2026-11-06 | 3 | SSH, `vcgencmd get_throttled` = `0x0` under load | reflash |
| 2 | node6 joins as a full server (`k3s_install.yml --limit node6`). Done 2026-11-06 | 3 → 4 | `Ready`, `EtcdIsVoter`, VIP can move to node6 | delete node6, wipe |
| 3 | node3 to etcd only (`k3s_etcd_only: true`, reserve 768Mi): remove, wipe `/var/lib/rancher/k3s/server/db`, rejoin ([runbook](../runbooks/node-ssd-migration.md#convert-a-servers-role-etcd-only-agent)). Done 2026-11-06 | 4 → 3 → 4 | voter again, Cilium healthy on node3 (API through 6444), Longhorn node `Ready` | rejoin as a full server |
| 4 | node2 to etcd only, on its SD card: `k3s_cluster_init_node` to node6 first (node2 rejoining with an empty db as init node would start a second cluster), remove, wipe `/var/lib/rancher/k3s/server/db`, rejoin with `k3s_etcd_only: true`, untainted. Done 2026-11-06 | 4 → 3 → 4 | voter, no API server on node2 | rejoin as a full server |
| 5 | node4 to worker, on its SD card without Longhorn: remove from etcd, `k3s-uninstall.sh`, move to `k3s_worker`, install k3s as an agent. Done 2026-11-06 (VIP moved to node6 in ~15 s) | 4 → 3 (node6, node2, node3) | 3 voters, API only on node6, VIP on node6 | rejoin as a server |
| 6 | measure memory, adjust reservations (`k3s_cluster_init_node` moved to node6 in phase 4). Done 2026-11-06, see [measured](#measured-after-phase-5) | 3 | numbers vs budget | revert variables |
| 7 | Loki + Fluent Bit: add `loki-app.yaml`, `fluent-app.yaml` to the prod kustomization. Done 2026-11-06: write and backend on node3, read, gateway and caches on node4; ~350 MB after start (caches fill up to 384 MB), Fluent Bit ~10 MB per node; available after: node2 2.4, node3 2.35, node4 2.8, node5 1.2, node6 5.4 GB | 3 | logs in Grafana, write/backend volumes on node3 | remove from the list |
| 8 | Rancher: add `rancher-app.yaml`. Done 2026-11-06: Rancher 1.1 GB on node6, plus webhook, Fleet, Turtles and CAPI controllers (~0.45 GB, mostly node4 and node6); k3s on node6 1.63 → 2.73 GB (+1.1 GB, more than the 0.7 GB estimate), node6 available 5.4 → 3.4 GB. node6's reservation (3072Mi) now about equals k3s + OS: raise it at the next k3s restart. k3s versions stay with Renovate and the system-upgrade plans: never change the version in Rancher (it would create its own upgrade plans) | 3 | UI, k3s memory on node6 before and after | remove from the list |
| 9 | Tempo + OpenTelemetry collector. Done 2026-11-06: ingester and metrics-generator on node3 (write-ahead logs on the SSD), the rest and the collector on node4; idle Tempo 160 MB (ingester up to 768Mi under load), collector 53 MB. A test trace sent through the gateway (`otel-collector.homelab.yekvitka.net/v1/traces`) shows in Tempo, Grafana and TraceQL search; span metrics reach Prometheus with UTF-8 names (`traces.span.metrics.calls_total`, label `service.name`) | 3 | traces in Grafana, Tempo volume on node3 | remove from the list |
| 10 | Istio ambient + Kiali with the Cilium `istio-config` component, tested on a k3d cluster first. Test 2026-11-07 (k3s 1.36.5, Cilium 1.20.2, Istio 1.30.4, repo values): with the default, istio-cni's plugin asks the API server at the kubernetes Service (10.43.0.1) from the node's network namespace for every new pod; there that address only works through Cilium's host socket load balancer, which does not reach into k3d nodes, so no pod started. In prod nodes reach it (checked), but the plugin is pointed at the API virtual IP (`KUBERNETES_SERVICE_HOST: ${K3S_API_VIP}`) so pod creation never depends on it. With that: new pods in and outside the mesh start, mesh traffic goes through ztunnel with mTLS (SPIFFE identities in its access log), traffic in and out of the mesh works, a Cilium rolling restart keeps it working. Kiali values fixed (Tempo port 3200, datasource uid `tempo`). Merged 2026-11-07 (PR #53), removed the same day before Istio installed: see [below](#istio-and-kafka-removed-2026-11-07) | 3 | new pods start on every node, ztunnel and istio-cni on all 5 nodes, a test namespace in ambient with mTLS, Kiali graph | removed; Cilium component off (2026-11-07) |
| 11 | Kafka: Strimzi operator + one broker on node6. Longhorn's taint toleration changes only with every volume detached: scale Prometheus, Alertmanager, Grafana and Loki write/backend to 0 for the change, label node6 `node_storage=longhorn`, scale back up. Done 2026-11-06: window 7 min; broker 634 MB on node6 (volume and replica on node6), Strimzi operator + entity operator 608 MB on node2, Longhorn on node6 275 MB; a test topic produced and consumed as `admin` (SCRAM), unauthenticated access refused. Available after: node6 2.2, node2 1.5, node3 2.0, node4 2.4, node5 1.1 GB; node6 CPU 61%, k3s there 2.89 GB (reservation 3072Mi). Removed 2026-11-07, Longhorn off node6 the same day (label removed, Longhorn node deleted; the taint toleration setting stays, no effect) | 3 | broker `Ready` on a Longhorn node, produce and consume a test topic | removed |
| 12 | Hubble relay/UI (descheduler and tofu-controller dropped, user 2026-11-06). Done 2026-11-06: UI at `hubble.homelab.yekvitka.net` behind basic auth, relay connected to all 5 nodes, 34 MB; no Cilium agent restart | 3 | flows in the Hubble UI | disable |
| 13 | Gatus checks (Rancher), docs, CLAUDE.md | 3 | everything green | - |

Phases 7-12: measure after each and stop at the 0.5 GB rule.

## Istio and Kafka removed (2026-11-07)

Merging phase 10 restarted the Cilium agent on every node (new `istio-config` settings) while Flux re-applied every app for the new commit. node6 was at 61% CPU before; the agent recompiling its programs for every pod there took it to 0% idle. etcd runs inside the k3s process: it slowed down, the controller-manager missed its leader lease renewal and k3s exited (11:26 UTC), before Istio was installed.

It then kept restarting (17 times in 1.5 hours):

- Each k3s restart makes kube-vip lose its lease and drop the API virtual IP (10.0.0.10) from node6's eth0, and put it back when k3s returns. Cilium counts the address as one of the node's own, so every change makes it recompile and reload the programs for all endpoints on node6, starving k3s again.
- Every controller in the cluster restarts and re-lists everything when the API goes away. Rancher on node6 misses its probes under the load and restarts; each start checks out its chart catalogs with `git` again.

node6 has no CPU left for a mesh or a broker: Istio (ztunnel and istio-cni on every node) and Kafka (the broker on node6) are out. Their prod overlays stay in the repo.

Afterwards (2026-11-07): Cilium's `istio-config` component off, Longhorn off node6, and longer leader leases (60 s lease, 40 s renewal deadline, 5 s retry instead of 15/10/2) for k3s's controller-manager and scheduler (`k3s_server_config`) and for kube-vip, so a slow API no longer restarts k3s or moves the VIP. The cloud-controller-manager runs on all three servers and its holder's k3s exited with every API outage, on node2 and node3 taking their etcd member with it: its lease is 240 s with a 180 s renewal deadline, longer than a k3s restart on node6 (95 s). kube-vip v1.2.0 always deletes the VIP when it starts and needs the API to add it back: a k3s restart still costs node6 one Cilium recompile.

The `dev/` tooling is stale (k3s 1.30.6 image in the k3d template, `helmfile.yaml` and `kubernetes/clusters/bootstrap/flux` missing): the phase 10 test used k3d (installed on pimaster, arm64) directly with Helm and the repo values, then deleted the cluster.

Inventory (`ansible/inventory.yml`): node6 is in `picluster`, `raspberrypi` and `k3s_master` (after node2-node4) since phase 1; `k3s_cluster_init_node` stays on a running server until phase 6. node2 and node3 stay in `k3s_master` as etcd-only servers; node4 moves to `k3s_worker` in phase 5.

If a second 8 GB node is added later, it joins as a second API server (phases 1-2 with `host_vars/node7.yml` and `prepare-node7`): API high availability behind 10.0.0.10, and node2 can become a worker.

## Spare SD cards

Every Pi except node2 and node4 moves to an SSD (node1's SSD holds only data). The freed SD cards hold no cluster data (slow random writes, they wear out):

- Gateway spare: the same OpenWrt image plus a config backup (`sysupgrade -b`) on a second card. The gateway, node1, node2 and node4 still boot from SD.
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
- Three etcd members: one can fail. node2's member writes to an SD card (slower, wears out); the etcd snapshots on S3 cover it.
- The 4 GB nodes are planned down to 0.7-1.1 GB free: a failed node's pods cannot move elsewhere (one pod per service, accepted).
- Rancher's memory on node6: measured before and after, limit 1536Mi, reservation 3072Mi.
- node6's CPU, not memory, is the limit: a Cilium agent restart there costs minutes of full CPU (Istio and Kafka removed for it, 2026-11-07).
- Each etcd conversion has a short window at 4 members; a snapshot exists before each.
