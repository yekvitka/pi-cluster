# Terraform (OpenTofu)

Independent modules, each with its own state. Run them inside the Ansible runner. `minio/` keeps its state on RustFS (S3 backend) and is applied by the Deploy workflow after approval ([runbook](../docs/runbooks/github-actions-runner.md)). `vault/` and `oci/` keep local state (`terraform.tfstate`, gitignored, on the control host): the Vault module runs before RustFS exists, so it stays `make configure-vault`.

| Module | Status | Manages | Provider |
|---|---|---|---|
| `minio/` | prod | RustFS buckets, users, policies (`make configure-minio`) | MinIO (RustFS is S3/MinIO compatible) |
| `vault/` | prod | Vault policies, Kubernetes auth roles, secrets (`make configure-vault`) | Vault, Kubernetes |
| `oci/` | prod | Oracle Cloud offsite VM, optional control host VM, network, firewall ([docs/offsite.md](../docs/offsite.md), [docs/control-host.md](../docs/control-host.md#oracle-cloud-vm)) | OCI |

Resource definitions live in each module's `resources/` (JSON/YAML), fed through `locals` and `for_each`; the `.tf` files stay thin.

```shell
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/<module> && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

`vault/` must be planned with `TF_VAR_enable_kubernetes_auth=true`: with false it plans to destroy the Kubernetes auth backend that External Secrets uses.
