# Platform catalog

Every app in `kubernetes/platform/`. **prod** apps are listed in `kubernetes/clusters/prod/infra/kustomization.yaml` and reconciled by Flux; the others are kept for later use and not deployed.

| App | Status | What it does here |
|---|---|---|
| cert-manager | prod | Let's Encrypt wildcard certificate (IONOS DNS-01 webhook), internal CA |
| cilium | prod | CNI, kube-proxy replacement, LoadBalancer IPs (L2), Hubble metrics |
| coredns | prod | Cluster DNS |
| csi-external-snapshotter | prod | CSI snapshot CRDs and controller (Velero → Longhorn) |
| envoy-gateway | prod | Gateway API: `public-gateway` on 10.0.0.68, TLS for all web UIs |
| external-dns | prod | Publishes routes to bind9 on node1 (RFC 2136) |
| external-secrets | prod | Secrets from Vault (node1) into the cluster |
| flux-operator | prod | Flux instance (GitOps), syncs `master` |
| grafana | prod | Grafana operator and instance, dashboards |
| k3s-etcd-backup | prod | S3 settings for k3s etcd snapshots (from Vault) |
| kube-prometheus-stack | prod | Prometheus, Alertmanager, node-exporter, kube-state-metrics, k3s mixins |
| kube-vip | prod | Virtual IP 10.0.0.10 for the k3s API |
| longhorn | prod | Block storage on the SSD nodes, one replica per volume |
| metrics-server | prod | Resource metrics (`kubectl top`) |
| system-upgrade | prod | k3s upgrades from Git (upgrade plans) |
| vault | prod | Vault agent injector (Vault itself runs on node1) |
| velero | prod | Daily backups to RustFS |
| loki | planned ([Cluster 2.0](../../docs/plans/cluster-2.0.md)) | Logs, Simple Scalable, S3 on RustFS |
| fluent | planned | Fluent Bit straight to Loki (`components/loki`); Fluentd is kept, not used |
| rancher | planned | Rancher on node6, the only API server |
| tempo | planned | Tracing |
| opentelemetry-collector | planned | Telemetry pipeline |
| istio | planned | Service mesh, ambient mode (with the Cilium `istio-config` component) |
| kiali | planned | Istio console |
| kafka | planned | Strimzi Kafka, one broker; Kafdrop and Schema Registry when used |
| descheduler | planned, needs a safer policy | It packed evicted pods onto the emptiest node, which then ran out of memory |
| databases | upstream, not deployed | CloudNativePG, MongoDB and Valkey operators |

The Elastic stack (ECK, Elasticsearch, Kibana) and Keycloak were removed from the repo (2026-11-02): Elastic does not fit the Pis and Loki covers logs; the Keycloak operator fails on arm64. Web UIs use basic auth at the gateway, Kiali its token login.

## Layout

```
<app>/
├── app/          HelmRelease: base/, components/, overlays/{dev,prod}/
└── config/       resources applied after the app (depends on <app>-app)
```

Each prod app has a Flux `Kustomization` in `kubernetes/clusters/prod/infra/<app>-app.yaml`. Environment values go in `overlays/<env>/values.yaml`; cluster-wide settings come from the `cluster-settings` ConfigMap (`${CLUSTER_DOMAIN}`, …). New apps: `boilerplate/`.
