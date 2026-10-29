# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

Pi Kubernetes Cluster — a homelab monorepo for a Raspberry Pi K3s cluster (fork of github.com/ricsanfre/pi-cluster), automated with Ansible and FluxCD. Contains bare-metal provisioning (`metal/`), host configuration, external services (Vault/RustFS/DNS), Terraform/OpenTofu configuration, and Kubernetes platform apps.

## Tool versions (managed via mise, see `.mise.toml`)

```
kubectl 1.37.0 | flux2 2.9.5 | velero 1.18.2 | istioctl 1.31.0 | helm 4.3.0 | opentofu 1.12.6 | longhorn cli 1.12.1 | cilium-cli 0.20.0
```

## Common commands

All operational commands run through the Makefile at repo root. The Makefile wraps everything through the Ansible runner container. Run `make help` for the full target list.

### Setup and linting

```bash
# Build the Docker-based ansible runner (one-time prerequisite)
make ansible-runner-setup

# CI-parity YAML lint (minimum PR safety check)
make lint-ci

# Local UV-based Ansible environment (alternative to container runner)
make ansible-local-setup
make ansible-local-lint

# Verify uv.lock is in sync with pyproject.toml
make uv-lock-check
```

### Ansible operations (all via runner container)

```bash
# Full cluster initialization:
# os-upgrade → external-setup → nodes-setup → dns-setup → external-services → san-setup → configure-os-backup → k3s-install → k3s-bootstrap
make init

# Individual stages:
make secret-files          # Create encrypted/local secret files
make os-upgrade            # Upgrade OS packages on target nodes (update.yml)
make external-setup        # Configure node1 as external services host (setup_picluster.yml --tags external)
make nodes-setup           # Configure k3s node prerequisites (setup_picluster.yml --tags node)
make dns-setup             # Configure authoritative Bind9 DNS on node1
make external-services     # Deploy/configure Vault and RustFS
make san-setup             # Centralized SAN (no-op while centralized_san: false). Needs Vault
make configure-os-backup   # Configure node backup jobs
make k3s-install           # Install K3s on cluster nodes
make k3s-bootstrap         # Bootstrap FluxCD and cluster services

# Bootstrap with dev overlay (instead of prod)
make k3s-bootstrap-dev

# Destructive operations — never run without explicit user request:
make clean                 # k3s-reset + external-services-reset
make k3s-reset             # Remove K3s from all nodes
make external-services-reset

# Shutdown nodes (with 1-minute delay)
make shutdown-k3s-worker
make shutdown-k3s-master
make shutdown-picluster
```

MinIO targets (`deploy-minio`, `configure-minio`) are legacy; use `deploy-rustfs`. `configure-minio` still configures RustFS through the MinIO-compatible Terraform module.

### Terraform validation (safe, no-apply)

```bash
# Run inside the ansible runner container:
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/minio && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/vault && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/elastic && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/keycloak && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

### Running ansible directly (not via Make)

```bash
# Always use the runner wrapper — never run host ansible-playbook directly
./ansible-runner/ansible-runner.sh ansible-playbook --syntax-check external_services.yml
./ansible-runner/ansible-runner.sh ansible-playbook k3s_bootstrap.yml -e overlay=dev

