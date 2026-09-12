# Macus Diagnostics bootable image

## Normal use

1. Download and extract the separate diagnostics USB image ZIP. Keep its `.img` and `.sha256` files together. In Macus, open Inventory & Diagnostics, click **Choose diagnostics image**, select the `.img`, and select a regular USB (2 GB or larger).
2. Click **Create Diagnostics USB**, confirm the selected drive can be erased, and approve the macOS administrator prompt. Wait for verification and automatic ejection.
3. Boot an Intel/AMD PC from the USB. Diagnostics starts automatically.
4. The graphical app scans automatically. Optionally enter an asset ID, record
   checks or run extra tests. Click **Save & Shut Down**.
5. Reconnect the USB to the Mac. Macus detects it and offers **Import saved reports**.

The image includes Python/Tk, smartmontools, dmidecode, PCI/USB utilities,
stress-ng and memtester. Built-in screen colors, keyboard input and speaker
checks support the guided inspection. No terminal, package downloads or account is needed.
It uses a Debian Bookworm live filesystem with Xorg/Openbox. Optional tests
remain limited (60-second CPU check and one 256 MiB memory pass).

The dedicated USB uses an MBR layout with BIOS boot support, an EFI boot partition,
and a separate 512 MiB FAT32 `MACUSREPORT` partition. Remaining drive capacity is
unused. The writer opens the USB through Apple’s `authopen` authorization service, then
writes and verifies it in the Macus process. It checks authorization before changing
any bytes, replaces the front partition map and clears the last MiB to remove stale
backup maps. It compares the SHA-256 of the written image and verifies the cleared
tail before ejecting. Device identity and opened-device capacity are checked after
authorization and before writing. No AppleScript administrator process writes raw
disk bytes. Creating it erases all existing
USB contents. Reclaim in Macus can later restore the full capacity as a normal drive.

The optional **Already have a Ventoy USB?** Add action requires a mounted data partition on an existing Ventoy USB.
It does not install Ventoy. It copies a checksummed ISO, creates `MacusReports`
and a small marker file, and preserves other images and all existing reports.
A different ISO at the reserved filename is not overwritten automatically.

## Report storage

Only USB-backed FAT/exFAT/NTFS filesystems with the Macus marker are eligible.
Unmarked USB partitions may be inspected read-only; internal drives are never
mounted by the report finder. Matching Ventoy mapped devices are considered via
USB ancestry, avoiding fixed disk names. Newly mounted eligible volumes use
nosuid/nodev/noexec. No executable is loaded from the report volume.

With one marked writable USB, the destination is automatic. Multiple marked
USBs require selection. With none available, results stay in memory and saving
is disabled; insert a prepared USB and click Find USB. Saving rechecks the
marker and USB ancestry, and errors prevent shutdown. Reports are synced before
poweroff; remove media only after the PC has powered off.

The app does not certify Windows eligibility, enrollment status, or firmware
password state. Unknown readings are not passed tests. Firmware support and
Secure Boot behavior need real-PC testing. ARM PCs and Macs are not targets for
this amd64 image. Ventoy versions vary in how their data partition is exposed;
use a current Ventoy version with its Linux remount support.

## Build and validation

```sh
bash scripts/build_diagnostics_iso.sh
docker build -f diagnostics/Test.Dockerfile -t macus-diagnostics-test:bookworm diagnostics
docker run --rm -v "$PWD:/src:ro" -v "$PWD/dist/diagnostics:/out" macus-diagnostics-test:bookworm bash /src/scripts/diagnostics/make-usb-image.sh
bash scripts/test_diagnostics_iso.sh
bash scripts/package_diagnostics.sh
# Macus never bundles the images. Its build does not require the Linux build.
bash scripts/build_app.sh
```

The builder runs in an amd64 Debian Docker container. On Apple Silicon it uses
emulation. Linux mount privileges are needed inside the Docker VM; no host block
devices are passed through. Sources are mounted read-only, with only the build
output directory writable. The build is versioned by distribution/package list
and SHA-256, but is not bit-for-bit reproducible against moving Debian mirrors.
`packages.txt` records the installed package versions; Debian license notices
remain inside the live filesystem under `/usr/share/doc`.

BIOS and UEFI QEMU boot regressions passed with 2 GiB of guest RAM and a
disposable FAT USB image. Dedicated USB boot is also tested with no CD attached,
using the complete MBR image and saving to its own reports partition. Secure Boot was not tested. A kernel command
line test flag exercises the same graphical application, automatically saves a
scan, powers down, and verifies the report survives in the virtual USB image.
The test flag is injected into a temporary copy of the ISO boot menus and is
not enabled in normal boot entries. Real hardware must still verify
actual battery/SMART readings, firmware boot, display/input, and Ventoy storage.

References:
- https://live-team.pages.debian.net/live-manual/html/live-manual.en.html
- https://www.ventoy.net/en/doc_linux_remount.html

## macOS permission errors

Version 0.3.1 used an AppleScript administrator shell for raw writes. On the test
Mac, TCC attributed the operation to `authtrampoline`, so the administrator password
did not provide removable-volume access. It could format the USB and then fail with
`dd: Operation not permitted`. Version 0.3.2 replaces that path with `authopen` and
native descriptor-based I/O; authorization failure occurs before any data is written.
Allow the macOS disk-authorization and removable-volume prompts. If removable
access was previously denied, check System Settings → Privacy & Security → Files
and Folders → Macus. Changing privacy permissions remains an explicit user action.

## Expanded hardware inventory (toolkit 1.1.0)

The live screen, HTML, JSON and CSV expose GPU vendor/model/driver, reported VRAM
when the driver exposes it, installed RAM and firmware-reported memory modules
(type, form factor, rated/configured speed, manufacturer, part and serial numbers).
Each internal disk includes decimal capacity in GB, HDD/SSD classification from the
kernel rotation flag, interface, model, serial and SMART health. USB disks are excluded.
PCI network adapter models and BIOS versions are also visible in the live report.

DMI is firmware-reported data; empty records are not proof of user-accessible slots.
Unknown module sizes or types stay unknown. GPU PCI aperture size is never treated
as VRAM. These fields describe detected hardware, not a pass/fail functional test.
The separate image's adjacent SHA-256 checks transfer integrity, not publisher identity;
use diagnostics images from a trusted source. Images are not copied into Macus.
