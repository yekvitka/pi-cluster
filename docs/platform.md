# Platform

What runs in the cluster and how it fits 4 GB Raspberry Pis. Every app in the repo, with its status: [kubernetes/platform](../kubernetes/platform/README.md).

## Design

- Five Raspberry Pis and an OpenWrt gateway. Ubuntu 24.04, installed by cloud-init; Ansible connects as `root` with the key in `metal/rpi/cloud-init/root.pub`.
- The BCM2835 hardware watchdog runs on every Pi (`rpi_watchdog_sec`, basic_setup role): a hung node reboots itself.
- Vault, RustFS and bind9 run on node1, outside the cluster: the cluster can be rebuilt without losing secrets or backups.
- Flux deploys what `kubernetes/clusters/prod/infra/kustomization.yaml` lists. The other apps in `kubernetes/platform/` are planned and come one at a time with [Cluster 2.0](plans/cluster-2.0.md).
- k3s stays on 1.36.x: Renovate proposes patch releases only (`.github/renovate.json5`).

## Sizing for 4 GB Raspberry Pis

- node6 keeps the control-plane `NoSchedule` taint; node2, node3 (etcd-only) and node4 also run light, stateless workloads (`k3s_control_plane_taint: false` in host_vars).
- The kubelet reserves memory for k3s and the OS (`k3s_kube_reserved_memory`: 1700Mi on servers, 3072Mi on node6, 768Mi on etcd-only servers, 600Mi on workers, plus 300Mi for the system) and evicts pods below 300Mi free.
- One pod per service, no replicas, except CoreDNS: two replicas on different nodes, because cluster DNS going down stops Flux, Longhorn and everything else.
- Longhorn runs on the SSD nodes only (`node_storage=longhorn`): node3, node5, and node6, left from Kafka (Longhorn tolerates its control-plane taint, other pods with volumes do not). Prometheus, Alertmanager and Grafana are pinned to workers that are storage nodes (`node_type=worker` + `node_storage=longhorn`).
- Logs, traces and Rancher came with Cluster 2.0, once node6 was the only API server (2026-11-06). Istio and Kafka were removed (2026-11-07): node6 has no CPU left for them.

## Known limits

- Rancher does not fit 4 GB API servers. Its cluster agent watches every resource type, which adds about 700Mi to every API server; on the 4 GB control plane node3 started to thrash. Rancher runs on node6 (8 GB), the only API server, since 2026-11-06 (k3s there +1.1 GB). Never change the k3s version in Rancher: upgrades go through Renovate and the system-upgrade plans.
- Prometheus has a 900Mi memory limit (640Mi request), below node5's free memory: it is OOM-killed and restarted instead of hanging the node. It stays under the limit with a 60s scrape interval (30s for node-exporter and the kubelet/cAdvisor, because Lens computes rates over 1m windows), 6h / 1GB retention and trimmed kubelet histograms (`app/overlays/prod/values.yaml`).

## Web UIs

All on the Envoy gateway (10.0.0.68, wildcard Let's Encrypt certificate) unless noted.

| UI | URL | Login |
|---|---|---|
| Grafana | https://grafana.homelab.yekvitka.net | own login (`admin`) |
| Longhorn | https://longhorn.homelab.yekvitka.net | basic auth |
| Prometheus | https://prometheus.homelab.yekvitka.net | basic auth |
| Alertmanager | https://alertmanager.homelab.yekvitka.net | basic auth |
| Vault | https://vault.homelab.yekvitka.net:8200/ui/ (node1) | token |
| RustFS console | https://object-store.homelab.yekvitka.net:9092/rustfs/console/ (node1) | `rustfsadmin` |
| OpenWrt LuCI | https://gateway.homelab.yekvitka.net | `root` |
| Gatus | http://10.99.0.2:8080 (offsite VM, tunnel only) | none |

- Basic auth: `SecurityPolicy` in the `route-basic-auth` components. Credentials in Vault `secret/webui/basic-auth` (user `admin`), created by `make configure-webui-auth`: Envoy only accepts SHA htpasswd entries, so the playbook stores the password and the entry, and External Secrets copies the entry into the cluster. Read the password: [reading a secret](quick-start.md#reading-a-secret).
- From the home network (192.168.50.x), add routes for 10.0.0.0/24 and 10.99.0.0/24 through the gateway (192.168.50.200) and use it as DNS server for `homelab.yekvitka.net`, e.g. on macOS: `sudo networksetup -setadditionalroutes "Wi-Fi" 10.0.0.0 255.255.255.0 192.168.50.200 10.99.0.0 255.255.255.0 192.168.50.200`.
- Lens: kubeconfig from pimaster (`~/.kube/config`, API at 10.0.0.10). Settings → Metrics → Prometheus "Auto detect", which finds the `prometheus-operated` service.
