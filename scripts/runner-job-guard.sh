#!/usr/bin/env bash
# Job-started hook for the self-hosted runner on pimaster
# (ACTIONS_RUNNER_HOOK_JOB_STARTED in ~/actions-runner/.env). It runs on the
# host before every job; a non-zero exit fails the job before any step runs.
#
# The repository is public: a fork pull request can edit a workflow to target
# this runner. Workflow files are untrusted, so the check lives here: only
# deploy.yml from master, started by a push or workflow_dispatch, may run.
#
# Install a copy outside the runner's work directory (a job must not be able
# to change it): see docs/runbooks/github-actions-runner.md.
set -euo pipefail

event="${GITHUB_EVENT_NAME:-}"
workflow="${GITHUB_WORKFLOW_REF:-}"
allowed="${GITHUB_REPOSITORY:-}/.github/workflows/deploy.yml@refs/heads/master"

case "$event" in
  push | workflow_dispatch) ;;
  *)
    echo "runner guard: event '${event}' may not run on this runner" >&2
    exit 1
    ;;
esac

if [ -z "${GITHUB_REPOSITORY:-}" ] || [ "$workflow" != "$allowed" ]; then
  echo "runner guard: workflow '${workflow}' may not run on this runner" >&2
  exit 1
fi

echo "runner guard: ${workflow} (${event}) allowed"
