# Control host in Oracle Cloud

Goal: the control host (pimaster) moves from the UTM VM on the Mac to a second Oracle Cloud VM that works from any network, and the cluster is rebuilt from empty disks with Ansible logging in as a non-root `ansible` user with sudo. Same nodes, same services, same Git and Flux flow.

Status (2026-11-10): decisions D1–D7 taken as recommended. Next: PR 2, then phase 1. Phase 4 (the Ansible change) starts after [Cluster 3.0](cluster-3.0.md) phase 4 is merged: that phase moves `ansible_user` into `group_vars/all/`.

## Why

- pimaster runs on the Mac. With the lid closed there is no control host, and away from home it needs a second network device and its own tunnel client (branch `feature/remote-access`, live since 2026-11-09, not merged).
- Ansible logs in to every node as `root` with one key, and every node accepts root SSH (`PermitRootLogin prohibit-password`). Cluster 3.0 left this out because cloud-init, the roles and the runner assume root. A rebuild removes that obstacle.
- The cluster holds no data worth keeping (user, 2026-11-10). A rebuild costs only time, and it proves cloud-init and `make init` with the new user. The last full rebuild was on 2026-11-03.

## Target

```
  any network                    Oracle Cloud (Frankfurt)                       home
  laptop, phone ── WireGuard ──► pimaster 10.99.0.3 ◄──────── WireGuard ───────┐
                                     │ WireGuard over the VCN                    gateway 10.0.0.1 ── nodes 10.0.0.0/24
                                 offsite 10.99.0.2  ◄──────── WireGuard ───────┘
                                                        (the gateway dials out to both VMs)
```

| | Now | After |
|---|---|---|
| Control host | UTM VM on the Mac, 10.0.0.20 on the cluster LAN | Oracle A1 VM `pimaster`, 10.99.0.3 in the tunnel |
| Reaching the control host | VS Code Remote-SSH from the Mac on the home network | WireGuard from the laptop or phone on any network, then SSH or VS Code Remote-SSH. No public SSH (D4) |
| SSH user on the nodes | `root` | `ansible` with passwordless sudo. sshd refuses root |
| Control key | `~/.ssh/id_rsa` of the old VM | a new key created on the new VM, plus a break-glass key on the Mac (D6) |
| Remote access hub | the offsite VM | pimaster. The offsite VM goes back to backups and monitoring only (D5) |
| Claude Code and VS Code | run as `root` (root-owned files, `chown` afterwards) | run as `pimaster` |
| Gateway SSH | `root`, key only | unchanged: OpenWrt has no sudo |
| Offsite VM SSH | `ubuntu` with sudo | unchanged |

Tunnel addresses (10.99.0.0/24): .1 gateway, .2 offsite, .3 pimaster, .16/28 remote clients (laptop .18, phone .19), now routed through pimaster instead of offsite. The old pimaster's client address (.17) is retired.

## Decisions

Each decision is needed before the phase in brackets. The recommendation comes first. Taken by the user on 2026-11-10: all as recommended.