# Local mode (bypasses Docker, uses uv):
ANSIBLE_RUNNER_MODE=local ./ansible-runner/ansible-runner.sh ansible-playbook --version
```

### Verification

There is no unit test suite. "Verify" means, as applicable: `make lint-ci`, `ansible-playbook --syntax-check` via the runner, `tofu validate`/`tofu fmt -check`, and for Kubernetes changes `kubectl kustomize <overlay>` renders cleanly.

## Architecture

### Layered automation flow

```
Cloud-init (OS install, metal/rpi/) → Ansible (OS config + K3s + external services) → FluxCD (cluster apps)
```

The cluster is designed to be fully redeployable from scratch using this chain.

### Ansible layer (`ansible/`)

- **Inventory**: `ansible/inventory.yml` defines host groups: `control` (pimaster, local connection), `picluster` (node1-node5), `raspberrypi` (all nodes), `k3s_cluster` → `k3s_master` (node2-node4) + `k3s_worker` (node5), and `s3`, `dns`, `vault`, `san` (all node1). Nodes run Ubuntu 24.04; node5 boots from SSD. Ansible is run by the `pimaster` user on the control host (`/home/pimaster`, whose `~/.ssh`, `~/.kube`, `~/.secrets` are mounted into the runner); it connects to the nodes over SSH as `root` (`ansible_user: root` in `group_vars/all.yml`). The gateway (10.0.0.1) runs OpenWrt and is not in the inventory: see `metal/openwrt/`. External services (Vault, RustFS, DNS) run on `node1`.
- **Playbooks**: Top-level playbooks in `ansible/*.yml` — most map to a Makefile target. Key ones: `setup_picluster.yml` (node1 / k3s node config, tag-filtered `external`/`node`), `k3s_install.yml`, `k3s_bootstrap.yml` (installs FluxCD and bootstraps cluster services), `external_services.yml` (Vault/RustFS deployment), `deploy_rustfs.yml` (RustFS S3 server install), `configure_dns_authoritative.yml` (Bind9 on node1).
- **Roles**: Custom roles in `ansible/roles/` — `basic_setup`, `dns`, `k3s`.
- **Centralized SAN**: `configure_centralized_san.yml` can make node1 SSD2 an iSCSI target and mount one LUN per k3s node at `/storage` (Longhorn data path). It is currently **disabled** (`centralized_san: false` in `group_vars/all.yml`). node1 SSD1 is `/storage` for RustFS and Vault.
- **Group/host vars**: `ansible/group_vars/` — `all.yml` (global), `k3s_cluster.yml`, `k3s_master.yml`, `external.yml`, `control.yml`. `ansible/host_vars/` — `node1.yml`, `node3.yml`, `node4.yml`, `node5.yml`.
- **Python deps**: Managed by `uv` via `ansible/pyproject.toml` and `ansible/uv.lock`. Key deps: `ansible-core==2.21.4`, `ansible-lint`, `yamllint`, `kubernetes`, `hvac` (Vault client), `certbot` + `certbot-dns-ionos`.
- **Lint config**: `ansible/.yamllint` (extends default, 180-char line limit as warning, ignores `.venv/`, `ansible_collections/`, `roles/ricsanfre.*/`, `docs/`) and `ansible/.ansible-lint`.

### Ansible runner (`ansible-runner/`)

A Docker container that provides a consistent Ansible execution environment with all tooling pre-installed:
- Built from `python:3.14-slim` with OpenTofu, kubectl, helm, uv, and ansible collections/roles baked in.
- Mounts `ansible/`, `kubernetes/`, `terraform/`, SSH keys, kubeconfig, `~/.secrets`, and `~/.certbot` from the host (`docker-compose.yaml`).
- The wrapper script `ansible-runner.sh` runs commands via `docker exec` by default; set `ANSIBLE_RUNNER_MODE=local` to use local `uv run` instead.

### Kubernetes / FluxCD layer (`kubernetes/`)

The cluster follows a **platform** pattern with environment overlays:

```
kubernetes/
├── clusters/           # Flux entrypoints per environment
│   ├── prod/           # Production cluster
│   │   ├── config/     # cluster-settings ConfigMap
│   │   ├── infra/      # Platform infra Kustomizations (one per service)
│   │   └── apps/       # Workload Kustomizations (currently empty)
│   └── dev/            # Dev cluster (k3d-based): config/, infra/
└── platform/           # Shared platform services (Helm + Kustomize)
    └── <service>/
        ├── app/        # HelmRelease manifests
        │   ├── base/           # Base: helm.yaml, ns.yaml, kustomization.yaml, values.yaml
        │   ├── components/     # Reusable patch/value bundles (e.g., dns01, monitoring)
        │   └── overlays/{dev,prod}/  # Env-specific: helm-patch.yaml, kustomization.yaml, values.yaml
        └── config/     # Non-Helm Kubernetes resources (ConfigMaps, policies, etc.)
