#!/usr/bin/env bash
# yamllint of the Ansible and Kubernetes trees, each with its own configuration.
# Also checks that dns_domain in site.yml matches CLUSTER_DOMAIN in cluster-settings.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd ansible && yamllint .)
(cd kubernetes && yamllint .)
echo "yamllint: ok"

python3 - <<'EOF'
import sys
import yaml

with open("ansible/group_vars/all/site.yml") as f:
    site = yaml.safe_load(f)
with open("kubernetes/clusters/prod/config/cluster-settings.yaml") as f:
    settings = yaml.safe_load(f)

dns_domain = site.get("dns_domain", "")
cluster_domain = (settings.get("data") or {}).get("CLUSTER_DOMAIN", "")

if dns_domain != cluster_domain:
    print(
        f"ERROR: dns_domain in group_vars/all/site.yml ({dns_domain!r}) does not match "
        f"CLUSTER_DOMAIN in clusters/prod/config/cluster-settings.yaml ({cluster_domain!r})"
    )
    sys.exit(1)

print(f"site: dns_domain and CLUSTER_DOMAIN agree ({dns_domain!r})")
EOF
