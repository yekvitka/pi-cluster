# Control host (pimaster)

Ubuntu 24.04 VM (6 GB memory, 6 CPUs), not managed by Ansible. It runs the Ansible runner container and holds the secrets that never go to Git (`~/.secrets`, `~/.certbot`, `~/.kube`, `~/.ssh`) and the local Terraform state. A move off the VM (laptop now, an always-on node later) is planned; copy those directories and `terraform/*/terraform.tfstate`.

The cluster LAN and the home network share one switch, so pimaster has an address on both and reaches the nodes directly, without the gateway route. Netplan replaces the installer config (cloud-init network config is disabled in `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`):

```yaml
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s1:
      dhcp4: false
      addresses:
      - 192.168.50.100/24
      - 10.0.0.20/24
      nameservers:
        addresses:
        - 10.0.0.1
        search:
        - homelab.yekvitka.net
      routes:
      - to: 0.0.0.0/0
        via: 192.168.50.1
        metric: 100
      - to: 0.0.0.0/0
        via: 10.0.0.1
        metric: 200
      - to: 10.99.0.0/24
        via: 10.0.0.1   # WireGuard tunnel to the Oracle VM
```

DNS comes only from the gateway, as on the nodes. The home router hands out its own IPv6 DNS servers, so a networkd drop-in ignores them:

```ini
# /etc/systemd/network/10-netplan-enp0s1.network.d/no-ipv6-dns.conf
[IPv6AcceptRA]
UseDNS=false
UseDomains=false

[DHCPv6]
UseDNS=false
UseDomains=false
```

Apply with `sudo netplan apply`, check with `resolvectl status enp0s1`.

Disk: 32 GB. The Ubuntu installer gives the root LV only half of the volume group. Extend it to the whole VG:

```shell
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```

The runner mounts `~/.ssh/known_hosts`: Ansible checks host keys and trusts a new host on first use; after a node is reprovisioned, remove its old key with `ssh-keygen -R <ip>`.

The runner wrapper asks Docker for a TTY only when it runs in one, so scripts and non-interactive shells call it directly. Start the runner as the user who owns `~/.ssh` and `~/.secrets`, never as root (`make ansible-runner-setup` refuses). `make verify` runs every CI check in the runner.