- **D1 Oracle account type (phase 1).** Recommended: upgrade the tenancy to Pay As You Go. Oracle stops idle Always Free instances on free accounts. Its published rule calls a VM idle when, over 7 days, its 95th-percentile CPU, network and memory (A1 shapes) all stay below 20%, and a control host is idle most days. Pay As You Go accounts are exempt, Always Free resources stay free, and in practice A1 capacity is easier to get. Add a budget alert at 1 USD. Alternative: stay on the free account and restart the VM from the console after Oracle stops it.
- **D2 Block storage (phase 1).** The offsite VM uses all 200 GB of Always Free block storage (50 GB boot + 150 GB backup volume), and a second VM needs at least a 47 GB boot volume. Recommended: replace the 150 GB backup volume with a 100 GB one, for a total of 50 + 50 + 100 = 200 GB at no cost. The restic repository holds 3.5 GiB, and it starts fresh after the rebuild (the cluster has no data). Alternative: keep 150 GB and pay for the extra 50 GB, about 2 USD a month at list price. This needs D1.
- **D3 VM size (phase 1).** Recommended: 3 OCPUs and 18 GB, the rest of the free A1 quota (offsite uses 1 OCPU and 6 GB). The runner image build, `make verify` and the VS Code server all run there, and A1 cores are slower than the Mac's. Alternative: 2 OCPUs and 12 GB. Resizing later only needs a reboot.
- **D4 Access to pimaster (phase 1).** Recommended: WireGuard only. The Oracle security list opens UDP 51820, as it does for the offsite VM, and WireGuard ignores packets that are not authenticated. SSH listens on `wg0` only. Break-glass: Oracle's serial console. Alternative: public SSH, key only, with fail2ban. That needs no client, but the port faces internet scans.
- **D5 Remote access hub (phase 2).** Recommended: the laptop and phone connect to pimaster, and the offsite VM stops forwarding into the home network. The VM that holds the backups then has the narrowest access again. The live setup from 2026-11-09 is undone on the offsite VM in phase 2, `feature/remote-access` is closed without merging, and its gateway rules move into this work. Alternative: keep both hubs, so the backup VM keeps two jobs and the laptop needs two tunnel profiles.
- **D6 Break-glass access (phase 3).** Recommended: the `ansible` user trusts two keys: pimaster's, and a passphrase-protected key on the Mac that is never used day to day. In addition, an encrypted copy of `~/.secrets`, `~/.certbot` and the Terraform state lives on the Mac. With both, any Linux machine with Docker on the home network can become the control host if Oracle, the VM or the account is gone. Without the break-glass key, losing the VM means re-flashing every Pi to get back in.
- **D7 Names (phase 1).** Recommended: the user on the nodes is called `ansible`. The new VM keeps the hostname and user `pimaster`, so the docs, the `control` inventory group and the `/home/pimaster/...` paths stay valid.

## Rules

- One pull request per code phase, based on `master`, merged in order. The user pushes and merges.
- Live changes are made by the user: the Oracle console, `tofu apply`, the gateway script, `make clean`, re-flashing the disks and `make init`. Destructive steps need an explicit go at the step itself, even though the cluster has no data.
- The old pimaster stays usable until phase 6. Nothing on it is deleted before the new pimaster has done the rebuild.
- Each phase ends with its validation before the next one starts.
- The Cluster 2.0 etcd rules (never a full `k3s_install.yml` on node6, snapshot first) apply to a running cluster. The rebuild starts from empty disks, which is the case `make init` is written for.
- The Terraform state moves to the new VM. The old VM never plans or applies again after the copy, so two states never diverge.

## Pull requests

| PR | Branch | Content | For phase |
|---|---|---|---|
| 1 | `feature/control-host-oci` | this plan | n/a |
| 2 | `feature/control-host-oci-vm` | `terraform/oci`: the pimaster VM and its first-boot config, backup volume 100 GB (D2), `ssh_authorized_keys` ignored after first boot (like `user_data`), the pimaster peer in the offsite first-boot config; `offsite_backup.yml` volume size check 100 GB; `wireguard-oci.sh`: pimaster peer and rules; docs for the control host and offsite | 1–3 |
| 3 | `feature/ansible-user` | Ansible as `ansible`: cloud-init, `metal/rpi/Makefile`, plays, a CI check, pipelining, docs | 4 |
| 4 | `feature/control-host-oci-done` | control host backup target, docs, cleanup | 6 |

## Phases

