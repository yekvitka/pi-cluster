# k3s mixins

The dashboards and alert rules of kube-prometheus-stack come from the monitoring mixins (kubernetes, node-exporter, CoreDNS, Grafana, Prometheus, Prometheus Operator), which assume a standard Kubernetes control plane. k3s runs the API server, scheduler, controller manager and etcd inside one process and exposes their metrics through the kubelet endpoint, so the stock dashboards show gaps and the stock alerts fire on missing targets.

This build renders the mixins with k3s settings into `../base`:

- every component's metrics are selected from the kubelet job, etcd included;
- `showMultiCluster` is off, so dashboards have no `cluster` variable (as the Helm chart's own generator does);
- dashboards are written as YAML without escaping.

```shell
make k3s-mixins
```

Based on Adin Hodovic's [k3s compatibility guide for kube-prometheus-stack](https://hodovi.cc/blog/configuring-kube-prometheus-stack-dashboards-and-alerts-for-k3s-compatibility/).
