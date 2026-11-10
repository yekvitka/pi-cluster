# Control host (pimaster)

The control host runs the Ansible runner container and holds what never goes to Git: `~/.secrets`, `~/.certbot`, `~/.kube`, `~/.ssh` and the local Terraform state. It is not managed by Ansible. Any Linux host with Docker that reaches the cluster LAN (10.0.0.0/24) can be one; this cluster's runs in Oracle Cloud.

## Oracle Cloud VM

Optional (`pimaster_enabled` in `terraform/oci`). The control host runs as an Always Free Ampere A1 VM next to the offsite VM: 3 OCPUs, 18 GB, 50 GB boot, Ubuntu 24.04. It works from any network and does not depend on a laptop being on. It replaced a VM on the home network on 2026-11-10 ([plan](plans/control-host-oci.md)).

- **Network:** WireGuard `wg0`, 10.99.0.3.
  - The gateway connects out to it, as it does to the offsite VM (`PIMASTER_ENDPOINT` and `PIMASTER_PUBKEY` of `metal/openwrt/script/wireguard-oci.sh`).
  - pimaster connects to the offsite VM over the VCN.
  - Oracle's security list opens UDP 51820 only, and SSH listens on `wg0` only.
  - The gateway gives pimaster the home network's access (`ctl_*` rules). Pings into the cluster LAN fail by design: the rules allow TCP and UDP only.
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
  AllowedIPs = 10.0.0.0/24, 10.99.0.2/32, 10.99.0.3/32
  PersistentKeepalive = 25
  ```

  Then SSH or VS Code Remote-SSH to `pimaster@10.99.0.3`, on any network, at home too: traffic goes through Frankfurt, about 40 ms per round trip. The two VMs are /32 routes because at home the laptop already has a `10.99.0.0/24` route through the gateway (192.168.50.200). macOS keeps that route over a VPN route of the same size, and the gateway lets the home network reach only the offsite VM, so SSH to pimaster would be refused.

  A client key that leaks is replaced on pimaster alone: a new key pair, the peer swapped in `/etc/wireguard/wg0.conf` and live (`wg set wg0 peer <old> remove`, then the new peer), the new public key in `wg_clients` (`tofu plan` stays clean: the first-boot config is ignored after the first boot).
- **First boot:** `pimaster-cloud-init.yaml.tftpl` creates the `pimaster` user (with the keys from `pimaster_ssh_authorized_keys`, no default `ubuntu` user), WireGuard, the firewall and Docker. It runs once, and Terraform ignores later changes to it.
  - Peers later: edit `/etc/wireguard/wg0.conf`, then `sudo bash -c 'wg syncconf wg0 <(wg-quick strip wg0)'`.
  - The saved iptables rules exclude Docker's own. Never run `netfilter-persistent save` while Docker runs: add a rule with `iptables` and by hand to `/etc/iptables/rules.v4`.
- **Break-glass:** Oracle's serial console (Instance → Console connection). The `pimaster` user gets a password for it once (`sudo passwd pimaster`, kept in a password manager). SSH stays key-only.

## Access to the hosts

| Host | User | Keys |
|---|---|---|
| node1–node6 | `ansible`, passwordless sudo. Root logs in on the console only: no SSH keys, `PermitRootLogin no` | `metal/rpi/cloud-init/ansible.pub` (not in Git): the control host's key and a break-glass key |
| gateway | `root` (OpenWrt has no sudo) | `/etc/dropbear/authorized_keys` |
| offsite VM | `ubuntu`, sudo | `ssh_authorized_keys` in `terraform/oci` (first boot only) |

- cloud-init creates the `ansible` user on a fresh install; `ansible/tasks/ansible_user.yml` (in `make external-setup` and `make nodes-setup`, alone with `setup_picluster.yml --tags ansible-user`) keeps its keys equal to `ansible.pub` and empties root's.
- The break-glass key is a passphrase-protected key kept off the control host (`ssh-keygen -t ed25519 -C picluster-breakglass`). With it and a copy of `~/.secrets`, `~/.certbot` and the Terraform state, any Linux host with Docker on the home network can take over if the control host is lost. Test it after any change to `ansible.pub`: `ssh -i <key> -o IdentitiesOnly=yes ansible@10.0.0.14 sudo -n true`.
- A new control host key goes to every node through `ansible.pub` and `--tags ansible-user` (from the old control host, or with the break-glass key), and by hand to the gateway and the offsite VM.

## Runner

The runner mounts `~/.ssh/known_hosts`: Ansible checks host keys and trusts a new host on first use; after a node is reprovisioned, remove its old key with `ssh-keygen -R <ip>`. Other machines that log in to the nodes (the laptop) keep their own `known_hosts` and need the same.

The runner wrapper asks Docker for a TTY only when it runs in one, so scripts and non-interactive shells call it directly. Start the runner as the user who owns `~/.ssh` and `~/.secrets`, never as root (`make ansible-runner-setup` refuses). `make verify` runs every CI check in the runner.

## A control host on the home network

The cluster LAN and the home network share one switch, so a host on it can take a second address on the cluster LAN (for example 10.0.0.20) and reach the nodes without the gateway; otherwise it needs a route to 10.0.0.0/24 through the gateway (192.168.50.200), like any home device ([OpenWrt](../metal/openwrt/README.md#home-network-access)). Either way, DNS should come from the gateway only: the home router also hands out its own IPv6 DNS servers, which a networkd drop-in ignores (`[IPv6AcceptRA]` and `[DHCPv6]` with `UseDNS=false`, `UseDomains=false`).