| Phase | Change | Live change | Applied by |
|---|---|---|---|
| 1 | Oracle: account, storage, the VM | new VM `pimaster`; backup volume replaced (fresh repository) | user: console settings, `tofu apply` from the old pimaster |
| 2 | The tunnel moves | gateway peer and rules for pimaster; offsite VM stops forwarding; laptop connects to pimaster | user: gateway script, offsite commands |
| 3 | Bootstrap the new pimaster | repository, tools, keys, secrets moved, runner | user, with Claude over SSH |
| 4 | Ansible as `ansible` (code) | the user created on the current nodes for a pre-flight; nothing else | merge; user approves the pre-flight commands |
| 5 | Rebuild | everything | user: `make clean`, re-flash, `make init` from the new pimaster |
| 6 | Cutover and cleanup | old VM shut down, old keys removed | user |

### Phase 1: Oracle

Code (PR 2, `terraform/oci`):

- `oci_core_instance.pimaster`: `VM.Standard.A1.Flex` with the D3 size, the same Ubuntu 24.04 image data source, 50 GB boot volume, public subnet, public IP (the WireGuard endpoint), `hostname_label = "pimaster"`. A new variable `pimaster_ssh_authorized_keys` takes the old pimaster's key (for the bootstrap copy) and the Mac's key. The VM is created only with `pimaster_enabled = true` (off by default), so for anyone else the module still builds only the offsite VM.
- First-boot config `pimaster-cloud-init.yaml.tftpl`:
  - user `pimaster` in the `docker` group;
  - packages `wireguard-tools git make jq curl rsync age iptables-persistent`. Docker (`docker.io docker-compose-v2`) is installed after the firewall rules are saved, so Docker's own rules never land in the saved set;
  - `wg0` at 10.99.0.3/24, listening on 51820, with these peers:
    - the gateway: AllowedIPs 10.99.0.1/32 and 10.0.0.0/24, no endpoint, the gateway dials;
    - offsite: endpoint at its VCN private IP, AllowedIPs 10.99.0.2/32, keepalive 25;
    - the clients from a `wg_clients` variable: laptop 10.99.0.18, phone 10.99.0.19.
  - Split DNS in `PostUp`: `resolvectl dns wg0 10.0.0.1; resolvectl domain wg0 ~<dns_domain>`. Only the homelab domain goes to the gateway; everything else uses Oracle's resolver.
  - IP forwarding for the clients, to 10.0.0.0/24 and 10.99.0.2 only.
  - iptables as on the offsite VM: UDP 51820 in, SSH only on `wg0`, the public SSH rule removed.
- The offsite first-boot config gets a pimaster peer (AllowedIPs 10.99.0.3/32 and 10.99.0.16/28, no endpoint), so a recreated offsite VM has it. The running VM gets it by hand in phase 2. The offsite template reads only pimaster's public key and pimaster's template reads only offsite's address and public key, so the two templates do not depend on each other in a cycle.
- `ssh_authorized_keys` joins `ignore_changes` on the offsite instance. It is first-boot only, like `user_data`. Without that, the new key on the new pimaster would make `tofu plan` change the offsite instance. pimaster's keys are in its first-boot config, so it has no metadata key and no default `ubuntu` user.
- D2: `oci_core_volume.backups` goes to 100 GB, and the size check in `offsite_backup.yml` follows. That playbook already formats an empty volume, mounts it and runs `restic init`.
- Outputs: `pimaster_public_ip`, `pimaster_tunnel_ip`, `offsite_private_ip`. New keys in `terraform.tfvars.example`.

Steps:

1. Oracle console: D1 (upgrade, budget alert), MFA on every console login of the tenancy. The tenancy will hold the control host.
2. On the old pimaster, the WireGuard key of the new VM:

   ```shell
   (umask 077; wg genkey | tee ~/.secrets/wireguard/pimaster-oci.key | wg pubkey > ~/.secrets/wireguard/pimaster-oci.pub)
   ```

   Then set the new values in `terraform/oci/terraform.tfvars`, as in `terraform.tfvars.example`: `pimaster_enabled = true`, the two SSH public keys, the key paths, `dns_domain`, and the laptop's `~/.secrets/wireguard/laptop.pub` in `wg_clients`.
