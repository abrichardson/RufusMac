#!/usr/bin/env bash
set -euo pipefail

# fetch_thirdparty.sh — fetch the external CLI tools Macus bundles for the
# Windows / multiboot / persistence engines. Built-in tools (diskutil, hdiutil,
# dd) are always present; this adds the extras into ./vendor, which
# scripts/build_app.sh copies into Macus.app/Contents/Resources/thirdparty.
#
# Best-effort: prefers Homebrew for wimlib/e2fsprogs. Linux/Reclaim modes work
# WITHOUT these; Windows (WIM split) and Multiboot/persistence need them.
#
# NOTE: Homebrew binaries link against Homebrew libraries. For a fully portable
# build, post-process with `dylibbundler` or use static builds. See docs/THIRD_PARTY.md.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
mkdir -p "$VENDOR"

echo "▶ Fetching third-party tools into $VENDOR"

if command -v brew >/dev/null 2>&1; then
  brew list wimlib    >/dev/null 2>&1 || brew install wimlib
  brew list e2fsprogs >/dev/null 2>&1 || brew install e2fsprogs

  WIMLIB="$(brew --prefix wimlib 2>/dev/null)/bin/wimlib-imagex"
  MKE2FS="$(brew --prefix e2fsprogs 2>/dev/null)/sbin/mke2fs"
  [ -f "$WIMLIB" ] && cp "$WIMLIB" "$VENDOR/" && echo "  • wimlib-imagex"
  [ -f "$MKE2FS" ] && cp "$MKE2FS" "$VENDOR/" && echo "  • mke2fs"
else
  echo "  ! Homebrew not found — install it (https://brew.sh) or place wimlib-imagex and mke2fs in $VENDOR manually."
fi

# Ventoy boot files (for experimental Multiboot mode). Pin a known version.
VENTOY_VERSION="${VENTOY_VERSION:-1.1.05}"
echo "▶ Ventoy $VENTOY_VERSION boot files"
echo "  Download the Linux release from https://github.com/ventoy/Ventoy/releases"
echo "  and extract its boot/ + ventoy/ payload into $VENDOR/ventoy/ (see docs/THIRD_PARTY.md)."

# Rufus UEFI:NTFS image (for the optional NTFS Windows path).
echo "▶ uefi-ntfs.img"
echo "  Obtain from https://github.com/pbatard/rufus (uefi-ntfs) and place at $VENDOR/uefi-ntfs.img"

echo "✅ Done. Re-run scripts/build_app.sh to bundle these into the app."
