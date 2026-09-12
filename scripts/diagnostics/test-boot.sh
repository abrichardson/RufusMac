#!/bin/bash
# Run in the test container. Only disposable virtual USB files are written.
set -euo pipefail
ISO=/out/Macus-Diagnostics-amd64.iso
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
# Instrument a test-only copy through the actual BIOS and EFI boot menus.
# Production bootloader settings, kernel, root filesystem and graphical app stay intact.
xorriso -osirrox on -indev "$ISO" \
  -extract /boot/grub/grub.cfg "$TEST_DIR/grub.cfg" \
  -extract /isolinux/live.cfg "$TEST_DIR/live.cfg" >/dev/null 2>&1
sed -i 's/boot=live/boot=live macus.selftest=1 console=ttyS0 console=tty0/g' "$TEST_DIR/grub.cfg" "$TEST_DIR/live.cfg"
xorriso -indev "$ISO" -outdev "$TEST_DIR/test.iso" -boot_image any replay \
  -map "$TEST_DIR/grub.cfg" /boot/grub/grub.cfg \
  -map "$TEST_DIR/live.cfg" /isolinux/live.cfg >/dev/null 2>&1
for firmware in bios uefi; do
  truncate -s 64M "$TEST_DIR/reports-$firmware.img"
  mkfs.vfat "$TEST_DIR/reports-$firmware.img" >/dev/null
  printf '%s\n' '{"schema_version":1,"purpose":"macus-diagnostics"}' > "$TEST_DIR/marker.json"
  mcopy -i "$TEST_DIR/reports-$firmware.img" "$TEST_DIR/marker.json" ::/.macus-diagnostics.json
  args=()
  if [ "$firmware" = uefi ]; then
    cp /usr/share/OVMF/OVMF_VARS.fd "$TEST_DIR/vars.fd"
    args=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd -drive "if=pflash,format=raw,file=$TEST_DIR/vars.fd")
  fi
  echo "Testing $firmware live boot…"
  python3 /src/scripts/diagnostics/run-vm.py "$firmware" "$TEST_DIR/monitor.sock" qemu-system-x86_64 -machine q35,accel=tcg -cpu max -m 2048 -smp 2 \
    "${args[@]}" -boot d -cdrom "$TEST_DIR/test.iso" -device qemu-xhci \
    -drive "if=none,id=reports,format=raw,file=$TEST_DIR/reports-$firmware.img" \
    -device usb-storage,drive=reports -display none -vga std -serial "file:/out/boot-test-$firmware.log" \
    -monitor "unix:$TEST_DIR/monitor.sock,server,nowait" -no-reboot -nic none || { tail -n 100 "/out/boot-test-$firmware.log"; exit 1; }
  if ! grep -q MACUS_SELFTEST_PASSED "/out/boot-test-$firmware.log"; then
    tail -n 100 "/out/boot-test-$firmware.log"
    exit 1
  fi
  mkdir -p "/out/boot-test-reports/$firmware"
  mcopy -s -i "$TEST_DIR/reports-$firmware.img" ::/MacusReports "/out/boot-test-reports/$firmware/"
done
python3 - <<'PY'
import json
from pathlib import Path
for firmware in ['bios', 'uefi']:
    reports = list((Path('/out/boot-test-reports') / firmware).rglob('report.json'))
    assert reports, 'No report survived shutdown: ' + firmware
    for path in reports:
        report = json.loads(path.read_text())
        assert report['asset_id'] == 'VM-BOOT-TEST'
        assert report['schema_version'] == 1
        assert report['system']['cpu']
        assert path.with_name('report.html').exists()
        assert path.with_name('summary.csv').exists()
print('PASS: BIOS and UEFI graphical live boot, automatic scan, USB discovery, saved reports and shutdown')
PY
