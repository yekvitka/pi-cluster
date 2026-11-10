# Quick start

Build your own cluster from this repository. You need:

- the hardware in [hardware and network](hardware-and-network.md): Raspberry Pi 4 boards for the gateway, node1 (with an SSD) and the k3s nodes, USB SSDs for the storage nodes, one switch;
- a domain with its DNS at IONOS: certificates use Let's Encrypt with the IONOS DNS-01 challenge, so no port opens at home;
- a Linux control host with Docker, curl and jq (this cluster's own: [control host](control-host.md)).

The chain: cloud-init installs the OS, Ansible configures the hosts, the external services and k3s, Flux deploys everything in the cluster from your fork.

## 1. Fork and clone

Fork the repository on GitHub (Flux pulls from your fork), then clone it on the control host.

## 2. Make it yours

Edit these files. Everything not listed is the reference design and works as is.

| File | Set |
|---|---|
| `ansible/inventory.yml` | the MAC address of each node (hostnames and IPs only if you change the IP plan or the number of nodes) |
| `ansible/group_vars/all.yml` | `dns_domain` (your homelab subdomain), `ntp_timezone`, `iscsi_initiator_iqn_prefix`, `git_private_repo` |
| `ansible/vars/picluster.yml` | `acme_issuer_email` |
| `kubernetes/clusters/prod/config/cluster-settings.yaml` | `CLUSTER_DOMAIN`, `S3_SERVER` |
| `kubernetes/platform/flux-operator/instance/overlays/prod/values.yaml` | `instance.sync.url`: your fork |
| `kubernetes/platform/cert-manager/config/components/acme-ionos/ionos-issuer.yaml` | ACME `email`; `groupName` (a name under your domain) |
| `kubernetes/platform/cert-manager/webhook-ionos/base/values.yaml` | the same `groupName` |
| `metal/rpi/cloud-init/nodes/network-config` | the DNS search domain; your home network on wlan0 (subnet and router) |
| `metal/rpi/cloud-init/ansible.pub` | the ansible user's public keys, one per line: the control host's and the break-glass key (not in Git) |
| `.github/renovate.json5` | your fork in the preset paths, if you run Renovate |

The gateway's home network, Wi-Fi and time zone are passed when its image is built (step 4). For the local k3d cluster (`dev/`), set your domain and fork in `kubernetes/clusters/dev/config/` and in the dev overlay of the Flux instance too.

### The reference IP plan

The cluster LAN is 10.0.0.0/24 behind the gateway: gateway 10.0.0.1, k3s API (kube-vip) 10.0.0.10, node1 10.0.0.11, nodes 10.0.0.12 and up, control host 10.0.0.20, load balancers 10.0.0.64/26 (Envoy Gateway on 10.0.0.68). To use other addresses, change them in `ansible/inventory.yml`, `ansible/group_vars/all.yml` (`default_gateway`, `dns_server`), `ansible/vars/picluster.yml` (`k3s_api_vip`), `ansible/host_vars/node1.yml` (DNS records), `cluster-settings.yaml`, `kubernetes/platform/cilium/config/base/ip-pool-lb.yaml`, `kubernetes/platform/kube-vip/overlays/prod/values.yaml`, the control-plane endpoints in `kubernetes/platform/kube-prometheus-stack/app/base/values.yaml`, `metal/rpi/cloud-init/nodes/network-config` and the addresses at the top of `metal/openwrt/gateway-setup.sh`.

## 3. Secrets

No secret is in Git. Two come from you; the rest are generated during the build.

| Secret | Created by | Kept in |
|---|---|---|
| IONOS API key | you, when `make secret-files` asks | `~/.secrets/ionos-credentials.ini`, Vault |
| GitHub token (private fork only) | you, when `make secret-files` asks | `~/.secrets`, Vault |
| Gateway root password | `build-image.sh` | `~/.secrets/openwrt-root-password` |
| Vault unseal keys and root token | `make init` (Vault install) | `~/.secrets/vault.env` |
| Service passwords: S3 users, Grafana, k3s token, ... | `make init` (`terraform/vault`) | Vault |
| Web UI basic auth, bind9 update key | `make init` | Vault |
| Offsite (optional): OCI API key, WireGuard key, restic password | you ([offsite](offsite.md)) | `~/.secrets` |

Keep an encrypted copy of `~/.secrets` and `terraform/*/terraform.tfstate` outside the control host: without them Vault cannot be unsealed and the offsite backup cannot be read.

## 4. Gateway

```shell
sudo WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>' \
  HOME_NET=192.168.1.0/24 HOME_ROUTER=192.168.1.1 WAN_IP=192.168.1.200 \
  WIFI_COUNTRY=DE ZONENAME=Europe/Berlin TIMEZONE='CET-1CEST,M3.5.0,M10.5.0/3' \
  metal/openwrt/build-image.sh
```

Write the image to the gateway's SD card and boot it; the domain comes from `dns_domain`. Then add its node exporter. Details and the manual install: [metal/openwrt](../metal/openwrt/README.md).

## 5. Boot disks

USB SSDs, or SD cards for nodes without one. From `metal/rpi`:

```shell
make img/ubuntu-24.04.5-preinstalled-server-arm64+raspi.img.xz
make burn-image USB=/dev/sdX
export WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>'   # wlan0 backup uplink
make prepare-node1 USB=/dev/sdX SSD1_ID=<node1 SSD1 /dev/disk/by-id name>
make prepare-node2 USB=/dev/sdX   # node3..node6 the same way
```

Nodes get 10.0.0.1N on eth0 (DNS from the gateway) and their home network address on wlan0. `k3s_cluster_init_node` (`ansible/vars/picluster.yml`) names the server that starts the cluster.

## 6. Build

From the repository root on the control host:

```shell
make prepare-ansible   # Ansible runner, secret files
make init              # OS, node setup, DNS, Vault/RustFS, web UI credentials, node1 exporters, k3s, Flux
```

Then the renewal of the certificates outside the cluster (Vault, RustFS, gateway):

```shell
make configure-cert-renewal
```

Optional, with an Oracle Cloud Always Free VM: an encrypted offsite copy of the backups and checks from outside, see [offsite](offsite.md).

## 7. Check

```shell
kubectl get nodes
flux get kustomizations
```

Every node `Ready`, every Kustomization `True`. Grafana answers on `https://grafana.<dns_domain>`.

### Reading a secret

Passwords live in Vault. On the control host, with the address and token that `make init` saved:

```shell
set -a; . ~/.secrets/vault.env; set +a
v() { curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/$1" | jq -r ".data.data.$2"; }

v grafana/admin password        # Grafana, user admin
v webui/basic-auth password     # Longhorn, Prometheus, Alertmanager, user admin
v s3/rustfsadmin key            # RustFS console, user rustfsadmin
```

`VAULT_TOKEN` is the root token: it stays in that shell. As `ansible` on node1 (`ssh ansible@10.0.0.11`) the `vault` CLI works with sudo (`sudo -i`).