3. D2 only: stop the offsite copy, which would fail every night until phase 5, and unmount the volume that is about to be replaced:

   ```shell
   ssh root@10.0.0.11 systemctl disable --now restic-offsite.timer
   ssh ubuntu@10.99.0.2 sudo umount /backup
   ```

4. Plan, read, apply, in two steps. OCI cannot shrink a volume in place, so it is replaced explicitly, and before the new boot volume exists, so the total stays within 200 GB:

   ```shell
   ./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/oci && tofu plan -replace=oci_core_volume.backups -target=oci_core_volume_attachment.backups -out tfplan'
   ./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/oci && tofu apply tfplan'
   ./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/oci && tofu plan -out tfplan'
   ./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/oci && tofu apply tfplan'
   ```

   Expected plans: first, the backup volume and its attachment are replaced. Second, `oci_core_instance.pimaster` is added. Nothing else changes, and the offsite instance stays. If A1 reports "Out of host capacity", retry later or set `pimaster_availability_domain_index`.

Validation: the instance is Running in the console. The serial console shows that cloud-init finished. Rollback: `tofu destroy -target=oci_core_instance.pimaster`. A replaced backup volume cannot be brought back (accepted: no data).

### Phase 2: the tunnel moves

Code (PR 2, `metal/openwrt/script/wireguard-oci.sh`):

- A second peer on `wg_oci`, `pimaster_vm`, with endpoint `PIMASTER_ENDPOINT`, key `PIMASTER_PUBKEY`, keepalive 25, AllowedIPs 10.99.0.3/32 and 10.99.0.16/28. The offsite peer keeps 10.99.0.2/32 only. On a re-run, unset variables are read back from uci, so neither peer is lost (taken from `feature/remote-access`).
- Rules `ctl_*` for sources 10.99.0.3 and 10.99.0.16/28, the same access as the home network:
  - on the gateway itself: SSH 22, LuCI 443, DNS 53;
  - in the LAN: SSH 22 and web 80/443 to any host;
  - k3s API 6443 on 10.0.0.10;
  - Vault 8200 and RustFS 9091/9092 on 10.0.0.11.

  These replace the `remote_*` rules of that branch.

Steps:

1. Back up the gateway:

   ```shell
   ssh root@10.0.0.1 sysupgrade -b /tmp/gw.tar.gz && scp -O root@10.0.0.1:/tmp/gw.tar.gz ~/backups/gateway-$(date +%Y%m%d).tar.gz
   ```

2. Add the pimaster peer and the rules:

   ```shell
   ssh root@10.0.0.1 "PIMASTER_ENDPOINT=<pimaster_public_ip> PIMASTER_PUBKEY=$(cat ~/.secrets/wireguard/pimaster-oci.pub) sh -s" < metal/openwrt/script/wireguard-oci.sh
   ```

3. On the offsite VM (D5), remove the remote-access setup from 2026-11-09 and add the pimaster peer:

   ```shell
   ssh ubuntu@10.99.0.2 'sudo sed -i "/# BEGIN remote access clients (ansible)/,/# END remote access clients (ansible)/d" /etc/wireguard/wg0.conf'
   ssh ubuntu@10.99.0.2 "printf '\n[Peer]\n# pimaster (Oracle VM, over the VCN)\nPublicKey = %s\nAllowedIPs = 10.99.0.3/32, 10.99.0.16/28\n' '$(cat ~/.secrets/wireguard/pimaster-oci.pub)' | sudo tee -a /etc/wireguard/wg0.conf >/dev/null"
   ssh ubuntu@10.99.0.2 "sudo bash -c 'wg syncconf wg0 <(wg-quick strip wg0)'"
   ssh ubuntu@10.99.0.2 'sudo sh -c "iptables-save | grep -v -- \"Remote access\" | iptables-restore && netfilter-persistent save"'
   ssh ubuntu@10.99.0.2 'sudo rm /etc/sysctl.d/90-remote-access.conf && sudo sysctl -w net.ipv4.ip_forward=0'
   ```

