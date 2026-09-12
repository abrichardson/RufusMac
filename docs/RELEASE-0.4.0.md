Macus 0.4.0 keeps the Mac application small and distributes PC diagnostics separately. Quick Scan 1.1 boots from a regular USB, collects inventory and basic health data, saves reports to that same USB, and shuts down automatically.

## Downloads

- **Macus-0.4.0-arm64.dmg** — Mac installer: open it and drag Macus into Applications. Requires Apple Silicon and macOS 26 or later.
- **Macus-0.4.0-arm64.zip** — the same Mac application as a ZIP.
- **Macus-QuickScan-USB.img.zip** — separate Intel/AMD PC boot image. Extract it, keep the `.img` and `.sha256` together, and select the image in Macus under Inventory & Diagnostics.
- **SHA256SUMS.txt** — checksums for these downloads. The boot-image ZIP also contains a checksum for the extracted image.

Back up existing reports before recreating a USB; writing an image erases the selected drive. Use a regular USB of 2 GB or larger. Ventoy is optional, not required. Reports accumulate under `MacusReports`; reconnect the USB to the Mac to import them. Full Diagnostics remains available from the boot menu.

## Changes

- Select a separate diagnostics image instead of bundling hundreds of megabytes inside the Mac app.
- Native authorized USB writing, fresh destination checks, checksum verification and automatic ejection.
- CPU/GPU inventory, RAM type/modules/speed, HDD/SSD capacity/interface, SMART and battery readings.
- Quick Scan 1.1: clearer model names and capacities, scan timing, NVMe wear/error counters, driver-reported GPU memory where available, and explicit warnings for unverified or suspect PC clocks.
- Failed saves leave the PC on with an error; successful repeated scans preserve previous reports.

## Validation and limits

32 Swift and 22 Python tests pass. The published Quick Scan image passed BIOS/UEFI virtual boots, repeated saves on the same USB, and save-failure handling. Internal virtual HDD/SSD contents remained unchanged. DMG integrity, application signature and download checksums were verified locally.

Quick Scan 1.0 was tested on a physical ThinkPad P15 Gen 2i. The 1.1 update still needs a small physical pilot across different PCs, including GPU-memory verification. Secure Boot compatibility is not verified. Hardware detection and basic SMART readings are not stress tests or a complete hardware certification; unknown data stays unknown. Windows installer testing is separate from diagnostics validation.

The Mac application is **ad-hoc signed, not Apple-notarized**. Downloaded copies may require explicit approval in macOS Privacy & Security. Checksums verify integrity, not publisher identity. No Windows or other proprietary OS installer is included.
