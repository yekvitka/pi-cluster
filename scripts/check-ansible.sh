#!/usr/bin/env bash
# ansible-lint (production profile, ansible/.ansible-lint), the become check
# (check-become.py) and a syntax check of every playbook. Needs the Galaxy
# roles and collections of ansible/requirements.yml.
set -euo pipefail
cd "$(dirname "$0")/../ansible"

ansible-lint
python3 ../scripts/check-become.py

failed=0
for playbook in *.yml; do
  case "$playbook" in inventory.yml | requirements.yml) continue ;; esac
  if ! out=$(ansible-playbook --syntax-check "$playbook" 2>&1); then
    echo "syntax check failed: $playbook"
    echo "$out"
    failed=1
  fi
done
[ "$failed" = 0 ] && echo "syntax check: ok"
exit "$failed"