4. Laptop: the WireGuard profile keeps its key (`laptop.key`, address 10.99.0.18), and its peer becomes pimaster: pimaster's public key, endpoint `<pimaster_public_ip>:51820`, AllowedIPs 10.99.0.0/24 and 10.0.0.0/24, DNS 10.0.0.1 for the homelab domain, MTU 1280. The phone works the same way, at 10.99.0.19. At home the profile can stay on. Traffic then goes through Frankfurt, about 40 ms per round trip.

Validation:

- On the gateway, `wg show wg_oci` shows a handshake under 2 minutes old for both peers.
- From the old pimaster, `ssh pimaster@10.99.0.3 cloud-init status` returns `done`.
- On the new VM:
  - `ping -c3 10.0.0.1`;
  - `nc -zv 10.0.0.16 22`;
  - `nc -zv 10.0.0.10 6443`;
  - `nc -zv 10.99.0.2 22`;
  - `resolvectl query vault.<dns_domain>` returns 10.0.0.11.
- From the laptop on a phone hotspot: `ssh pimaster@10.99.0.3`, then Grafana in the browser.
- Gatus on the offsite VM stays all green: its own tunnel did not change.

Rollback: restore the gateway backup (`sysupgrade -r`) and re-run `make configure-remote-access` from the branch.

### Phase 3: bootstrap the new pimaster

On the new VM as `pimaster`, unless a step says otherwise. Log in from the old pimaster first (`ssh pimaster@10.99.0.3`), and from the Mac once its WireGuard profile works (VS Code Remote-SSH, host 10.99.0.3, user `pimaster`).

1. The control key, created on the VM and never copied anywhere. It stays RSA at `~/.ssh/id_rsa`, so the runner's mounts and `ansible_ssh_private_key_file` stay as they are:

   ```shell
   ssh-keygen -t rsa -b 4096 -N '' -C pimaster@oci -f ~/.ssh/id_rsa
   ```

2. A console password for Oracle's serial console, the break-glass access of D4: `sudo passwd pimaster`, kept in the password manager. The user has a locked password otherwise, and SSH stays key-only. On the Mac, the break-glass key (D6), with a passphrase. Its public key goes into `ansible.pub` in phase 5:

   ```shell
   ssh-keygen -t ed25519 -C picluster-breakglass -f ~/.ssh/picluster-breakglass
   ```

3. Repository and tools: `git clone https://github.com/yekvitka/pi-cluster ~/pi-cluster`, install mise, then run `mise install` in the repository. Pushing works from VS Code Remote-SSH, which forwards the Mac's Git credentials.
4. Move the files that are not in Git. On the old pimaster, as `pimaster`:

   ```shell
   rsync -a ~/.secrets ~/.certbot pimaster@10.99.0.3:
   rsync -a ~/.kube/config pimaster@10.99.0.3:.kube/
   cd ~/pi-cluster && rsync -aR terraform/*/terraform.tfstate terraform/*/terraform.tfvars CLAUDE.md pimaster@10.99.0.3:pi-cluster/
   for f in terraform/*/terraform.tfstate; do mv "$f" "$f.moved-to-oci"; done
   ```

   - `~/.certbot` keeps the issued certificates, so the rebuild places no new Let's Encrypt orders and stays clear of the rate limits.
   - Claude Code's memory moves too: on the old VM it is in `/root/.claude/projects/-home-pimaster-pi-cluster/`, on the new one in `~/.claude/projects/-home-pimaster-pi-cluster/` of `pimaster`.
   - Not moved: `~/.ssh` (new key, empty `known_hosts`). On the new VM, delete `~/.secrets/wireguard/pimaster.{key,pub}`, the old VM's retired client key.

