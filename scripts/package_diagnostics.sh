#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=${1:-$ROOT/dist/diagnostics}
cd "$OUTPUT"
# Keep the downloadable boot media independent of the Mac application.
for name in Macus-Diagnostics-USB.img Macus-Diagnostics-amd64.iso; do
  test -f "$name"
  test -f "$name.sha256"
  /usr/bin/zip -q "$name.zip" "$name" "$name.sha256"
done
