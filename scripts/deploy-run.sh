#!/usr/bin/env bash
# Runs one command for the Deploy workflow (.github/workflows/deploy.yml) in a
# one-off ansible-runner container started from this checkout, never the
# long-running container, which mounts the working clone.
#
# The repository is public and so are its Actions logs: the full output goes to
# ~/deploy-logs/<run id>/<name>.log on this host, the job log only gets a
# summary (play recap, plan/apply totals, the failed task and host).
#
# Usage: scripts/deploy-run.sh <name> <command...>
set -euo pipefail

name="$1"
shift
repo="$(cd "$(dirname "$0")/.." && pwd)"
logs="${HOME}/deploy-logs"
log_dir="${logs}/${GITHUB_RUN_ID:-local}"
log="${log_dir}/${name}.log"

mkdir -p "$log_dir"
chmod 700 "$logs" "$log_dir"
find "$logs" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +

set +e
docker compose -p deploy -f "${repo}/ansible-runner/docker-compose.yaml" \
  run --rm -T -e ANSIBLE_NOCOLOR=1 -e NO_COLOR=1 ansible-runner \
  bash -lc "$(printf ' %q' "$@")" >"$log" 2>&1
status=$?
set -e
chmod 600 "$log"

{
  # Ansible: the recap, and for a failure the task and host without the message
  awk '
    /^TASK \[/ { task = $0 }
    /^(fatal|failed): \[/ {
      match($0, /^[a-z]+: \[[^]]*\]/)
      print task
      print substr($0, 1, RLENGTH)
      next
    }
    /^PLAY RECAP/ { recap = 1 }
    recap && NF == 0 { recap = 0 }
    recap { print }
  ' "$log"
  # OpenTofu and Flux: totals only, never resource details
  grep -oE 'Plan: [0-9]+ to add, [0-9]+ to change, [0-9]+ to destroy|No changes\.|Apply complete! Resources: [^.]*\.|Saved plan is stale|(fetched|applied) revision [^ ]+' "$log" | uniq || true
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "Full log on $(hostname): ${log}"
exit "$status"
