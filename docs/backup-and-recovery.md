# Backup and recovery

Three copies, two locations, one of them offsite and encrypted.

| What | How | When | Where | Kept |
|---|---|---|---|---|
| Kubernetes resources | Velero | daily 04:00 | RustFS `k3s-velero` (node1) | 30 days |
| Longhorn volumes | Velero CSI snapshots → Longhorn backups | daily 04:00 | RustFS `k3s-longhorn` | 30 days |
| etcd | k3s etcd snapshots | every 12h | each server + RustFS `k3s-etcd` | last 5 |
| Node configuration | restic (`make configure-os-backup`) | daily 03:00 | RustFS `restic` | restic policy |
| Vault | Raft snapshot (`vault-raft-snapshot.sh`) | nightly, before the offsite copy | node1 `/var/backups/vault` | offsite policy |
| All of the above | restic over SFTP through WireGuard, encrypted on node1 | daily 05:00 | Oracle Cloud VM `/backup/restic` | 7 daily, 4 weekly, 6 monthly |

- RustFS and Vault run on node1, outside the cluster: rebuilding the cluster (`make k3s-install`, `make k3s-bootstrap`) does not touch secrets or backups.
- The k3s etcd S3 settings come from the `kube-system/k3s-etcd-snapshot-s3-config` secret (External Secrets, Vault `s3/etcd`).
- The offsite copy skips `/storage/rustfs/k3s-loki` (logs, 7 days retention).
- Details of the offsite copy, the Vault snapshot token and restore checks: [offsite](offsite.md).

## Restore checks

- restic: `restic check --read-data-subset=5%` and a file restore compared with `sha256sum` (node1, `set -a; . /etc/restic/offsite.env`).
- Vault: `vault operator raft snapshot inspect <file>` on a restored `vault.snap` (as root on node1).
- etcd: `k3s etcd-snapshot ls` on a server; restore with `k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>`.

## After a full power cycle

Vault unseals itself (`vault-unseal.service`), but ExternalSecrets that failed while Vault was unreachable wait for their refresh interval and block the Flux chain (cert-manager-config first). Check `kubectl get externalsecret -A`; re-sync the failed ones with `kubectl annotate externalsecret <name> -n <ns> force-sync=$(date +%s) --overwrite`.
