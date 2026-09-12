# Quick Scan boot image

A separate appliance; no Macus app changes are required.

1. Extract `Macus-QuickScan-USB.img.zip`, keeping the image and its SHA-256 file together.
2. In existing Macus 0.4, choose the `.img` under Inventory & Diagnostics and create the USB.
   This erases the selected USB, so import any existing reports first.
3. Boot an Intel/AMD PC from the USB. The default Quick Scan collects inventory and basic
   health data, saves HTML/JSON/CSV to `MacusReports` on that same USB, and powers off.
4. Move the USB to the next PC. Reconnect it to the Mac to import the accumulated reports.

The serial number identifies each scan, with a unique fallback when unavailable.
Every run gets its own directory. No manual checks or stress tests run automatically.
GPU/RAM/storage details use the existing full collector, with individual probes limited
 to 8 seconds and an overall external-probe budget of 45 seconds. Timeouts remain unknown.
Boot time and USB writes are additional; approximately 1–2 minutes is a target, not a
hardware-independent guarantee. Full Diagnostics is available from the two-second boot menu.

Quick Scan verifies the reports destination belongs to the physical USB that holds the live
boot filesystem. It does not select another plugged-in report USB. If saving fails or the
boot USB cannot be identified, it leaves the PC on with an error; it attempts to preserve
collected results temporarily under `/run/macus-quickscan` in RAM. That recovery copy is lost
on shutdown. Only a successful USB save triggers automatic shutdown.

## Build / test

Use the full Diagnostics 1.1.0 ISO as `/base/Macus-Diagnostics-amd64.iso` in the existing
`macus-diagnostics-test:bookworm` container, mount the repository read-only at `/src`, and
mount an output directory at `/out`. Run:

```
bash /src/scripts/diagnostics/build-quickscan.sh
bash /src/scripts/diagnostics/test-quickscan.sh
```

The test boots the unmodified production USB image on BIOS and UEFI, without injected
self-test flags or GUI interactions. It checks saved hardware reports, automatic poweroff,
and unchanged internal virtual HDD/SSD contents. Secure Boot and real-PC timing require
hardware testing. The ISO is a build intermediate; distribute the USB image for the
same-drive unattended workflow.

## Quick Scan 1.1.0

Quick Scan has an independent version (`quick_scan_version`) and enhancements module;
Macus app sources and its package are unchanged. Reports prominently show firmware model
name, human-readable capacities, scan timing, and NVMe wear/error counters. CSV keeps
existing byte columns for import compatibility. Unsupported drive counters stay unknown.

The clock status is unverified unless systemd's current-boot synchronization marker exists.
A timestamp earlier than the embedded UTC image build timestamp is suspect. No network
wait or firmware-clock adjustment is performed. UUID-based report folders prevent duplicate
or incorrect PC dates from overwriting scans.

Nouveau VRAM is matched by exact PCI address from its kernel log and labelled as driver-
reported available memory; sysfs remains preferred. No memory size is inferred from a
GPU name or PCI aperture. Reference: Linux nouveau_ttm.c and the Nouveau KMS documentation:
https://nouveau.freedesktop.org/KernelModeSetting.html

Validation covers BIOS/UEFI, repeated scans on the same virtual USB, and a missing report
marker that must leave the machine on. Unit tests cover a full-disk write error without
publishing a partial report. A physical pilot across different PC models remains necessary;
virtual tests cannot validate every GPU/firmware implementation or Secure Boot.
