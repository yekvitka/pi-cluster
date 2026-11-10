#!/usr/bin/env bash
# yamllint of the Ansible and Kubernetes trees, each with its own configuration.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd ansible && yamllint .)
(cd kubernetes && yamllint .)
echo "yamllint: ok"
