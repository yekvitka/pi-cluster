#!/usr/bin/env bash
# Checks every tracked shell script with shellcheck (warnings and errors): *.sh and
# files with a sh, bash or dash shebang. Jinja templates (*.j2) are left out.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts=()
while IFS= read -r file; do
  case "$file" in *.j2) continue ;; esac
  [ -f "$file" ] || continue
  if [[ "$file" == *.sh ]] || head -n1 "$file" | grep -qE '^#!.*\b(ba|da)?sh\b'; then
    scripts+=("$file")
  fi
done < <(git ls-files)

shellcheck --severity=warning "${scripts[@]}"
echo "shellcheck: ${#scripts[@]} scripts ok"