```

**Flux reconciliation flow**: Flux watches the Git repo → `<service>-app` Kustomization creates namespace + HelmRelease → `<service>-config` depends on `<service>-app` and applies config resources.

**Enabled in prod** (`clusters/prod/infra/kustomization.yaml`): cert-manager, cilium, coredns, csi-external-snapshotter, descheduler, envoy-gateway, external-dns, external-secrets, flux, grafana, kube-prometheus-stack, longhorn, metrics-server, system-upgrade, vault, velero, kube-vip. Disabled to fit 4 GB Pis: fluent, loki, otel-collector, tempo, rancher. Other services in `platform/` (istio, kiali, kafka, keycloak, elastic-stack, eck-operator, databases, …) have no prod Kustomization.

**Key FluxCD patterns**:
- Environment-specific values go in `overlays/{dev,prod}/values.yaml`, never duplicate base manifests.
- Cluster-wide settings live in a ConfigMap (`cluster-settings`) in `clusters/<env>/config/`, consumed by HelmReleases via `valuesFrom`.
- Flux `Kustomization` resources in `clusters/<env>/infra/` point to `platform/<service>/app/overlays/<env>` with `dependsOn` chains for ordering.
- The `boilerplate/` directory contains a `gruntwork-io/boilerplate` template for generating new FluxCD app manifests.

### Terraform layer (`terraform/`)

Four independent modules (OpenTofu), each with its own local state:

| Module | Purpose | Provider |
|--------|---------|----------|
| `minio/` | S3 buckets, users, policies (RustFS backend) | MinIO |
| `vault/` | Vault secrets, policies, K8s auth roles | Vault + Kubernetes |
| `elastic/` | Elasticsearch roles, users, ILM, templates, data views | Elasticsearch |
| `keycloak/` | Keycloak realm, groups, clients, users, scopes | Keycloak |

All modules follow a data-driven pattern: resource definitions are loaded from `resources/` files (JSON/YAML) and fed into Terraform via `locals` + `for_each`, keeping `.tf` files thin. DNS is not managed by Terraform (Bind9 via Ansible, external-dns in-cluster).

### External services

Vault (secrets management) and RustFS (S3 object storage for backups) run **outside the cluster** on `node1`, deployed via Ansible playbooks (`deploy_vault.yml`, `deploy_rustfs.yml`), configured via Terraform (`terraform/vault/`, `terraform/minio/`). RustFS replaces MinIO with an S3-compatible API; the existing `aminueza/minio` Terraform provider is compatible. node1 also serves authoritative DNS (Bind9). This keeps them locally accessible without public internet exposure.

### Dev cluster (`dev/`)

Local development environment using `k3d` (K3s in Docker):
- `create_cluster.sh` provisions a k3d cluster from `k3d-cluster/k3d-cluster.yaml.tmpl`; `dev/Makefile` wraps it
- Dev Flux entrypoint in `kubernetes/clusters/dev/` (infra: cilium, coredns, envoy-gateway, flux, metrics-server)
- Dev overlays in `kubernetes/platform/*/app/overlays/dev/`

## CI

GitHub Actions in `.github/workflows/ci.yml`: runs `yamllint .` inside `ansible/` directory on PRs and pushes to `master`. Renovate config lives in `.github/renovate/`.

## Safety constraints

- **Never run** destructive actions (`make clean`, `make k3s-reset`, `make external-services-reset`, `tofu apply`) without explicit user request.
- Do not run host `ansible-playbook` directly — always use the runner wrapper.
- `scripts/` contains operational scripts (e.g. `recover-valkey-stale-ip.sh`) that expect a live cluster and valid kubeconfig.
- Never edit, delete, or commit `terraform.tfstate*` or `tfplan` files in `terraform/*/` (gitignored local state).
- Treat `make lint-ci` failures on pre-existing issues in untouched files as informational, not blockers.
- Avoid touching generated/vendor trees: `ansible/.ansible/`, `ansible-runner/runner/.kube/cache/`.

## FluxCD PR branch workflow

When validating changes from a feature branch in the live cluster:

1. Create branch `feature/<desc>` or `issue/<desc>` from master
2. Edit `kubernetes/platform/flux-operator/instance/overlays/prod/values.yaml` → set `instance.sync.ref` to the branch
3. Commit and push
4. Patch in-cluster GitRepository to the same branch and reconcile:
   ```bash
   GR_NAME="$(kubectl -n flux-system get gitrepository -o jsonpath='{range .items[?(@.spec.url=="https://github.com/yekvitka/pi-cluster")]}{.metadata.name}{"\n"}{end}' | head -n1)"
   kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"<branch>"}}}'
   flux reconcile source git "${GR_NAME}" -n flux-system
   flux reconcile kustomization flux-system -n flux-system --with-source
   ```
5. After merge: revert `instance.sync.ref` to `refs/heads/master`, push, and patch in-cluster GitRepository back to `master`:
   ```bash
   kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"master","name":null}}}'
   flux reconcile source git "${GR_NAME}" -n flux-system
   ```

## Search strategy

- Start with targeted path-scoped searches: `ansible/**`, `terraform/**`, `kubernetes/**`, `dev/**`, `metal/**`
- Exclude noisy trees: `ansible/.ansible/`, `ansible/.venv/`

## Git Commit Guidelines

- Never add Co-Authored-By to commit messages
- Never add "🤖 Generated with [Claude Code]" or similar attributions to PR bodies

## Additional Claude Code Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
