# Offsite: Oracle Cloud VM

An Oracle Cloud Always Free VM (`terraform/oci`, region eu-frankfurt-1) keeps an offsite copy of the backups and monitors the cluster from outside. Ampere A1 (arm64): 1 OCPU, 6 GB, Ubuntu 24.04, 50 GB boot + 150 GB backup volume (ext4 `offsite-backups`, mounted at `/backup`). Free tier, not pay-as-you-go: Oracle may reclaim an idle VM; `tofu apply` and the gateway script recreate it.

## Access

- The home public IP is dynamic (Play), so the VM opens no SSH to the internet. A WireGuard tunnel runs from the OpenWrt gateway (10.99.0.1) to the VM (10.99.0.2): the gateway connects out and keeps it up, no port forwarding at home.
- Oracle security list: UDP 51820 and ICMP 3/4 only (the VCN default list is emptied). On the VM, iptables allows SSH and the Gatus UI on `wg0` only.
- Gateway side: `metal/openwrt/script/wireguard-oci.sh`, firewall zone `oci`: nothing from the VM into home networks except the monitoring targets (`mon_*` rules).
- Secrets on the control host, not in Git: `~/.secrets/oci/` (API key and config), `~/.secrets/wireguard/oci-vm.key`. OCIDs and key paths in `terraform/oci/terraform.tfvars` (gitignored, see `terraform.tfvars.example`).
- The first-boot config (`cloud-init.yaml.tftpl`) runs once: Terraform ignores later changes to it and to the image; the running VM is configured with Ansible (inventory group `oci`).

```shell
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/oci && tofu plan'
ssh ubuntu@10.99.0.2      # from pimaster or the home network (route 10.99.0.0/24 via the gateway)
```

## Offsite backup

`make configure-offsite-backup` (`ansible/offsite_backup.yml`): every night at 05:00 node1 copies `/storage/rustfs` (all RustFS buckets except `k3s-loki`) and a Vault Raft snapshot (`/var/backups/vault/vault.snap`) to the VM with restic over SFTP (`restic-offsite.timer`).

- Encrypted on node1: the VM never gets the password. On the VM the `restic` user is SFTP-only, chrooted to `/backup`.
- Retention 7 daily, 4 weekly, 6 monthly (grouped by host and tag).
- The repository password is `~/.secrets/restic-offsite.password` on the control host: keep a copy in a password manager, the offsite copy cannot be read without it.
- Vault is copied as a Raft snapshot, never as files (`/storage/vault` is live Raft storage): `vault-raft-snapshot.sh` runs before restic with a periodic orphan token that only has the `raft-snapshot` policy (`terraform/vault`), stored in `/etc/restic/vault-snapshot.token` and renewed by every snapshot. A failed snapshot does not stop the RustFS copy.
- `terraform/vault` must be planned with `TF_VAR_enable_kubernetes_auth=true` (`enable_kubernetes_auth: true` in `vars/picluster.yml`): with false it plans to destroy the Kubernetes auth backend External Secrets depends on.

## Outside monitoring

`make configure-offsite-monitoring` (`ansible/offsite_monitoring.yml`): Gatus on the VM checks Grafana, the k3s API, Vault, RustFS, LuCI and bind9 through the tunnel, plus certificate expiry (alert below 7 days). UI on http://10.99.0.2:8080 (tunnel only). The checks right after a VM boot fail until the tunnel is up. No notifications yet.
