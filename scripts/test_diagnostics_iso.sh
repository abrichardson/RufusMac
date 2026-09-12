#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Native host architecture QEMU avoids nested x86 emulation on Apple Silicon.
docker build -f "$ROOT/diagnostics/Test.Dockerfile" -t macus-diagnostics-test:bookworm "$ROOT/diagnostics"
docker run --rm \
  --mount "type=bind,source=$ROOT,target=/src,readonly" \
  --mount "type=bind,source=$ROOT/dist/diagnostics,target=/out" \
  macus-diagnostics-test:bookworm bash -c 'cp /src/scripts/diagnostics/test-boot.sh /tmp/test-boot.sh; exec bash /tmp/test-boot.sh'

docker run --rm \
  --mount "type=bind,source=$ROOT,target=/src,readonly" \
  --mount "type=bind,source=$ROOT/dist/diagnostics,target=/out" \
  macus-diagnostics-test:bookworm bash -c 'cp /src/scripts/diagnostics/test-usb-boot.sh /tmp/test-usb-boot.sh; exec bash /tmp/test-usb-boot.sh'
