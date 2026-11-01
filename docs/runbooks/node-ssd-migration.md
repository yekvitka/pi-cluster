# Runbook: move a control plane node to SSD boot

pimaster is a VM without USB, so the SSD is flashed from the node itself while it still runs from its SD card (or from node1 for a new node). Done for node3; the cluster keeps etcd quorum (2 of 3) throughout.

1. Backups: `k3s etcd-snapshot save --name pre-<node>-ssd` on another server, and a Velero backup.
2. On the node: download the Ubuntu image and check it against `SHA256SUMS`, then `xz -dc <img> | dd of=/dev/disk/by-id/usb-<ssd> bs=4M conv=fsync`. Mount the SSD's `system-boot` partition and write `user-data` (from `metal/rpi/cloud-init/nodes/user-data`, `nodeX` and `SSH_PUB_KEY` replaced as in the Makefile) and `network-config` (a copy of the node's `/etc/netplan/50-cloud-init.yaml`: it keeps the Wi-Fi key on the node).
3. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`, then `systemctl disable --now k3s` on the node, then `kubectl delete node <node>`. k3s removes the etcd member on node delete (`Removing etcd member from cluster due to node delete` in the other servers' k3s log).
4. Power off, remove the SD card (keep it: the rollback), power on. First boot grows the root partition and runs cloud-init.
5. From pimaster: `ssh-keygen -R <ip>`, also inside the runner (`docker exec ansible-runner ssh-keygen -f /home/runner/.ssh/known_hosts -R <ip>`), then with `--limit <node>`: `update.yml`, `setup_picluster.yml --tags node`, `k3s_install.yml`. The node joins as an etcd learner and is promoted.
6. system-upgrade-controller runs the `k3s-server` plan on the new node and cordons it until done. The upgrade script can fail with `Found multiple K3s pids` (it counts its own `k3s kubectl`); the Job retries and the node is uncordoned once the plan completes (`plan.upgrade.cattle.io/k3s-server` label).

Rollback before step 3: wipe the SSD. After step 3: unplug the SSD, insert the SD card (SD boots first), delete `/var/lib/rancher/k3s/server/db` on the node and rerun `k3s_install.yml --limit <node>`.

## Corrupted etcd member

A hard power cut can corrupt a member's database (`panic: freepages: failed to get all reachable pages` in the k3s log, k3s restarting in a loop). With the other two members healthy: snapshot, `systemctl stop k3s` on the node, `kubectl delete node <node>` (removes the member), delete `/var/lib/rancher/k3s/server/db` on the node, `systemctl start k3s`. It rejoins as a learner and is promoted.

## Longhorn node selector

Changing `systemManagedComponentsNodeSelector` (Longhorn) is applied only with all Longhorn volumes detached: scale down Prometheus, Alertmanager and Grafana (suspend their Flux Kustomizations and HelmReleases first), let Flux upgrade Longhorn, then scale back up. Existing volumes keep their replica count: set `numberOfReplicas` on each `volumes.longhorn.io`.
