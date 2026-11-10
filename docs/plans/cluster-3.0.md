# Cluster 3.0

Goal: the same hardware and services as [Cluster 2.0](cluster-2.0.md), run from a repository a platform team would sign off on: every pull request checked by CI, no known security defects, the owner's values in one place, decisions and incidents written down, alerts that reach a person, restores that are proven. No new hardware and no new services, except alert delivery.

Status (2026-11-10): phases 1–4 merged. The full rebuild drill of phase 8 ran on 2026-11-10 with the [control host move](control-host-oci.md) ([times](../backup-and-recovery.md#full-rebuild)). Next: phase 5.

## Why

A review of the repository (2026-11-08) found:

- CI runs only yamllint: Ansible, the Flux manifests, Terraform and the shell scripts reach `master` unchecked.
- TLS verification is off where it should be on. Every Ansible call to Vault sets `validate_certs` to `not enable_letsencrypt`, so with the Let's Encrypt certificates in use nothing is verified, the k3s join token included. Host keys are not checked either, on root SSH sessions.
- The k3s admin kubeconfig is readable by every local user on the servers (`write-kubeconfig-mode: 644`).
- Alerts go nowhere: Alertmanager has only the `"null"` receiver and Gatus has no alerting.
- The owner's values sit in about ten files, some twice (MAC addresses in the inventory and in the gateway script).
- Dead code: two apps marked "not used", a node that is not planned, a group that does not exist, broken `dev/` targets, four Helm versions.
- Code comments carry the history (25 dates, 12 "phase" references) instead of the reasons; the decisions and incidents behind them exist only in commit messages and the 2.0 plan.
- The conventions (style, verification, branch workflow) are in a local, untracked file: nobody else can see them.

## Rules

- One pull request per phase, merged in order. Branches stack (each starts from the previous one), so a PR shows only its own commits once the one before it is merged. The user pushes and merges.
- A change meant to keep behavior is proven to: every Flux path renders the same before and after (`kubectl kustomize`, cluster-settings substituted, compared as data), and every Ansible variable resolves to the same value on every host.
- Each phase lists what changes on the running system and who applies it. Vault writes and `tofu apply` are run by the user.
- Never a full `k3s_install.yml` on node6: it would write `cluster-init` into its config, and a k3s restart there costs a Cilium recompile of every endpoint. The etcd rules of Cluster 2.0 stay.
- Verified with `make lint`, `ansible-lint`, `ansible-playbook --syntax-check`, `kubectl kustomize` of every Flux path, `tofu validate` and `tofu fmt -check`; from phase 3 on, `make verify` and CI.

## Phases

| Phase | Change | Live change | Applied by |
|---|---|---|---|
| 1 | Security defects | Ansible verifies TLS and host keys; kubeconfig 0600 on the servers | user: one ad-hoc command on node2, node3, node6 |
| 2 | Cleanup | none: nothing removed is deployed | merge |
| 3 | CI and repository gates | none | merge; user: branch protection on GitHub |
| 4 | Structure: variables, Vault session, one site file | none (proven) | merge |
| 5 | Alerts reach a person (Telegram) | Alertmanager and Gatus configuration | user: bot token and chat ID into Vault, `make configure-offsite-monitoring` |
| 6 | Decisions, incidents, runbooks, contributor docs | none | merge |
| 7 | Pod Security Admission | namespace labels | merge |
| 8 | Recovery proven | restore drills, encrypted Terraform state | user: drills, one `tofu apply` per module |

### Phase 1: security defects

- **TLS to Vault and RustFS.** The inverted `validate_certs: "{{ not (enable_letsencrypt | default(false)) }}"` goes from the 12 Vault calls: the modules verify by default, and `vault_cacert` is still passed for a private CA. `rustfs_validate_certificate: "{{ enable_letsencrypt }}"`, the way `tls_skip_verify` already works for Vault. Checked before the change: the runner verifies `vault.<domain>:8200` and `object-store.<domain>:9091` with the system CA bundle. `TF_VAR_minio_ssl_verify` goes too: `terraform/minio` has no such variable.
- **SSH host keys.** `host_key_checking = true` with `StrictHostKeyChecking=accept-new`: a new host is trusted on first use, a changed key stops the run. The runner mounts the control host's `~/.ssh/known_hosts`, so what it trusts survives a rebuild. After a node is reprovisioned, remove its old key (`ssh-keygen -R <ip>`, `ssh-keygen -R <name>`).
- **kubeconfig.** `write-kubeconfig-mode: "0600"`. Live, without a k3s restart, once by the user: set the same line in `/etc/rancher/k3s/config.yaml` and the mode of `/etc/rancher/k3s/k3s.yaml` on node2, node3 and node6 (ad-hoc commands in the PR). k3s keeps the mode at its next start.
- **Runner image.** Galaxy installs with TLS verification (no `--ignore-certs` default). helm-diff pinned to the version every build has picked so far (3.15.15), managed by Renovate.
- **k3s role defaults.** No default token (`s1cret0`) and no default version (`v1.24.7+k3s1`): both always come from Vault and the cluster variables, so a missing value fails instead of silently using the default.
- **Terraform lock files in Git** (`.terraform.lock.hcl`, hashes for linux_arm64 and linux_amd64): pimaster and CI use the same provider builds.

Validation: syntax-check and ansible-lint; host key checks pass on every host (`ansible all -m ping`); a check-mode run connects everywhere; a Vault read with verification on. Rollback: revert the PR (the 0600 mode can stay).

### Phase 2: cleanup

- **Delete what is not deployed or not planned:** `platform/descheduler` and `clusters/prod/infra/descheduler-app.yaml`; `platform/flux-operator/tofu-controller`; `host_vars/node7.yml` and `prepare-node7`; `group_vars/external.yml` (there is no `external` group, and it set `ubuntu` where every node uses `root`); `install_utilities_localhost.yml` and `make install-local-utils` (amd64 binaries and kubectl 1.35 on an arm64 host, replaced by `.mise.toml`; it also ran `ansible-playbook` outside the runner).
- **`dev/`:** delete the broken targets (`helm-setup`, `cluster-setup`, `cluster-bootstrap`: `helmfile.yaml` and `kubernetes/clusters/bootstrap` do not exist), set the k3d image to the cluster's k3s version under Renovate, and document the flow that works (k3d plus Helm with the repo values). The dev Flux instance syncs `kubernetes/cluster/dev` (should be `clusters`), and dev's config still applies an old `flux-system` GitRepository on a `dev` branch that does not exist: both fixed. Found on the way: `create_cluster.sh` needs `tmpl`, which is not installed (now `envsubst`), and k3d switched the default kubeconfig's context, the one Ansible uses, to the dev cluster (now `dev/kubeconfig`). Tested 2026-11-09: Cilium with the repo values runs and the nodes become Ready; pods do not reach the Kubernetes API Service in k3d, so CoreDNS and Flux do not run there (documented in `dev/README.md`).
- **One Helm version** (`helm_version` in the cluster variables): the v3.9.4 in `group_vars/k3s_master.yml` and the role fallback v3.13.2 go.
- **Versions repeated in Ansible follow the cluster:** grafana-operator CRDs 5.22.2 → 5.25.0, with a Renovate comment (the existing custom managers do not match `helm_template`).
- **No MinIO aliases:** `minio_*` → `rustfs_*` in `configure_minio.yml` and `reset_external_services.yml`; their messages show the RustFS ports (9091, 9092), not 9000 and 9001.
- **Renovate:** custom managers on `managerFilePatterns` (`fileMatch` is deprecated) and group rules on `matchPackageNames` (`matchPackagePatterns` is deprecated); the group for a runner controller that is not deployed goes; `:skipStatusChecks` goes (nothing automerges); the Dockerfile's `ARG` versions are read too. `renovate-config-validator --strict` passes on all six files.
- **Pinned sources:** the Grafana dashboards fetched from `main` branches pinned to the release Flux deploys (Envoy Gateway, External Secrets) or a commit (no releases: the Flux and Vault dashboards); Fluent Bit's `busybox` image tagged. The Spegel dashboard is gone: its URL answered 404, and the grafana.com version queries metric names k3s's embedded Spegel does not export.
- **Small:** ansible.cfg (no `./collections` path, no commented-out vault password, final newline); "IP to HAProxy" (it is kube-vip); "architectire".

Validation: render equality for every Flux path except the deleted apps and the dashboard URLs; syntax-check, lint. Rollback: revert.

### Phase 3: CI and repository gates

- `.github/workflows/ci.yml`, one job per layer. Every action pinned to a commit SHA (Renovate keeps them current with `helpers:pinGitHubActionDigests`), `permissions: contents: read`, superseded runs cancelled.
  - **yaml:** yamllint (Ansible, Kubernetes), actionlint.
  - **ansible:** uv from the lock file, Galaxy requirements, ansible-lint (production profile), `--syntax-check` of every playbook.
  - **kubernetes:** render every Flux path, substitute cluster-settings (`flux envsubst --strict`), validate with kubeconform (Kubernetes schemas and a CRD catalog).
  - **terraform:** `tofu fmt -check`, `tofu init -backend=false`, `tofu validate` per module.
  - **shell:** shellcheck of every shell script.
  - **dockerfiles:** hadolint (`.hadolint.yaml`: distribution package versions stay unpinned).
  - **secrets:** gitleaks over the whole history (`.gitleaks.toml`: Kubernetes Secret names are not secrets).
  - **renovate:** `renovate-config-validator --strict`.
- `make verify` runs the same checks in the runner, through the same scripts CI calls (`scripts/`); the flux CLI, kubeconform and shellcheck join the runner image, which mounts the repository at `/repo`.
- `ansible-runner.sh` asks Docker for a TTY only when it has one: no `script -qec` wrapper outside a terminal. The runner refuses to start as root (it would mount root's keys and secrets).
- On GitHub, by the user: branch protection on `master` (pull request required, CI jobs required, no force push).

Found by the new checks and fixed in the same PR: the dev cluster-settings lacked `TRUSTED_INTERNAL_POD_CIDR` (Flux would have substituted an empty string); the mixin generator installed its Go tools at `@latest`, and its `rm -rf` could expand to `/*` with an empty variable. For later: `terraform/minio` reads Vault secrets through a deprecated data source; the ephemeral resource that replaces it also keeps them out of the state (phase 8).

Validation (2026-11-10): every check passes in the new runner image (85 s), actionlint and hadolint are clean, the Renovate validator passes. The first CI run on GitHub is the last proof.

### Phase 4: structure

Behavior stays the same, proven by render equality and a dump of every Ansible variable on every host before and after.

- **Variables by topic.** `vars/picluster.yml` and `group_vars/all.yml` become `group_vars/all/` (site, k3s, external services, backup, offsite, versions). The 21 `include_vars` of `vars/picluster.yml` go, and with them the namespace workaround in `tasks/power_loss.yml`. The precedence drops from `include_vars` to group_vars: each variable is checked against play vars, role vars, group_vars and host_vars that could now win.
- **One Vault session.** `tasks/vault_session.yml` reads `~/.secrets/vault.env`, checks it and sets `vault_addr`, `vault_token` and `vault_cacert`. It replaces the copies in 11 files (60 lines twice in `k3s_install.yml` alone).
- **One site file (target).** The owner's values in `ansible/group_vars/all/site.yml` (domain, email, time zone, IQN prefix, fork URL, private repo) and in `cluster-settings.yaml` for Kubernetes. The cert-manager email and groupName and the Flux sync URL come from cluster-settings through Flux substitution; the gateway script reads the MAC addresses from the inventory; CI checks that site.yml and cluster-settings agree. The quick start goes from ten files to about three plus the inventory.
- **Not done:** moving the playbooks into `ansible/playbooks/`. Ansible resolves group_vars, templates and task files relative to the playbook: every path would change and nothing would work better.

Validation: render equality, the variable dump, syntax-check, and check-mode runs (`--check`) of `setup_picluster.yml` and `backup_configuration.yml` with nothing changed.

### Phase 5: alerts reach a person

- **Telegram.** The user creates a bot (BotFather) and a chat. Bot token and chat ID go into Vault (`secret/alerting/telegram`) through `make secret-files`; nothing about the bot is in Git.
- **Alertmanager.** Its whole configuration comes from an ExternalSecret template (`alertmanagerSpec.configSecret`): the chart's default routes and inhibit rules plus a Telegram receiver; `Watchdog` stays on `null`.
- **Gatus** on the Oracle VM: Telegram alerting, `failure-threshold: 3` (the first checks after a VM boot fail before the tunnel is up), `send-on-resolved: true`. The token comes from Vault into the config file on the VM (mode 0600).

Validation: a test alert (`amtool alert add`) arrives and resolves; a temporary Gatus check against a closed port alerts and resolves. Rollback: the receiver back to `null`, Gatus without alerting.

### Phase 6: decisions, incidents, runbooks, contributor docs

- **Decision records** (`docs/adr/`, context, decision, consequences): state outside the cluster; pull-based GitOps; no inbound ports; one pod per service and one Longhorn replica; node6 the only API server; long leader leases; power-loss recovery and the disk write cache; encryption before data leaves the house.
- **Incident write-ups** (`docs/incidents/`, blameless: impact, timeline, cause, what changed): node3 thrashing under Rancher (2026-10-30); node6's k3s crash loop after the Istio merge (2026-11-07); the power cuts and etcd corruption (2026-11-08); containerd CPU on node6 from Rancher's chart catalogs (2026-11-08).
- **Comments** give the reason, not the history: dates and phase numbers out, a link to the decision or incident in.
- **Runbooks:** restore (a Velero namespace with its volume, Vault from a Raft snapshot, etcd from an S3 snapshot), reprovision a node (cloud-init to rejoin, known_hosts), certificate renewal failure. The power cycle stays in [backup and recovery](../backup-and-recovery.md).
- **Contributor files:** CONTRIBUTING.md (layout, style rules, verification, branch and Flux test workflow, commit messages), CODEOWNERS, a pull request template, SECURITY.md, .editorconfig, .pre-commit-config.yaml (the fast CI checks).
- **README:** a status section instead of "Next: Cluster 2.0", the single API server among the design decisions, a CI badge, numbers with their date. CHANGELOG.md; tag `v3.0.0` when this plan is done.

### Phase 7: pod security

- Pod Security Admission labels on every namespace in the repo: `warn` and `audit` at `restricted`; `enforce` at `baseline` where every pod passes, `privileged` where an app needs the host (kube-system, longhorn-system and the namespaces of Fluent Bit, node-exporter, the Velero node agent and system-upgrade).
- Each namespace is checked first with a server-side dry run (`kubectl label --dry-run=server`), which lists the pods that would violate the level.
- Live: labels only. Running pods are not touched; a new pod that violates the level is refused. No Cilium change.
- Not in 3.0: default-deny NetworkPolicies. Every policy change regenerates Cilium endpoints, on node6 at full CPU for minutes; later, one namespace at a time with node6's CPU measured.

### Phase 8: recovery proven

- **Drills,** run by the user; results with measured times in [backup and recovery](../backup-and-recovery.md):
  - Velero: restore one namespace with its volume into a new namespace, compare, delete.
  - Offsite: `restic check --read-data-subset` and a file restore from the Oracle VM.
  - Vault: restore the latest Raft snapshot into a throwaway Vault (a container on pimaster), unseal, read a secret.
  - etcd: `etcdutl snapshot status` on the latest S3 snapshot (a restore would reset the cluster).
- **Monthly `restic check`** on node1 (a systemd timer); a failed run alerts.
- **Terraform state encrypted** (OpenTofu state encryption, passphrase in `~/.secrets`, migrated with an unencrypted fallback): one apply per module, by the user.
- **Recovery objectives** written down: how much data each failure can lose and how long recovery takes (a node, node6, node1, the house).
- **Optional, the user decides:** the full rebuild drill on the 2.0 layout (`make clean`, `make init`): done 2026-11-10, about an hour from `make clean` to every Flux app ready ([times](../backup-and-recovery.md#full-rebuild)).

## Not in 3.0

- A second API server: no hardware.
- A dedicated Ansible user instead of root: done outside this plan, with the 2026-11-10 rebuild in [Control host in Oracle Cloud](control-host-oci.md). Ansible logs in as `ansible` with sudo, and no node accepts root SSH.
- Default-deny NetworkPolicies (phase 7).
- Moving the playbooks (phase 4).

## Done when

- Every pull request runs the CI jobs, and `master` requires them.
- No inverted TLS check is left, host keys are checked, the kubeconfig is 0600 on every server.
- A test alert reaches Telegram from Alertmanager and from Gatus.
- A newcomer edits about three files plus the inventory (quick start).
- Each drill in phase 8 has a date and a measured time in backup and recovery.
- `v3.0.0` is tagged.
