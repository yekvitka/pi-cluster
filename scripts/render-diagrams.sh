#!/usr/bin/env bash
# Renders docs/diagrams/*.mmd (Mermaid) to docs/images/<name>.png. The README
# embeds the PNG instead of a mermaid block: GitHub Mobile shows Mermaid as raw
# code, and a PNG looks the same on every device (an SVG's labels depend on the
# viewer's fonts). White background: readable in light and dark mode.
#
# Usage: scripts/render-diagrams.sh   (needs Docker; commit the PNGs)
set -euo pipefail
cd "$(dirname "$0")/.."

# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION=12.0.0

for src in docs/diagrams/*.mmd; do
  name="$(basename "$src" .mmd)"
  echo "== $src -> docs/images/${name}.png"
  docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/docs:/data" \
    "minlag/mermaid-cli:${MERMAID_CLI_VERSION}" \
    -i "/data/diagrams/${name}.mmd" -o "/data/images/${name}.png" \
    --backgroundColor white --size 2000 --scale 2
done
