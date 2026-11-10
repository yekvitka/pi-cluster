# Deploy workflow and self-hosted runner

Continuous delivery from `master` (`.github/workflows/deploy.yml`), run by a
GitHub Actions runner on pimaster. pimaster already holds everything a deploy
needs (the runner image, `~/.secrets`, the node SSH key, the kubeconfig). The
runner connects out to GitHub over HTTPS, so it needs no inbound port.

## What runs, and when

| Trigger | Job | Gate |
|---|---|---|
| push to master | Flux reconcile (`flux-system` with its source) | none |
| push, `terraform/minio/` changed | `configure_minio.yml` plan, then apply of that saved plan | `terraform-apply` approval |
| push, `ansible/` or `terraform/vault/` changed | step summary: apply by hand | none |
| Run workflow | one playbook with `--check --diff`, then the real run if `dry_run` is unticked | `ansible-deploy` approval |

Never run from CI: `k3s_install.yml`, `k3s_reset.yml`, `k3s_bootstrap.yml`,
`external_services.yml`, `make configure-vault` (the Vault module runs before
RustFS exists, so its state stays local: it's the bootstrap layer).

### The repository is public

That has two consequences, and the setup below handles both:

- **Workflow files are untrusted.** A fork pull request can edit `ci.yml` to
  `runs-on: [self-hosted, pimaster]`. The runner therefore runs
  `scripts/runner-job-guard.sh` on the host before every job: only
  `deploy.yml` from `refs/heads/master`, started by `push` or
  `workflow_dispatch`, gets past it. The check sits on the host, where a pull
  request can't change it. Requiring approval for fork pull request workflows
  is a second layer, not the only one.
- **Actions logs are public.** `--diff` prints rendered templates, and plan
  output names resources. `scripts/deploy-run.sh` writes the full output to
  `~/deploy-logs/<run id>/<job>.log` on pimaster (mode 600, kept 30 days).
  The job log only gets the play recap, plan and apply totals, and the failed
  task and host.

Jobs run in a one-off container of the runner image started from the job's
own checkout (`docker compose -p deploy run`). The long-running
`ansible-runner` container and the working clone `/home/pimaster/pi-cluster`
are never touched, so a feature branch checked out there is safe.

## 1. GitHub settings (before the runner starts)

Do this first. A job that names an environment that doesn't exist yet
creates it without protection rules and runs straight away: on 2026-11-10
the first queued `minio-apply` ran unapproved this way (a no-op plan, so
nothing changed).

**Settings → Environments**: create `terraform-apply` and `ansible-deploy`,
each with:

- Required reviewers: `yekvitka`
- Deployment branches and tags: **Selected branches → `master`**

**Settings → Actions → General**

- Fork pull request workflows from outside collaborators: **Require approval
  for all outside collaborators**.
- Workflow permissions: **Read repository contents** (the default).

The environments hold no secrets. Credentials stay on pimaster.

## 2. Install the runner (pimaster, as `pimaster`)

`pimaster` must be in the `docker` group (it is) and have sudo for the
service. On GitHub: **Settings → Actions → Runners → New self-hosted runner →
Linux**, architecture ARM64 (the Oracle VM is an Ampere A1). Use the download
commands and version shown on that page, into `~/actions-runner`. Then:

```bash
cd ~/actions-runner
./config.sh --url https://github.com/yekvitka/pi-cluster --token <TOKEN> \
  --name pimaster --labels pimaster --work _work --unattended

# Host-side guard, root-owned: jobs run as pimaster and can't change it
sudo install -d -m 755 /usr/local/libexec
sudo install -o root -g root -m 755 ~/pi-cluster/scripts/runner-job-guard.sh \
  /usr/local/libexec/gha-job-guard.sh
echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/libexec/gha-job-guard.sh" >> .env

# PATH for jobs: svc.sh copies the current shell's PATH into .path, which in
# a VS Code terminal includes the editor's own directories
echo "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" > .path

sudo ./svc.sh install pimaster
sudo ./svc.sh start
```

After any change to `scripts/runner-job-guard.sh` on master, re-run the
`sudo install` line. The runner updates itself. Logs:
`journalctl -u 'actions.runner.*' -f`; the guard's exit code per job is in
`~/actions-runner/_diag/Worker_*.log` (`gha-job-guard.sh`, then
`Finished process … with exit code`).

## 3. Move the minio state to RustFS

One time, on pimaster in `~/pi-cluster`, on a branch that contains this
change.

```bash
# 1. Bucket terraform-state with versioning (deploy_rustfs.yml, idempotent)
make deploy-rustfs

# 2. Back up the local state
mkdir -p ~/tfstate-backup
cp terraform/minio/terraform.tfstate ~/tfstate-backup/minio-$(date +%F).tfstate

# 3. Copy it into the bucket, plan only: expect "No changes."
./ansible-runner/ansible-runner.sh ansible-playbook configure_minio.yml \
  -e tofu_migrate_state=true -e plan_only=true

# 4. The local files are now stale: move them out of the module
mv terraform/minio/terraform.tfstate terraform/minio/terraform.tfstate.backup \
  ~/tfstate-backup/
```

If step 3 fails on the lock file (`PreconditionFailed` or `NotImplemented` on
`terraform.tfstate.tflock`), RustFS doesn't support S3 conditional writes:
set `use_lockfile = false` in `terraform/minio/provider.tf` and run step 3
again. Then the only lock is the workflow's `deploy` concurrency group, so
don't run `make configure-minio` while a deploy is waiting for approval.

To roll back, remove the `backend "s3"` block, put the backup back as
`terraform/minio/terraform.tfstate` and run `tofu init -reconfigure`. Every
earlier version of the state is also kept in the bucket (versioning).

## 4. Smoke test

1. Merge any change. The Deploy run shows **Flux reconcile** green, and the
   runner log shows `runner guard: … allowed`.
2. Open a pull request whose workflow targets `[self-hosted, pimaster]`: the
   job must fail with `runner guard: event 'pull_request' may not run on this
   runner`.
3. Change a file under `terraform/minio/` (a description in
   `resources/buckets/`). Expect **Terraform minio plan**, then a review
   request for `terraform-apply`.

## Day to day

**Approving an apply.** Read the plan totals in the job summary. For the
details, open `~/deploy-logs/<run id>/minio-plan.log` on pimaster. Then
**Review deployments → Approve and deploy**. The apply uses the saved plan.
If the state changed in the meantime, OpenTofu refuses it (`Saved plan is
stale`): push again, or run the workflow again.

**Ansible.** Actions → Deploy → **Run workflow**: pick the playbook and add
`extra_args` (`--tags node --limit node4`). Keep `dry_run` ticked to see the
`--check` result (diff in `~/deploy-logs/<run id>/ansible-check.log`), then
run it again unticked and approve `ansible-deploy`.

**Queueing.** One deploy at a time. A run waiting for approval holds the
queue. GitHub keeps only one pending run, so a third push replaces the second
pending one, and the newest run carries all changes anyway.

**Runner image.** Jobs use the `ansible-runner` image as built on pimaster.
After a Dockerfile change, rebuild it (`make ansible-runner-setup`) before
relying on the change in CI.
