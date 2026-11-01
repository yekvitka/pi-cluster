# Platform

What runs in the cluster, how it is sized and where it differs from [upstream](https://github.com/ricsanfre/pi-cluster). The catalog of every app in the repo, with its status, is in [kubernetes/platform](../kubernetes/platform/README.md).

## Differences from upstream

- 5 Raspberry Pis + OpenWrt gateway; no x86 nodes, no PXE server.
- BCM2835 hardware watchdog enabled on every Pi (`rpi_watchdog_sec`, basic_setup role): a hung node reboots itself.
- Optional centralized iSCSI SAN on node1, disabled ([hardware](hardware-and-network.md#storage)).
- Ansible connects as `root`; SSH key from `metal/rpi/cloud-init/root.pub`.
- Only core and monitoring apps are enabled in `kubernetes/clusters/prod/infra/kustomization.yaml`. The other upstream apps stay in `kubernetes/platform/`, not deployed.
- k3s held on 1.36.x (`.github/renovate.json5`): Renovate proposes 1.36 patch releases only.
- External services (Vault, RustFS, bind9) run on node1, outside the cluster: the cluster can be rebuilt without losing secrets or backups.

## Sizing for 4 GB Raspberry Pis

- node2 keeps the control plane `NoSchedule` taint (etcd only); node3 and node4 also run light, stateless workloads (`k3s_control_plane_taint: false` in host_vars).
- The kubelet reserves memory for k3s and the OS (`k3s_kubelet_config`: `k3s_kube_reserved_memory`, default 1700Mi on servers and 600Mi on workers, plus 300Mi system) and evicts pods below 300Mi free.
- One pod per service, no HA (CoreDNS included).
- Longhorn runs on the SSD nodes only (`node_storage=longhorn`). Prometheus, Alertmanager and Grafana are pinned to workers that are storage nodes (`node_type=worker` + `node_storage=longhorn`).
- Disabled as unused: descheduler (it packed evicted pods onto the emptiest node, which then ran out of memory), tofu-controller (Terraform runs from the runner), Hubble relay and UI (Hubble metrics stay).
- Logs (Loki, Fluent Bit) and Rancher come with [Cluster 2.0](plans/cluster-2.0.md); traces (Tempo, OpenTelemetry) are not deployed.

## Known limits

- Rancher does not fit the 4 GB control plane. In the cluster its controllers exhaust the control plane nodes. Running Rancher on pimaster and importing the cluster failed too: the cattle-cluster-agent (500–700Mi) watches every resource type, which grew k3s-server by about 700Mi on each master and made node3 thrash. It returns on the 8 GB control plane of Cluster 2.0.
- Prometheus has a 900Mi memory limit (640Mi request), below node5's free memory: it is OOM-killed and restarted instead of hanging the node. It keeps memory under the limit with a 60s scrape interval (30s for node-exporter and the kubelet/cAdvisor: Lens computes rates over 1m windows), 6h / 1GB retention and trimmed kubelet histograms (`app/overlays/prod/values.yaml`).

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

- Basic auth: `SecurityPolicy` in the `route-basic-auth` components. The upstream route components use OIDC with Keycloak, which is not deployed. Credentials in Vault `secret/webui/basic-auth` (user `admin`), created by `make configure-webui-auth`: Envoy only accepts SHA htpasswd entries, so the playbook stores the password and the entry; External Secrets copies the entry into the cluster. Read the password with `vault kv get -field=password secret/webui/basic-auth`.
- From the home network (192.168.50.x), add routes for 10.0.0.0/24 and 10.99.0.0/24 through the gateway (192.168.50.200) and use it as DNS server for `homelab.yekvitka.net`, e.g. on macOS: `sudo networksetup -setadditionalroutes "Wi-Fi" 10.0.0.0 255.255.255.0 192.168.50.200 10.99.0.0 255.255.255.0 192.168.50.200`.
- Lens: kubeconfig from pimaster (`~/.kube/config`, API at 10.0.0.10). Settings → Metrics → Prometheus "Auto detect" (it finds the `prometheus-operated` service); the manual Prometheus Operator setting showed no metrics.
