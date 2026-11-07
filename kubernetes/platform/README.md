# Platform catalog

Every app in `kubernetes/platform/`. **prod** apps are listed in `kubernetes/clusters/prod/infra/kustomization.yaml` and reconciled by Flux; the [Cluster 2.0](../../docs/plans/cluster-2.0.md) plan added Loki, Rancher, Tempo and Hubble.

| App | Status | What it does here |
|---|---|---|
| cert-manager | prod | Let's Encrypt wildcard certificate (IONOS DNS-01 webhook), internal CA |
| cilium | prod | CNI, kube-proxy replacement, LoadBalancer IPs (L2), Hubble metrics, relay and UI (`hubble.${CLUSTER_DOMAIN}`, basic auth) |
| coredns | prod | Cluster DNS |
| csi-external-snapshotter | prod | CSI snapshot CRDs and controller (Velero → Longhorn) |
| envoy-gateway | prod | Gateway API: `public-gateway` on 10.0.0.68, TLS for all web UIs |
| external-dns | prod | Publishes routes to bind9 on node1 (RFC 2136) |
| external-secrets | prod | Secrets from Vault (node1) into the cluster |
| flux-operator | prod | Flux instance (GitOps), syncs `master` |
| fluent | prod | Fluent Bit on every node straight to Loki (`components/loki`) |
| grafana | prod | Grafana operator and instance, dashboards; Prometheus, Loki and Tempo datasources |
| k3s-etcd-backup | prod | S3 settings for k3s etcd snapshots (from Vault) |
| kube-prometheus-stack | prod | Prometheus, Alertmanager, node-exporter, kube-state-metrics, k3s mixins |
| kube-vip | prod | Virtual IP 10.0.0.10 for the k3s API |
| loki | prod | Logs, Simple Scalable (one pod per component), S3 on RustFS, 7 days |
| longhorn | prod | Block storage on the SSD nodes (node3, node5), one replica per volume |
| metrics-server | prod | Resource metrics (`kubectl top`) |
| opentelemetry-collector | prod | OTLP in (`otel-collector.${CLUSTER_DOMAIN}`), traces to Tempo, span metrics to Prometheus, logs to Loki |
| rancher | prod | Rancher on node6, the only API server (`rancher.${CLUSTER_DOMAIN}`); k3s versions stay with system-upgrade |
| system-upgrade | prod | k3s upgrades from Git (upgrade plans) |
| tempo | prod | Tracing (tempo-distributed), S3 on RustFS |
| vault | prod | Vault agent injector (Vault itself runs on node1) |
| velero | prod | Daily backups to RustFS |
| descheduler | not used | Dropped (2026-11-06): it packed evicted pods onto the emptiest node |

Istio, Kiali and Kafka were removed (2026-11-07, node6 has no CPU left for them) and deleted from the repo; git history keeps them.

Web UIs without their own login get basic auth at the gateway.

## Layout

```
<app>/
├── app/          HelmRelease: base/, components/, overlays/{dev,prod}/
└── config/       resources applied after the app (depends on <app>-app)
```

Each prod app has a Flux `Kustomization` in `kubernetes/clusters/prod/infra/<app>-app.yaml`. Environment values go in `overlays/<env>/values.yaml`; cluster-wide settings come from the `cluster-settings` ConfigMap (`${CLUSTER_DOMAIN}`, …). New apps: `boilerplate/`.
