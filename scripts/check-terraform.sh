#!/usr/bin/env bash
# tofu fmt, then init without a backend and validate, for every module in
# terraform/. The provider lock files must not change.
set -euo pipefail
cd "$(dirname "$0")/../terraform"

tofu fmt -check -recursive
for module in */; do
  module="${module%/}"
  echo "== $module"
  (cd "$module" && tofu init -backend=false -input=false -lockfile=readonly -no-color >/dev/null && tofu validate -no-color)
done
