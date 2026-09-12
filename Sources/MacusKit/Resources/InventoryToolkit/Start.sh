#!/bin/sh
set -eu
# Invoke with bash/sh even on exFAT or a noexec USB mount.
TOOLKIT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$(uname -s)" != Linux ]; then
  echo 'Boot a Linux live session on the PC, then run this launcher there.' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 is required. Use an Ubuntu Desktop live session.' >&2
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  exec python3 "$TOOLKIT_DIR/inventory.py" "$@"
fi
exec sudo python3 "$TOOLKIT_DIR/inventory.py" "$@"
