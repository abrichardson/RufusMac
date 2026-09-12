# Changelog

## Quick Scan 1.1.0 — 2026-09-12

- Separate unattended boot image: boot, scan, save to the same USB and shut down. Full Diagnostics remains available from the boot menu.
- Highlight friendly model names, readable capacities, scan timing and NVMe wear/error counters.
- Detect Nouveau driver-reported VRAM by PCI address; unavailable memory remains unknown.
- Mark unverified PC clocks and flag dates earlier than the image build timestamp.
- Verify repeated saves preserve reports, and failed saves leave the PC on.
- Keep Macus at 0.4.0; boot image updates do not enlarge the application.

## 0.4.0

- Privacy rebuild: neutral build paths, stripped debug data, an explicit resource list, and a packaging check for personal build paths.

- Keep diagnostics media outside Macus. Select a separately downloaded USB image or ISO with its matching SHA-256 file; remember the selection between launches.
- Report GPU model/driver, RAM type/module capacity/speed/part numbers, and drive model/capacity/HDD-or-SSD/interface in the live app, HTML/JSON/CSV and Mac report viewer.
- Build and distribute the Mac app independently from diagnostics images.


## 0.3.2

- Replace the diagnostics AppleScript raw writer with Apple's authopen service and native file-descriptor I/O, preserving the app's removable-volume permission context.
- Check authorization before changing disk contents, verify device capacity, and verify both the written image and backup partition-map cleanup.
- Add the macOS removable-volume usage description and actionable authorization errors.


## 0.3.1

- Create Diagnostics USB from a regular USB, with direct BIOS/UEFI boot and 512 MiB of report storage.
- Confirm the target before erase, recheck it after authorization, verify written bytes, and eject automatically.
- Keep the existing Ventoy option under an expandable section.

All notable changes to RufusMac are documented here.
This project adheres to [Semantic Versioning](https://semver.org).

## [0.3.0] — 2026-09-10

- Added the offline Macus Diagnostics bootable image and graphical PC interface.
- Added verified image installation to existing Ventoy data partitions, automatic
  report-storage discovery, report import and combined CSV export.
- Included generic hardware inventory, SMART/battery readings, guided checks,
  screen/keyboard/speaker tools, and optional CPU/limited-memory tests.
- Added BIOS and UEFI virtual boot tests covering automatic scan, USB report
  persistence and shutdown. Physical Ventoy/PC testing remains required.

## [0.1.0] — 2026-06-15

First functional preview. Built with the help of Claude Code.

### Added
- **Liquid Glass UI** — native SwiftUI for macOS 26 (Tahoe): mode switcher, device picker, drag-and-drop boot selection, contextual options, confirmation sheet, and persistent footer.
- **Safe device detection** — `DiskService` lists only external/physical/removable disks; internal disks are never shown (covered by unit tests).
- **Writer engines** — `BurnPlanner` generates auditable command pipelines for:
  - **Single ISO / DD** — raw `dd` write for Linux and hybrid images, with optional SHA-256 verify.
  - **Windows** — FAT32 + file copy, automatic `install.wim` → `.swm` split, and a **Windows 11 bypass** (TPM / Secure Boot / RAM / CPU + local-account `BypassNRO`).
  - **Reclaim** — restore a USB to a normal, usable volume.
  - **Multiboot (experimental)** — Ventoy-style layout, plus optional Linux persistence.
- **Dry-run "Preview only"** mode and a full command preview before any destructive action.
- **ISO catalog** — curated, browsable list of popular distributions and Windows.
- **Checksum service** — SHA-256/512 verification.
- **`rmctl` CLI** — `list`, `preview`, `catalog`, `verify`.
- **Packaging** — `build_app.sh`, `make_dmg.sh` (portable `.dmg` + checksum), `make_icon.sh`, `fetch_thirdparty.sh`, `scrub_secrets.sh`.

### Known limitations
- Windows and Multiboot modes require the bundled third-party tools (`scripts/fetch_thirdparty.sh`).
- Multiboot and persistence are experimental and need real-hardware validation.
- The app is unsigned (right-click → Open on first launch).
- Real-time write progress and the in-app downloader are planned.
