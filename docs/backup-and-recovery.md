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
- Vault: `vault operator raft snapshot inspect <file>` on a restored `vault.snap` (on node1 with sudo: `ssh ansible@10.0.0.11`).
- etcd: `k3s etcd-snapshot ls` on a server; restore with `k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>`.

## Full rebuild

`make clean`, then `make init`, then `make configure-cert-renewal`, `make configure-offsite-backup` and `make configure-offsite-monitoring`. The nodes keep their OS; Vault, RustFS and k3s start empty.

Measured 2026-11-10, from the control host in Oracle Cloud (about 40 ms to the nodes), Ansible as `ansible`:

| Step | Time |
|---|---|
| `make clean` (k3s reset 316 s, Vault and RustFS reset 171 s) | 8.1 min |
| `make init` | 33.9 min |
| — `os-upgrade` | 291 s |
| — `external-setup` | 158 s |
| — `nodes-setup` | 187 s |
| — `dns-setup` | 39 s |
| — `external-services` (Vault, RustFS, Terraform) | 307 s |
| — `configure-webui-auth`, `configure-os-backup`, `deploy-monitoring-agent` | 4 + 108 + 63 s |
| — `k3s-install` (node6 first, then node2, node3, the workers) | 836 s |
| — `k3s-bootstrap` (Flux installed; the apps follow) | 37 s |
| Flux: every Kustomization and HelmRelease ready after `init` | 18 min |
| `make configure-cert-renewal`, `make configure-offsite-backup`, `make configure-offsite-monitoring` | 42 + 63 + 7 s |

About an hour from `make clean` to a ready cluster, without a manual step. Checks that passed: 37 Flux Kustomizations, 22 HelmReleases and 11 ExternalSecrets ready, 71 Prometheus targets up, 5 Longhorn volumes healthy, an etcd snapshot in RustFS `k3s-etcd`, a Velero backup (3422 items, 5 CSI snapshots) in 2.8 minutes, Gatus green, a manual offsite run (113 MiB, 28 s) with a fresh Vault snapshot, no node accepting root SSH. The node1 certificates came from the existing certbot lineages (no new order); the cluster wildcard `pi-cluster-tls` is ordered again on every rebuild, since cert-manager keeps no state outside the cluster (Let's Encrypt allows 5 identical certificates a week). Rancher's Fleet pods restart a few times while Rancher starts.

## Power cycle

Planned: `make shutdown-picluster` halts node1-node6 within a minute; cut the power when the green LEDs stay off. A power outage (no UPS) has to work too: the cluster comes back by itself, losing some recent data is acceptable. Power on everything at once; the gateway must be up for the nodes to get the time.

On start, without manual steps:

- Every Pi waits for chrony to sync the clock before its services start (`chrony-wait`, at most 180 s; `ansible/tasks/boot_order.yml`, applied by `make nodes-setup` and `make external-setup`, alone with `setup_picluster.yml --tags boot-order`). The Pis have no battery clock and boot up to days behind: services started on the wrong time issue leases and tokens with it (Vault logins failed with "invalid not before"), and every ExternalSecret looks due for a refresh while Vault may still be down.
- node1: Vault and RustFS also wait for the DATA SSD (`/storage`), so they never start on an empty directory; `vault-unseal.service` unseals Vault.
- etcd needs two of node2, node3 and node6.
- A filesystem check at boot repairs what it finds (`fsck.repair=yes`) instead of waiting at an emergency shell; the USB disks run without their volatile write cache, which the USB-SATA bridges here do not reliably write out (`ansible/tasks/power_loss.yml`, tag `power-loss`). Not node6 (`usb_disk_write_cache: true`): its SSD took 49 ms per synced write without the cache and etcd on the only API server became unhealthy.
- A corrupted etcd database (k3s panics in bbolt, or fails with `failed to read consistent index`, on every start) heals itself on every server: after two such starts `k3s-etcd-selfheal` (k3s `ExecStartPre`) removes the member, moves the database aside and k3s rejoins as a new member. node2 and node3 ask the API to remove it; node6, the only API server, removes it with etcdctl through node2 and node3, only when both are healthy and after a snapshot from one of them. node6 joins through node3 (`k3s_join_server`), not through the API virtual IP it serves itself. A lost quorum (two members corrupted) still needs the [runbook](runbooks/node-ssd-migration.md#corrupted-etcd-member).
- Flux retries a failed app every 2 minutes (`retryInterval` patch in `kubernetes/clusters/prod/infra/kustomization.yaml`), instead of after its 30-minute interval.
- The kubelet's graceful shutdown marks the pods it stops as Failed or Succeeded; their replacements start, the old pods stay listed (Error or Completed) until `pod-cleanup` deletes them, within 10 minutes.

Measured 2026-11-08 (`make shutdown-picluster`, power off ~10 minutes): all Pis up 1 minute after power-on, the API answers through the VIP after 6 minutes, every Flux app is ready after 9 minutes, no manual step. The clocks booted ~3 minutes behind; chrony then needed 3.5 minutes from the gateway (no `iburst`), so k3s on node3-node6 started on the 180 s timeout.

Hard power cut 2026-11-08 (no shutdown, ~3 minutes off): with `iburst` every clock synced 26-35 s after boot and k3s started right after; the API was back 1.3 minutes after the Pis. node3's etcd database was corrupted (`panic: freepages`), recovered with the runbook in 5 minutes; Grafana, Alertmanager and Loki (single volume copies on node3) were down until then and Longhorn recovered their volumes by itself. Two fixes from that boot: kube-vip's IPVS load balancer is off (its health check restarted kube-vip and dropped the VIP while node6 was busy), and Loki rejoins memberlist every minute (loki-read had started alone and never got ready).

Check: every node `Ready`, `kubectl get kustomization -A`, `kubectl get helmrelease -A`, `kubectl get externalsecret -A` all ready, no pod outside `Running`/`Completed`, no alert firing in Alertmanager but `Watchdog`. An ExternalSecret that stays `SecretSyncedError` while `vault-backend` is valid waits out ESO's retry backoff (up to ~16 minutes): `kubectl annotate externalsecret <name> -n <ns> force-sync=$(date +%s) --overwrite`.
