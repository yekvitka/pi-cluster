# Runbook: move a control plane node to SSD boot

pimaster is a VM without USB, so the SSD is flashed from the node itself while it still runs from its SD card (or from node1 for a new node). The cluster keeps etcd quorum (2 of 3) throughout.

1. Backups: `k3s etcd-snapshot save --name pre-<node>-ssd` on another server, and a Velero backup.
2. On the node: download the Ubuntu image and check it against `SHA256SUMS`, then `xz -dc <img> | dd of=/dev/disk/by-id/usb-<ssd> bs=4M conv=fsync`. Mount the SSD's `system-boot` partition and write `user-data` (from `metal/rpi/cloud-init/nodes/user-data`, `nodeX` and `SSH_PUB_KEY` replaced as in the Makefile) and `network-config` (a copy of the node's `/etc/netplan/50-cloud-init.yaml`: it keeps the Wi-Fi key on the node).
3. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`, then `systemctl disable --now k3s` on the node, then `kubectl delete node <node>`. k3s removes the etcd member on node delete (`Removing etcd member from cluster due to node delete` in the other servers' k3s log).
4. Power off, remove the SD card (keep it: the rollback), power on. First boot grows the root partition and runs cloud-init.
5. From pimaster: `ssh-keygen -R <ip>`, also inside the runner (`docker exec ansible-runner ssh-keygen -f /home/runner/.ssh/known_hosts -R <ip>`), then with `--limit <node>`: `update.yml`, `setup_picluster.yml --tags node`, `k3s_install.yml`. The node joins as an etcd learner and is promoted.
6. system-upgrade-controller runs the `k3s-server` plan on the new node and cordons it until done. The upgrade script can fail with `Found multiple K3s pids` (it counts its own `k3s kubectl`); the Job retries and the node is uncordoned once the plan completes (`plan.upgrade.cattle.io/k3s-server` label).

Rollback before step 3: wipe the SSD. After step 3: unplug the SSD, insert the SD card (SD boots first), delete `/var/lib/rancher/k3s/server/db` on the node and rerun `k3s_install.yml --limit <node>`.

## Convert a server's role (etcd-only, agent)

Cluster 2.0 conversions (node3 to etcd-only, 2026-11-06), with 4 etcd members so quorum holds throughout:

1. `k3s etcd-snapshot save --name pre-<phase>` on another server.
2. Longhorn volumes whose only replica is on the node: stop their pods so the volumes detach. Grafana: `flux suspend kustomization grafana-instance`, then `spec.deployment.spec.replicas: 0` on `grafanas.grafana.integreatly.org/grafana` (the short name `grafana` resolves to an External Secrets generator). Alertmanager: `spec.replicas: 0` on the `Alertmanager` resource.
3. Longhorn's default `node-drain-policy` (`block-if-contains-last-replica`) blocks the drain even with those replicas stopped: set `allow-if-replica-is-stopped` for the conversion. `csi-attacher` and `csi-provisioner` (one replica each) keep a `minAvailable: 1` PDB while any volume is attached elsewhere: if they run on the node, delete their pods (a delete is not an eviction) and they start on another node.
4. `kubectl drain`, `systemctl disable --now k3s`, `kubectl delete node <node>` (k3s removes the etcd member), then move `/var/lib/rancher/k3s/server/db` aside (`db.pre-<phase>`) and set the host_vars (`k3s_etcd_only`, `k3s_kube_reserved_memory`).
5. `k3s_install.yml --limit <node>`. The role starts k3s itself: the install script skips the start when nothing changed (`No change detected`), which left node3 down before the role was fixed.
6. Check `kubectl get node <node> -o jsonpath='{.spec.unschedulable}'`: before the `k3s-agent` plan required `node_type=worker`, a rejoining server matched it for a few seconds and its job, deleted mid-way, left the node cordoned (Longhorn then cannot start the node's instance manager). Uncordon if needed.
7. Scale the pods back up, remove the Grafana `replicas` override, resume Flux, set `node-drain-policy` back to `block-if-contains-last-replica`.

An etcd-only server listens on 6443 (k3s supervisor, `/api` answers 503) and 6444 (local load balancer); the `kubernetes` Service endpoints list only real API servers.

## Corrupted etcd member

A hard power cut can corrupt a member's database (`panic: freepages: failed to get all reachable pages` or `panic: assertion failed: Page expected to be ...` in the k3s log, k3s restarting in a loop). On node2 and node3 `k3s-etcd-selfheal` does this by itself (node annotation `etcd.k3s.cattle.io/remove=true` instead of deleting the node, then the database moved aside); `DRYRUN=1 /usr/local/sbin/k3s-etcd-selfheal` shows what it sees. 2026-11-08 power cut: node3's database corrupted again (old SandForce SSD, write cache already off); the script removed the member and node3 rejoined by itself 13 minutes after power-on (the API was slow, the first version gave up waiting). By hand, for node6 or when the API is down, with the other two members healthy: snapshot, `systemctl stop k3s` on the node, `kubectl delete node <node>` (removes the member), delete `/var/lib/rancher/k3s/server/db` on the node, `systemctl start k3s`. It rejoins as a learner and is promoted. Move the database aside (`db.corrupt-<date>`) instead of deleting it. node3, 2026-11-08: 5 minutes, voter again 55 s after the start; the faulted single-copy Longhorn volumes on node3 (Grafana, Alertmanager, Loki) recovered by themselves once node3 was back.

## Longhorn node selector

Changing `systemManagedComponentsNodeSelector` or `taintToleration` (Longhorn) is applied only with all Longhorn volumes detached (Loki write and backend have volumes too): scale down Prometheus, Alertmanager and Grafana (suspend their Flux Kustomizations and HelmReleases first), let Flux upgrade Longhorn, then scale back up. Done this way on 2026-11-06 for node6 (7 min): suspend the `longhorn` HelmRelease before the change is merged, `spec.replicas: 0` on the Prometheus and Alertmanager resources and on `grafanas.grafana.integreatly.org/grafana`, `kubectl scale sts loki-write loki-backend --replicas=0` (`loki` HelmRelease suspended), resume `longhorn` once every volume is detached. Afterwards Fluent Bit resends its backlog: Loki write needs CPU to catch up (limit 1 core), and if queries hang once the write pod has a new IP, restart `deploy/loki-read`. Existing volumes keep their replica count: set `numberOfReplicas` on each `volumes.longhorn.io`.