5. Trust the new key on the current nodes (as root, until the re-flash) and on the offsite VM (permanently). From the old pimaster:

   ```shell
   scp pimaster@10.99.0.3:.ssh/id_rsa.pub /tmp/pimaster-oci.pub
   for ip in 10.0.0.11 10.0.0.12 10.0.0.13 10.0.0.14 10.0.0.15 10.0.0.16; do
     ssh root@$ip 'cat >> .ssh/authorized_keys' < /tmp/pimaster-oci.pub
   done
   ssh ubuntu@10.99.0.2 'cat >> .ssh/authorized_keys' < /tmp/pimaster-oci.pub
   ```

6. Runner and checks on the new VM:

   ```shell
   make ansible-runner-setup
   make verify
   ./ansible-runner/ansible-runner.sh ansible all -m ping
   kubectl get nodes
   ```

   Then `tofu init && tofu plan` in each module shows no changes. For `terraform/vault`, load the Vault environment and set `TF_VAR_enable_kubernetes_auth=true`, as `configure_vault.yml` does.

Validation: every command in step 6 passes, and the three plans show no changes. Record the image build time and the `make verify` time; on the Mac `make verify` took 85 s. Rollback: delete the VM; remove the extra key line on the nodes and the offsite VM; rename the state files back on the old VM.

### Phase 4: Ansible connects as `ansible`

Code (PR 3, after Cluster 3.0 phase 4):

- **cloud-init** (`user-data`, `user-data-node1`):
  - `disable_root: true`;
  - user `ansible` with `lock_passwd: true`, `sudo: "ALL=(ALL) NOPASSWD:ALL"`, `shell: /bin/bash` and the keys from `ansible.pub`;
  - root keeps a locked password and gets no keys.
- **`metal/rpi/Makefile`:** `PUB_KEY_FILE=cloud-init/ansible.pub`. Every line of the file becomes one entry in the `ssh_authorized_keys` list: today's `sed` inserts a single line, and the file now holds two keys (pimaster and break-glass). `.gitignore` lists `ansible.pub` instead of `root.pub`.
- **Variables:**
  - `ansible_user: ansible`;
  - the `security_ssh_permit_root_login` override goes, so the `ricsanfre.security` default `"no"` applies and sshd refuses root;
  - sudo comes from cloud-init (`/etc/sudoers.d/90-cloud-init-users`).
- **Plays that target nodes without `become`** get `become: true`:
  - `cert_renewal.yml`;
  - the two `s3` plays of `offsite_backup.yml` (the `oci` play already has `ansible_become`);
  - the two `k3s_master` plays of `k3s_install.yml` that lack it.

  All other node plays already set it.
- **Tasks delegated to the control host** that would now inherit `become` get `become: false`:
  - "Fetch restic S3 credentials on-demand from Vault" (`backup_configuration.yml`);
  - "Request a periodic raft-snapshot token" (`offsite_backup.yml`);
  - "Write Kubernetes config file with the correct cluster address" (`k3s_install.yml`);
  - the six "Read ... values.yaml" tasks in `roles/k3s/master/tasks/installation.yml`.

  Inside the runner they would still work, because `runner` has sudo there, but files they write would belong to root: the kubeconfig would become unreadable.
- **Paths built from `~{{ ansible_user }}`** now point at `/home/ansible`:
  - the Vault environment lines in `.bashrc` on node1 (`deploy_vault.yml`), whose root token lookup already uses `sudo jq`;
  - the admin kubeconfig copy on the servers (k3s role, mode 0600).
- **`make configure-cert-renewal`:** the two `ssh root@node1` commands become `ssh ansible@node1 sudo ...`. The gateway stays `root@`.
- **`ansible.cfg`:** `pipelining = True`. With `become`, each task then needs fewer SSH round trips, which matters at about 40 ms per round trip through Frankfurt. Ubuntu's sudoers has no `requiretty`.
- **CI check** (`scripts/check-ansible.sh`): every play that targets hosts other than localhost sets `become`, and every task delegated to localhost inside such a play sets `become: false`. A missed `become` otherwise fails only at runtime, in the middle of a rebuild.
- **Docs:**
  - `docs/platform.md`, `docs/quick-start.md` (`ansible.pub`), `docs/backup-and-recovery.md` ("as root on node1" becomes "with sudo");
  - CLAUDE.md, which is local only;
  - the Cluster 3.0 plan ("Not in 3.0") points here.

