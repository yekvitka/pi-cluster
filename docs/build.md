# Build from scratch

The chain: cloud-init (OS) → Ansible (hosts, external services, k3s) → Flux (everything in the cluster).

1. Gateway: [metal/openwrt/README.md](../metal/openwrt/README.md).
2. Boot disks (USB SSDs; SD cards for nodes without one yet): put the pimaster user's public key (`/home/pimaster/.ssh/id_rsa.pub`, the key the Ansible runner uses) in `metal/rpi/cloud-init/root.pub`, then from `metal/rpi`:

   ```shell
   make img/ubuntu-24.04.5-preinstalled-server-arm64+raspi.img.xz
   make burn-image USB=/dev/sdX
   export WIFI_SSID='<home ssid>' WIFI_KEY='<home wifi password>'   # wlan0 backup uplink
   make prepare-node1 USB=/dev/sdX SSD1_ID=<node1 SSD1 /dev/disk/by-id name>
   make prepare-node2 USB=/dev/sdX   # node3..node7 the same way
   ```

   Nodes get 10.0.0.1N on eth0 (DNS from the gateway) and 192.168.50.20N on wlan0.

3. Only with `centralized_san: true`: set node1 SSD2 in `ansible/vars/centralized_san/centralized_san_target.yml`.
4. From the repo root on pimaster:

   ```shell
   make prepare-ansible   # ansible runner + secret files (IONOS API key)
   make init              # os-upgrade, node setup, DNS, Vault/RustFS, SAN, k3s, Flux bootstrap
   ```

5. After `make init`:

   ```shell
   make configure-cert-renewal        # automatic certificate renewal on node1
   make configure-webui-auth          # basic auth credentials for the web UIs
   make configure-offsite-backup      # needs the Oracle VM (terraform/oci, docs/offsite.md)
   make configure-offsite-monitoring
   ```

`k3s_cluster_init_node` (vars/picluster.yml) names the server that runs `cluster-init`; point it at the first server installed.
