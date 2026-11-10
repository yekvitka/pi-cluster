# Control host (pimaster)

Ubuntu 24.04 VM (6 GB memory, 6 CPUs), not managed by Ansible. It runs the Ansible runner container and holds the secrets that never go to Git (`~/.secrets`, `~/.certbot`, `~/.kube`, `~/.ssh`) and the local Terraform state. It moves to an Oracle Cloud VM ([below](#oracle-cloud-vm), [plan](plans/control-host-oci.md)). Until then, this VM is the control host.

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

## Oracle Cloud VM

Optional (`pimaster_enabled` in `terraform/oci`). The control host runs as an Always Free Ampere A1 VM next to the offsite VM: 3 OCPUs, 18 GB, 50 GB boot, Ubuntu 24.04. It works from any network and does not depend on a laptop being on. The move from the VM above: [plan](plans/control-host-oci.md), phases 1–3.

- **Network:** WireGuard `wg0`, 10.99.0.3.
  - The gateway connects out to it, as it does to the offsite VM (`PIMASTER_ENDPOINT` and `PIMASTER_PUBKEY` of `metal/openwrt/script/wireguard-oci.sh`).
  - pimaster connects to the offsite VM over the VCN.
  - Oracle's security list opens UDP 51820 only, and SSH listens on `wg0` only.
  - The gateway gives pimaster the home network's access (`ctl_*` rules).
- **DNS:** the homelab domain goes to the gateway (10.0.0.1) through the tunnel, everything else to Oracle's resolver (`resolvectl status wg0`).
- **Remote access:** laptops and phones are WireGuard peers of pimaster (10.99.0.16/28, `wg_clients` in `terraform.tfvars`). pimaster forwards them to the cluster LAN and the offsite VM, and they get the same access as pimaster. Laptop profile:

  ```ini
  [Interface]
  PrivateKey = <~/.secrets/wireguard/laptop.key>
  Address = 10.99.0.18/32
  MTU = 1280
  DNS = 10.0.0.1

  [Peer]
  PublicKey = <~/.secrets/wireguard/pimaster-oci.pub>
  Endpoint = <pimaster_public_ip>:51820
  AllowedIPs = 10.99.0.0/24, 10.0.0.0/24
  PersistentKeepalive = 25
  ```

  Then SSH or VS Code Remote-SSH to `pimaster@10.99.0.3`, on any network, at home too: traffic goes through Frankfurt, about 40 ms per round trip.
- **First boot:** `pimaster-cloud-init.yaml.tftpl` creates the `pimaster` user (with the keys from `pimaster_ssh_authorized_keys`, no default `ubuntu` user), WireGuard, the firewall and Docker. It runs once, and Terraform ignores later changes to it.
  - Peers later: edit `/etc/wireguard/wg0.conf`, then `sudo bash -c 'wg syncconf wg0 <(wg-quick strip wg0)'`.
  - The saved iptables rules exclude Docker's own. Never run `netfilter-persistent save` while Docker runs: add a rule with `iptables` and by hand to `/etc/iptables/rules.v4`.
- **Break-glass:** Oracle's serial console (Instance → Console connection). The `pimaster` user gets a password for it once (`sudo passwd pimaster`, kept in a password manager). SSH stays key-only.