Pre-flight on the current nodes, from the new pimaster with `master` (still root). The cluster is disposable, but this catches gaps before any disk is re-flashed:

```shell
R=./ansible-runner/ansible-runner.sh
$R ansible picluster -m ansible.builtin.user -a 'name=ansible shell=/bin/bash password_lock=true'
$R ansible picluster -m ansible.posix.authorized_key -a "user=ansible key='{{ lookup(\"ansible.builtin.file\", \"~/.ssh/id_rsa.pub\") }}'"
$R ansible picluster -m ansible.builtin.copy -a "dest=/etc/sudoers.d/90-ansible content='ansible ALL=(ALL) NOPASSWD:ALL\n' mode=0440 validate='visudo -cf %s'"
```

Then, on the PR 3 branch:

- `ansible all -m ping`;
- `ansible picluster -b -m command -a id` shows uid 0;
- check-mode runs of `setup_picluster.yml`, `backup_configuration.yml`, `deploy_monitoring_agent.yml`, `cert_renewal.yml` and `configure_dns_authoritative.yml`.

Each run reports the same changed tasks as a check-mode run as root on `master`. The only expected difference is sshd's `PermitRootLogin`.

Validation: `make verify` with the new CI check; the pre-flight above. Rollback: revert PR 3. Root login works until phase 5, because the pre-flight removes nothing.

### Phase 5: rebuild

From the new pimaster, with PR 3 merged, in this order:

1. `make clean` runs as `ansible` and proves the reset playbooks with the new user. It also wipes Vault and RustFS on node1's `DATA` SSD, which a re-flash would not do: cloud-init never reformats that disk (`overwrite: false`), and the disk never leaves node1.
2. Write `metal/rpi/cloud-init/ansible.pub`: pimaster's public key and the break-glass public key, one per line.
3. Re-flash from the old pimaster: it has USB passthrough on the Mac, and the cloud VM cannot write disks. The flow is the one in the quick start (`make burn-image`, `make prepare-nodeX`). Do node4 first (worker, SD card), boot it, and check from the new pimaster:
   - `ssh ansible@10.0.0.14 sudo -n true` works;
   - `ssh root@10.0.0.14` is refused;
   - the rendered `user-data` on the boot partition lists both keys.

   Then node1 (SD card only), node2 (SD), node3, node5 and node6 (SSD).
4. On the new pimaster, forget the old host keys: `ssh-keygen -R` for each node's IP and name.
5. `make init`, timed.
6. The steps that are not part of `init`: `make configure-cert-renewal`, `make configure-offsite-backup` (fresh repository on the 100 GB volume; it re-enables the node1 timer) and `make configure-offsite-monitoring`.

Validation: the same checks as the 2026-11-03 rebuild.

- All Flux Kustomizations and HelmReleases are Ready, and all ExternalSecrets are synced.
- All Prometheus targets are up, and the Longhorn volumes are healthy.
- An etcd snapshot reaches S3, and a Velero backup completes.
- Gatus is all green.
- The served certificates are valid, with no new ACME order.
- A manual offsite run completes and `restic snapshots` lists it.
- `ansible all -m ping` works as `ansible`, and no node accepts root SSH.

The measured times go into [backup and recovery](../backup-and-recovery.md). This rebuild is the full rebuild drill of Cluster 3.0 phase 8.

Rollback: none is needed for data. If the new pimaster fails partway, the break-glass key and the copy of the secrets let any Linux machine with the repository continue.

### Phase 6: cutover and cleanup

