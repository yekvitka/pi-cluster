# Dev cluster (k3d)

A local k3s cluster in Docker (one server, two agents) started with the real cluster's k3s flags: no flannel, kube-proxy, CoreDNS, Traefik, ServiceLB, local storage or metrics-server. It tests Cilium and Helm chart values before they reach the real cluster.

Needs Docker, k3d, Helm and `envsubst`.

```shell
cd dev
make create-k3d                 # kubeconfig in dev/kubeconfig
export KUBECONFIG=$PWD/kubeconfig
```

The cluster never touches the default kubeconfig: on the control host it points to the real cluster, and Ansible uses its current context.

Cilium with the repository's values (chart version from `kubernetes/platform/cilium/app/base/helm.yaml`); the nodes become `Ready`:

```shell
helm upgrade --install cilium oci://quay.io/cilium/charts/cilium --version <version> -n kube-system \
  -f ../kubernetes/platform/cilium/app/base/values.yaml \
  -f ../kubernetes/platform/cilium/app/overlays/dev/values.yaml --wait
```

Other charts the same way, base values then the dev overlay.

Known limit: with these Cilium values, pods in k3d do not reach the Kubernetes API Service (10.43.0.1). CoreDNS installs but stays not ready, so Flux and the apps do not run here.

```shell
make delete-k3d
```
