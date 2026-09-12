#!/bin/bash
# Derive a separate Quick Scan appliance from the full diagnostics ISO.
set -euo pipefail
BASE=${1:-/base/Macus-Diagnostics-amd64.iso}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
xorriso -osirrox on -indev "$BASE" \
  -extract /live/filesystem.squashfs "$WORK/root.squashfs" \
  -extract /sha256sum.txt "$WORK/sha256sum.txt" >/dev/null 2>&1
unsquashfs -no-progress -d "$WORK/root" "$WORK/root.squashfs" >/dev/null
cp /src/diagnostics/quickscan/enhancements.py "$WORK/root/opt/macus/enhancements.py"
date -u +%Y-%m-%dT%H:%M:%S+00:00 > "$WORK/root/opt/macus/image-built-at"
cp /src/diagnostics/quickscan/quickscan.py "$WORK/root/opt/macus/quickscan.py"
# Full Diagnostics remains available from the boot menu; default bypasses Xorg.
cat > "$WORK/root/opt/macus/launch.sh" <<'LAUNCH'
#!/bin/sh
if grep -q 'macus.full=1' /proc/cmdline; then
    exec /usr/bin/xinit /opt/macus/session.sh -- :0 vt1 -nolisten tcp
fi
exec >/dev/tty1 2>&1
exec /usr/bin/python3 -u /opt/macus/quickscan.py
LAUNCH
chmod +x "$WORK/root/opt/macus/launch.sh"
sed -i 's/Restart=on-failure/Restart=no/' "$WORK/root/etc/systemd/system/macus-diagnostics.service"
cat > "$WORK/live.cfg" <<'BIOS'
label quickscan
 menu label ^Quick Scan - auto save and shut down
 menu default
 linux /live/vmlinuz
 initrd /live/initrd.img
 append boot=live components quiet noeject nopersistence hostname=macus-quickscan
label full
 menu label ^Full Diagnostics - manual tests
 linux /live/vmlinuz
 initrd /live/initrd.img
 append boot=live components quiet noeject nopersistence hostname=macus-diagnostics macus.full=1
BIOS
cat > "$WORK/grub.cfg" <<'UEFI'
set default=0
set timeout=2
menuentry "Quick Scan - auto save and shut down" {
 linux /live/vmlinuz boot=live components quiet noeject nopersistence hostname=macus-quickscan
 initrd /live/initrd.img
}
menuentry "Full Diagnostics - manual tests" {
 linux /live/vmlinuz boot=live components quiet noeject nopersistence hostname=macus-diagnostics macus.full=1
 initrd /live/initrd.img
}
UEFI
mksquashfs "$WORK/root" "$WORK/new.squashfs" -comp xz -noappend -processors 4 -no-progress >/dev/null
HASH=$(sha256sum "$WORK/new.squashfs" | cut -d ' ' -f 1)
sed -i "/live\/filesystem.squashfs/s/^[0-9a-f]*/$HASH/" "$WORK/sha256sum.txt"
# Update the manifest entries for the two replaced boot menus as well.
for file in live.cfg grub.cfg; do
 HASH=$(sha256sum "$WORK/$file" | cut -d ' ' -f 1)
 sed -i "/\/$file/s/^[0-9a-f]*/$HASH/" "$WORK/sha256sum.txt"
done
xorriso -indev "$BASE" -outdev "$WORK/quickscan.iso" -boot_image any replay \
 -map "$WORK/new.squashfs" /live/filesystem.squashfs \
 -map "$WORK/sha256sum.txt" /sha256sum.txt \
 -map "$WORK/live.cfg" /isolinux/live.cfg \
 -map "$WORK/grub.cfg" /boot/grub/grub.cfg >/dev/null 2>&1
cp "$WORK/quickscan.iso" /out/Macus-QuickScan-amd64.iso
bash /src/scripts/diagnostics/make-usb-image.sh /out/Macus-QuickScan-amd64.iso /out/Macus-QuickScan-USB.img
(cd /out && sha256sum Macus-QuickScan-amd64.iso > Macus-QuickScan-amd64.iso.sha256)
