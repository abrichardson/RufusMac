#!/bin/bash
# Development-only refresh of Python UI/collector files without reinstalling Linux.
set -euo pipefail
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
ISO=/out/Macus-Diagnostics-amd64.iso
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$TEMP_DIR/root.squashfs" \
  -extract /sha256sum.txt "$TEMP_DIR/sha256sum.txt" >/dev/null 2>&1
unsquashfs -no-progress -d "$TEMP_DIR/root" "$TEMP_DIR/root.squashfs" >/dev/null
cp /src/diagnostics/{app.py,storage.py} "$TEMP_DIR/root/opt/macus/"
cp /src/Sources/MacusKit/Resources/InventoryToolkit/inventory.py "$TEMP_DIR/root/opt/macus/"
cp /usr/share/misc/pci.ids "$TEMP_DIR/root/usr/share/misc/pci.ids"
mksquashfs "$TEMP_DIR/root" "$TEMP_DIR/new.squashfs" -comp xz -noappend -processors 4 -no-progress >/dev/null
HASH=$(sha256sum "$TEMP_DIR/new.squashfs" | cut -d ' ' -f 1)
sed -i "/live\/filesystem.squashfs/s/^[0-9a-f]*/$HASH/" "$TEMP_DIR/sha256sum.txt"
xorriso -indev "$ISO" -outdev "$TEMP_DIR/new.iso" -boot_image any replay \
  -map "$TEMP_DIR/new.squashfs" /live/filesystem.squashfs \
  -map "$TEMP_DIR/sha256sum.txt" /sha256sum.txt >/dev/null 2>&1
cp "$TEMP_DIR/new.iso" /out/Macus-Diagnostics-amd64.iso.new
mv /out/Macus-Diagnostics-amd64.iso.new "$ISO"
cd /out
sha256sum Macus-Diagnostics-amd64.iso > Macus-Diagnostics-amd64.iso.sha256
