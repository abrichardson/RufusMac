#!/bin/bash
set -euo pipefail
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
truncate -s 64M "$WORK/hdd.img"
truncate -s 96M "$WORK/ssd.img"
sha256sum "$WORK/hdd.img" "$WORK/ssd.img" > "$WORK/internal.sha256"
for firmware in bios uefi uefi-repeat save-failure; do
 if [ "$firmware" = uefi-repeat ]; then
  mv "$WORK/usb-uefi.img" "$WORK/usb-$firmware.img"
 elif [ "$firmware" = save-failure ]; then
  mv "$WORK/usb-uefi-repeat.img" "$WORK/usb-$firmware.img"
  mdel -i "$WORK/usb-$firmware.img@@$offset" ::/.macus-diagnostics.json
 else
  cp --sparse=always /out/Macus-QuickScan-USB.img "$WORK/usb-$firmware.img"
 fi
 export EXPECT_SAVE_FAILURE=0
 if [ "$firmware" = save-failure ]; then export EXPECT_SAVE_FAILURE=1; fi
 args=()
 if [ "$firmware" != bios ]; then
  cp /usr/share/OVMF/OVMF_VARS.fd "$WORK/vars.fd"
  args=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd -drive "if=pflash,format=raw,file=$WORK/vars.fd")
 fi
 python3 /src/scripts/diagnostics/test-quickscan-vm.py "$firmware" "$WORK/monitor.sock" qemu-system-x86_64 \
  -machine q35,accel=tcg -cpu max -m 2048 -smp 2 "${args[@]}" -boot c -device qemu-xhci \
  -drive "if=none,id=usb,format=raw,file=$WORK/usb-$firmware.img" -device usb-storage,drive=usb,bootindex=1 \
  -drive "if=none,id=hdd,format=raw,file=$WORK/hdd.img" -device ide-hd,drive=hdd,rotation_rate=7200 \
  -drive "if=none,id=ssd,format=raw,file=$WORK/ssd.img" -device nvme,drive=ssd,serial=QUICK-TEST-NVME \
  -display none -vga std -serial "file:/out/quickscan-$firmware.log" \
  -monitor "unix:$WORK/monitor.sock,server,nowait" -no-reboot -nic none
 offset=$(python3 - "$WORK/usb-$firmware.img" <<'PYOFFSET'
import sys,struct
with open(sys.argv[1],'rb') as f:
 f.seek(486); print(struct.unpack('<I',f.read(4))[0]*512)
PYOFFSET
)
 mkdir -p "/out/quickscan-reports/$firmware"
 mcopy -s -i "$WORK/usb-$firmware.img@@$offset" ::/MacusReports "/out/quickscan-reports/$firmware/"
done
sha256sum -c "$WORK/internal.sha256"
python3 - <<'PY'
import json
from pathlib import Path
for firmware in ['bios','uefi','uefi-repeat','save-failure']:
 reports=list((Path('/out/quickscan-reports')/firmware).rglob('report.json'))
 assert len(reports) == (2 if firmware in ['uefi-repeat','save-failure'] else 1), (firmware, reports)
 for path in reports:
  r=json.loads(path.read_text())
  assert r['quick_scan']['mode']=='unattended'
  assert r['quick_scan_version']=='1.1.0'
  assert r['clock']['status'] in ['unverified', 'suspect']
  assert r['clock']['image_built_at']
  assert r['asset_id'] and r['asset_id']!='VM-BOOT-TEST'
  assert r['gpus'] and r['memory']['modules']
  assert {d['drive_type'] for d in r['storage']}=={'HDD','SSD'}
  assert all(v=='not tested' for v in r['manual_checks'].values())
  assert path.with_name('report.html').exists() and path.with_name('summary.csv').exists()
  print(firmware, r['quick_scan'])
print('PASS: production BIOS/UEFI boot, repeated same-USB reports, save failure stays on, internal test disks untouched.')
PY
