# Vault

OpenTofu configuration for the Vault server on node1. Everything Vault holds for the cluster comes from the files in `resources/`.

| Files | Become |
|---|---|
| `resources/secrets/<group>.json` | KV v2 secrets at `secret/<group>/<key>` |
| `resources/policies/*.yaml` | Vault policies |
| `resources/roles/*.json` | Kubernetes auth roles |

The module also mounts the KV v2 engine at `secret/` and sets up Kubernetes auth: a `vault-auth-sa` service account whose token lets Vault review the tokens pods present.

## Secrets

Each key in a group file is one secret. Vault stores its `content` plus a generated password in the field named by `secret_name`: 15 letters and digits, starting with a letter (`password_length` changes the length). Nobody types or sees a password.

```json
{
  "admin": {
    "secret_name": "password",
    "content": { "username": "admin", "service": "grafana" }
  }
}
```

This gives `secret/grafana/admin` with `username`, `service` and `password`. Pods read secrets through External Secrets, which logs in with the `external-secrets` role and its `readonly` policy.

Keys that come from outside (the IONOS API key, the bind9 update key, the GitHub token) are not generated: `make load-external-services-keys` writes them.

## Policies and roles

```yaml
readonly:
  description: "Read-only access to all secrets"
  policy: |
    path "secret/*" {
      capabilities = ["read", "list"]
    }
```

```json
{
  "external-secrets": {
    "service_account_names": ["external-secrets"],
    "service_account_namespaces": ["external-secrets"],
    "policies": ["readonly"],
    "audience": "https://kubernetes.default.svc.cluster.local"
  }
}
```

## Run

```shell
make configure-vault    # plan and apply, no confirmation prompt
```

The playbook reads the Vault address and token from `~/.secrets/vault.env`, then plans and applies right away (`-auto-approve`). To see the plan first, run `tofu plan` in the runner with the same variables. It must use `TF_VAR_enable_kubernetes_auth=true`: with `false` it plans to destroy the Kubernetes auth that External Secrets depends on.

Removing a file or a key deletes those secrets from Vault at the next apply.

Validate without Vault:

```shell
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/vault && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

The state (`terraform.tfstate`) stays on the control host and is not in Git.
