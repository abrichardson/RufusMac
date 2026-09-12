# Inventory & Diagnostics — standalone collector

For the simpler bootable graphical appliance, see [DIAGNOSTICS-APPLIANCE.md](DIAGNOSTICS-APPLIANCE.md). The notes below describe the advanced folder-based collector.

The Mac app exports a versioned folder containing a Python standard-library
collector, shell launcher, run guide and empty Reports folder. The public
`InventoryToolkit.export(to:)` API accepts a mounted destination folder so a
future Ventoy workflow can call it after preparing the data partition. It does
not alter Ventoy configuration, install a bootloader, or erase media.

Use an official Ubuntu Desktop x64 live image for ordinary Intel/AMD PCs. Boot
through Ventoy, choose Try Ubuntu, then run `bash Start.sh` from the toolkit
folder. Python 3 is required. smartmontools/dmidecode/pciutils/usbutils and
stress-ng/memtester improve coverage; they are optional and are not bundled.
This release needs no server, account, Internet connection or Python packages
for basic collection. Offline full diagnostics require those OS tools already
in the live image. Manufacturer-specific plugins are not implemented yet.

## Data and diagnostics

Version 1 JSON preserves structured system/battery/storage data and bounded raw
command results, with collection timestamps, asset IDs and independent report
IDs. No credentials, Windows keys or user files are collected. It does collect
serial numbers, network interface details and technician notes.

SMART's exit bitmask distinguishes collection failures from reported health
problems. Unavailable data never becomes a pass. Battery ratios use matching
energy or charge units, never a mixture. Usable RAM differs from installed RAM;
raw DIMM data is included when dmidecode is available. Display modes are
advertised, not guaranteed native resolution. TPM and Secure Boot observations
do not imply Windows 11 eligibility. BIOS passwords and organization enrollment
stay unknown pending separate checks.

Guided checks are technician attestations. CPU verification is limited to 60
seconds and at most four workers. RAM testing covers 256 MiB for one pass, with a
768 MiB available-memory preflight. Neither is a comprehensive certification.
Timeouts and missing executables are unknown/unavailable, never successful.

The collector never mounts, formats, repairs or benchmarks writes to internal
drives. USB disks are excluded from SMART inventory to omit boot/report media.
Report paths must resolve to USB-backed storage using findmnt/lsblk ancestry,
unless the operator explicitly opts into local output for e.g. VM testing.
The host live desktop's own disk behavior is outside this guarantee. A separate
writable USB can hold reports if the live session cannot write the Ventoy data
partition. No automatic mount/remount is attempted.

Each completed report is published in its own unique directory. Interrupted or
failed saves do not publish partial bundles. HTML escapes data; CSV exports
neutralize formula-leading cells. JSON keeps original data. Macus imports only
immediate report directories, skips symbolic links and oversized/invalid files,
and reports skipped files. The batch CSV includes all scans, not just the latest
scan for each serial. This preserves retest history explicitly.

## Validation

- Swift tests cover export, preservation of existing files, import and CSV safety.
- Python tests cover SMART masks, incomplete batteries, missing tools, USB output
  checks, filtering of boot media, safe serialization and failed/duplicate saves.
- A Linux container smoke test exercises real collection and report creation with
  no network and no host hardware devices exposed.
- Packaged app UI verified: toolkit screen, Linux report import, and enabled CSV export.
- A real PC live-boot and USB persistence test remains required. Container results
  cannot validate actual batteries, firmware, SATA/NVMe health or stress tests.

Commands:

```sh
swift test
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/InventoryToolkitTests -v
bash scripts/build_app.sh
```

Sources for the supported workflow:
- https://www.ventoy.net/en/doc_disk_layout.html
- https://ubuntu.com/desktop/docs/en/latest/tutorial/try-ubuntu-desktop/
