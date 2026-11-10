#!/usr/bin/env bash
# tofu fmt, then init without a backend and validate, for every module in
# terraform/. The provider lock files must not change. Each module gets a
# throwaway TF_DATA_DIR: a module's own .terraform may hold a real backend
# (minio: S3 on RustFS), which validate would otherwise try to reach.
set -euo pipefail
cd "$(dirname "$0")/../terraform"
data_dirs="$(mktemp -d)"
trap 'rm -rf "$data_dirs"' EXIT

tofu fmt -check -recursive
for module in */; do
  module="${module%/}"
  echo "== $module"
  (cd "$module" && export TF_DATA_DIR="$data_dirs/$module" && tofu init -backend=false -input=false -lockfile=readonly -no-color >/dev/null && tofu validate -no-color)
done