- Shut the old pimaster down and keep the UTM VM for two weeks; then the user deletes it. Remove its key from `ubuntu`'s `authorized_keys` on the offsite VM.
- Close `feature/remote-access` without merging and delete its worktree and branch. Its gateway rules went into phase 2, and the offsite part was undone there.
- **Control host backup (D6),** PR 4: `make control-host-backup` writes `~/backups/control-host-<date>.tar.age`. It holds `~/.secrets`, `~/.certbot`, `terraform/*/terraform.tfstate` and `.tfvars`, and CLAUDE.md, encrypted with an age passphrase. The Mac pulls it with `scp` after every change to those files. Restore test: decrypt it into a scratch directory and compare.
- **Docs,** PR 4:
  - `docs/control-host.md`: the Oracle VM, the bootstrap, access, the backup, and recovery (`tofu apply`, then restore the archive);
  - `docs/hardware-and-network.md`: the hosts table, 10.0.0.20 out of the IP plan, the tunnel addresses;
  - `docs/quick-start.md`: any Linux host with Docker works, and the Oracle control host is optional, like the offsite VM;
  - `docs/offsite.md`: no more hub;
  - `metal/openwrt/README.md`;
  - the README numbers;
  - CLAUDE.md (local).

## Security

- **The new trust boundary.** pimaster holds the keys to everything: sudo on every node, the Vault root token (`~/.secrets/vault.env`), the restic password, the OCI API key and the WireGuard keys. In Oracle it sits in the same tenancy as the offsite backups, so a compromised Oracle account reaches the cluster and both copies of the data. Countermeasures:
  - MFA on the Oracle account (phase 1);
  - no public SSH (D4);
  - Oracle's default encryption of the boot volume;
  - the restic password also in a password manager;
  - the break-glass key and the encrypted copy of the secrets outside Oracle (D6).
- **What improves.** No node accepts root SSH. Every root action goes through sudo and is logged with the `ansible` user. Access is revoked in one place: one user's `authorized_keys`, via cloud-init on the next build. Passwordless sudo still makes a stolen `ansible` key as powerful as root. A sudo password would need a become password in every run, which is friction without a matching gain for automation.
- **Unchanged.** The WireGuard private keys of both VMs pass through instance metadata and the Terraform state (the offsite pattern; Cluster 3.0 phase 8 encrypts the state). Membership in the `docker` group on pimaster equals root on pimaster, as today.

## Risks

| Risk | Effect | Mitigation |
|---|---|---|
| A1 out of capacity in Frankfurt | VM not created | retry, another availability domain, D1 |
| Oracle stops an idle VM | control host down | D1 |
| A missed `become` | a task fails partway through the rebuild | the play and task audit in phase 4, the CI check, the check-mode pre-flight on the live nodes |
| Multi-key rendering in cloud-init | locked out of a freshly flashed node | node4 alone first, rendered `user-data` checked; break-glass key |
| About 40 ms per round trip to the nodes | slower Ansible runs | pipelining; `ControlPersist` is already on |
| Home internet down | no control from anywhere (Flux cannot pull either) | at home: the Mac on the home network, break-glass key, secrets copy |
| Oracle account lost or locked | no control host, no offsite copy | D6; the offsite copy is optional by design |

## Not in this plan

- A non-root user on the gateway: OpenWrt has no sudo, so root with a key stays.
- Another user on the offsite VM: `ubuntu` with sudo stays.
- Re-flashing the gateway: only its WireGuard script runs again.
- Managing pimaster with Ansible: the runner is a container on pimaster, so a local connection would configure the container, not the host. First-boot config and documented steps instead, as for the offsite VM.
- Moving node1's `DATA` SSD: never.

## Done when

- pimaster runs in Oracle and is reached from the laptop on a foreign network through WireGuard. The UTM VM is deleted.
- `make init` from the new pimaster built the cluster on freshly flashed disks, and every check of the 2026-11-03 rebuild passes.
- No node accepts root SSH, Ansible connects as `ansible`, and the CI check finds no node play without `become`.
- The encrypted control host backup is on the Mac, and its restore test passed.
- The docs describe the new control host, and the measured rebuild times are in backup and recovery.
