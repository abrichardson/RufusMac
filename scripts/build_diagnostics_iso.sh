#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/dist/diagnostics"
docker build --platform linux/amd64 -t macus-diagnostics-builder:bookworm "$ROOT/diagnostics"
# Privileges are confined to the Docker Linux VM. Only source (read-only) and
# this build's output directory are mounted; no host disks are passed through.
BUILD_CONTAINER="macus-diagnostics-build-$(date +%Y%m%d%H%M%S)"
# Preserve the container on failure for recovery. Execute a private script copy
# so edits in the workspace cannot change a running shell script's contents.
docker run --name "$BUILD_CONTAINER" --platform linux/amd64 --privileged \
  --mount "type=bind,source=$ROOT,target=/src,readonly" \
  --mount "type=bind,source=$ROOT/dist/diagnostics,target=/out" \
    macus-diagnostics-builder:bookworm bash -c 'cp /src/scripts/diagnostics/build-live.sh /tmp/build-live.sh; exec bash /tmp/build-live.sh'
docker rm "$BUILD_CONTAINER" >/dev/null
