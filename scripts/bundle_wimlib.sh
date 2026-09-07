#!/bin/bash
# Bundle wimlib and its non-system dylibs; no Homebrew dependency at runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIM_PREFIX="$(brew --prefix wimlib)"
mkdir -p "$ROOT/vendor"
cp "$WIM_PREFIX/bin/wimlib-imagex" "$ROOT/vendor/wimlib-imagex"
cp "$WIM_PREFIX/lib/libwim.15.dylib" "$ROOT/vendor/libwim.15.dylib"
chmod u+w "$ROOT/vendor/wimlib-imagex" "$ROOT/vendor/libwim.15.dylib"
WIM_LINK=$(otool -L "$ROOT/vendor/wimlib-imagex" | awk '/libwim.*dylib/ {print $1; exit}')
install_name_tool -change "$WIM_LINK" '@executable_path/libwim.15.dylib' "$ROOT/vendor/wimlib-imagex"
install_name_tool -id '@loader_path/libwim.15.dylib' "$ROOT/vendor/libwim.15.dylib"
# Fail instead of distributing a binary with unresolved Homebrew dependencies.
if otool -L "$ROOT/vendor/"* | grep -E '/opt/homebrew/|/usr/local/'; then
    echo 'Additional non-system libraries must be bundled.' >&2
    exit 1
fi
cp "$WIM_PREFIX/COPYING" "$ROOT/vendor/WIMLIB-COPYING"
cp "$WIM_PREFIX/COPYING.GPLv3" "$ROOT/vendor/WIMLIB-COPYING.GPLv3"
codesign --force --sign - "$ROOT/vendor/libwim.15.dylib"
codesign --force --sign - "$ROOT/vendor/wimlib-imagex"
"$ROOT/vendor/wimlib-imagex" --version
