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
# user's profile and venv)
CMD="docker exec -it ansible-runner \
     /bin/bash -lic"

$CMD "$(printf ' %q' "$@")"