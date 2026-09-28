#!/usr/bin/env bash
# Gera um .zip por skill em dist/, pronto para upload no claude.ai
# (Settings > Capabilities > Skills > Upload skill).
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist && mkdir -p dist
for dir in plugins/*/skills/*/; do
  name=$(basename "$dir")
  (cd "$(dirname "$dir")" && zip -rq "../../../dist/$name.zip" "$name")
  echo "dist/$name.zip"
done
