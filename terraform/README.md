# Terraform (OpenTofu)

Independent modules, each with its own local state (`terraform.tfstate`, gitignored, kept on the control host). Run them inside the Ansible runner.

| Module | Status | Manages | Provider |
|---|---|---|---|
| `minio/` | prod | RustFS buckets, users, policies (`make configure-minio`) | MinIO (RustFS is S3/MinIO compatible) |
| `vault/` | prod | Vault policies, Kubernetes auth roles, secrets (`make configure-vault`) | Vault, Kubernetes |
| `oci/` | prod | Oracle Cloud offsite VM, network, firewall ([docs/offsite.md](../docs/offsite.md)) | OCI |
| `elastic/` | upstream, not deployed | Elasticsearch roles, users, ILM | Elasticsearch |
| `keycloak/` | upstream, not deployed | Keycloak realm, clients, users | Keycloak |

Resource definitions live in each module's `resources/` (JSON/YAML), fed through `locals` and `for_each`; the `.tf` files stay thin.

```shell
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/<module> && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

`vault/` must be planned with `TF_VAR_enable_kubernetes_auth=true`: with false it plans to destroy the Kubernetes auth backend that External Secrets uses.
