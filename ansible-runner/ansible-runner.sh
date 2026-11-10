#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${ANSIBLE_RUNNER_MODE:-docker}"

if [[ "${MODE}" == "local" ]]; then
    cd "${REPO_ROOT}/ansible"
    exec uv run "$@"
fi

# Run the command in the runner container, in a login shell (loads the runner
# user's profile and venv). A TTY only when there is one: scripts and CI have none
TTY=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY="-t"
fi

exec docker exec -i ${TTY:+"$TTY"} ansible-runner /bin/bash -lc "$(printf ' %q' "$@")"