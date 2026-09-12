#!/bin/bash
# Run in the diagnostics test/build container. No physical disks are accessed.
set -euo pipefail
ISO=${1:-/out/Macus-Diagnostics-amd64.iso}
OUTPUT=${2:-/out/Macus-Diagnostics-USB.img}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Reuse ISOLINUX's hybrid boot code, without the ISO's overlapping GPT/APM.
truncate -s 32768 "$WORK/mbr.bin"
dd if="$ISO" of="$WORK/mbr.bin" bs=1 count=432 conv=notrunc status=none
xorriso -osirrox on -indev "$ISO" -extract /boot/grub/efi.img "$WORK/efi.img" >/dev/null 2>&1
truncate -s 512M "$WORK/reports.img"
mkfs.vfat -F 32 -n MACUSREPORT "$WORK/reports.img" >/dev/null
printf '%s\n' '{"schema_version":1,"purpose":"macus-diagnostics"}' > "$WORK/marker.json"
mcopy -i "$WORK/reports.img" "$WORK/marker.json" ::/.macus-diagnostics.json
mmd -i "$WORK/reports.img" ::/MacusReports
xorriso -indev "$ISO" -outdev "$WORK/usb.img" \
  -boot_image any discard \
  -boot_image isolinux system_area="$WORK/mbr.bin" \
  -boot_image isolinux bin_path=/isolinux/isolinux.bin \
  -boot_image isolinux cat_path=/isolinux/boot.cat \
  -boot_image isolinux boot_info_table=on \
  -boot_image isolinux load_size=2048 \
  -boot_image any partition_offset=16 \
  -boot_image any next \
  -boot_image any efi_path=/boot/grub/efi.img \
  -append_partition 2 0xef "$WORK/efi.img" \
  -append_partition 3 0x0c "$WORK/reports.img" >/dev/null 2>&1
mv "$WORK/usb.img" "$OUTPUT"
# Whole MiB length permits exact read-back verification without short-read pipes.
python3 - "$OUTPUT" <<'PY'
import os, struct, sys
p = sys.argv[1]
with open(p, 'r+b') as f:
    f.truncate((os.path.getsize(p) + 1048575) // 1048576 * 1048576)
    f.seek(0)
    header = f.read(32768)
    assert header[510:512] == b'\x55\xaa'
    assert header[512:520] != b'EFI PART', 'Unexpected overlapping GPT'
    previous_end = 0
    for index, expected_type in enumerate([0x17, 0xef, 0x0c]):
        entry = header[446 + 16 * index:462 + 16 * index]
        start, count = struct.unpack_from('<II', entry, 8)
        assert entry[4] == expected_type and count > 0
        assert start >= previous_end, 'Overlapping USB partitions'
        previous_end = start + count
    assert previous_end * 512 <= os.path.getsize(p)

PY
(cd "$(dirname "$OUTPUT")" && sha256sum "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")
xorriso -indev "$OUTPUT" -report_system_area plain 2>&1
