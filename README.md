# Macus

Created by SynapsEdge. A native macOS app for creating bootable USB installers.

Creates Windows installation USBs on macOS 26 and Apple Silicon. See Credits below for the original project and license.

## Downloads

[Download Macus 0.4.0 and Quick Scan 1.1](https://github.com/abrichardson/RufusMac/releases/tag/v0.4.0).

- **Macus-0.4.0-arm64.dmg**: the Mac application for Apple Silicon, macOS 26 or later. Open the DMG and drag Macus into Applications. A ZIP is also available.
- **Macus-QuickScan-USB.img.zip**: separate PC boot image. Extract it and keep the `.img` and `.sha256` together, then select the image in Macus.

The published Mac app is Developer ID signed and Apple-notarized. SHA-256 files verify download integrity; macOS verifies the publisher signature and notarization ticket.

## What works in this fork

- Windows UEFI installers on FAT32, with either GPT or MBR partition tables.
- Large `sources/install.wim` split into `.swm` parts using bundled wimlib.
- Small `install.esd` and existing split `.swm` payloads copied normally.
- Already-mounted ISO detection; mounting errors no longer silently select the Linux writer.
- ISO access and copying run as the logged-in user; only formatting requests administrator privileges.
- Preflight before erase: source layout, FAT32 file limits, required tools, capacity, and fresh physical USB identity checks.
- Verification compares copied files byte-for-byte and checks split WIM integrity.
- Paths containing spaces, quotes, and shell metacharacters are handled as data.
- Standard Windows installation by default. Experimental Windows 11 bypass is opt-in and may not work on all releases.

## Windows account options and progress

The Windows options panel can create a named local administrator, allow setup without a Microsoft account, and decline Express setup settings. These controls are off by default and independent of the hardware bypass. Local accounts start with a blank password and request a password change at the next sign-in, matching Rufus's approach. No password is collected by the Mac app. Validate this behavior in Windows Setup before deploying customized media.

Windows writes display the current stage, live tool output, and elapsed time. See [the official Rufus comparison](docs/RUFUS-COMPARISON.md) for the implementation rationale, remaining features, and test limits.

## Inventory & Diagnostics

Diagnostics boot media is a separate download; the Mac app stays small. Extract
the **USB image ZIP** (keeping the `.img` and `.sha256` together). In the sidebar choose **Inventory & Diagnostics**, select a regular USB of 2 GB or larger,
choose the extracted `.img`, then click **Create Diagnostics USB**. Confirm the drive can be erased and wait
for verification and automatic ejection.

Boot an Intel/AMD PC from that USB. **Quick Scan automatically scans, saves and shuts down** with no clicks. Move it to the next PC, or reconnect the USB to your Mac and click **Import saved reports**. Choose Full Diagnostics from the boot menu for guided/manual checks. A separate 512 MiB partition keeps reports on the
same USB. An existing Ventoy USB can also be used from the expandable option.
Unknown data never becomes a passing result. This is not a Windows compatibility or firmware-enrollment certification.
See [the bootable image guide](docs/DIAGNOSTICS-APPLIANCE.md) for build commands,
storage behavior and test limits.

The earlier folder-based toolkit remains available under **Advanced** for custom
Linux sessions: `swift run macusctl inventory-export /path/to/destination`.

## Build

```sh
brew install wimlib
bash scripts/bundle_wimlib.sh
swift test
bash scripts/build_app.sh
```

Open `dist/Macus.app`. The build bundles wimlib and its library so it does not depend on Homebrew at runtime. It is locally ad-hoc signed, **not Apple notarized**. Building this fork does not provide a Developer ID or eliminate Gatekeeper checks on downloaded distributions.

## Use

1. Select **Single ISO** and your Windows ISO.
2. Select a USB disk, FAT32, and UEFI. GPT is the default.
3. Review the destination and confirm **Erase & Write**. All data on that USB is erased.
4. Wait for copying, verification, and successful eject, then boot the destination PC from the USB.

For a Windows x64 ISO, the target is an Intel/AMD PC. Creating the USB on Apple Silicon does not make the x64 installer bootable on that Mac.

## Limits and validation

- Quick Scan 1.0 was successfully tested on a physical ThinkPad P15 Gen 2i. Quick Scan 1.1 passed BIOS/UEFI virtual boot, repeated-save and save-failure checks, plus 22 Python tests. Its physical multi-model pilot and GPU-memory verification remain pending. Windows installer validation remains separate; these diagnostics results do not certify Windows Setup.
- Tests execute the Windows pipeline using fake disk/mount commands and real temporary file copies. They cover WIM/ESD/SWM copies, GPT/MBR, missing wimlib, oversized ESD rejection, an internal disk appearing at execution time, corruption detection, and subprocess pipe draining.
- Large ESD files and other files over FAT32's limit are rejected **before erase**. ESD conversion is not implemented.
- Multiboot is disabled because upstream references an installer script that is not supplied. Legacy Windows BIOS boot, NTFS writing, and full formatting are not implemented.
- Raw/Linux writing and reclaim are inherited features, not the focus of this validation.
- Disk name, size, bus, and identifier checks reduce mistakes but are not a unique hardware serial-number binding. Keep the selected USB connected throughout the operation.

Read-only diagnostics:

```sh
swift run macusctl inspect /path/to/Windows.iso
swift run macusctl list
swift run macusctl preview windows /path/to/Windows.iso
```

## Credits

Original RufusMac: Harith Dilshan / h4rithd.com. wimlib: Eric Biggers and contributors, https://wimlib.net/. See `LICENSE` and the licenses bundled with wimlib.

### Dedicated Diagnostics USB

Select the separate `.img` in **Inventory & Diagnostics → Choose diagnostics image**,
then click **Create Diagnostics USB** to prepare a regular
USB of 2 GB or larger. The selected drive is erased, verified and ejected. Boot
a PC from it; Quick Scan saves and shuts down automatically. Reconnect it to your Mac and
click **Import saved reports**. Ventoy is optional. The dedicated layout includes
512 MiB for reports; remaining USB capacity is unused. See
[the diagnostics guide](docs/DIAGNOSTICS-APPLIANCE.md) for build and test details.

Reports now include GPU model/driver, firmware-reported RAM type, module sizes and
speeds, and each internal drive’s model, capacity, HDD/SSD type, interface and health.
Unknown fields remain unknown; detection does not certify functionality.

Quick Scan 1.1 adds readable capacities, friendly model names, scan timing, NVMe wear/error details, driver-reported GPU memory where available, and explicit clock warnings. See [the Quick Scan guide](docs/QUICK-SCAN.md). Back up existing reports before rewriting a USB.

## Signed release builds

Local builds default to ad-hoc signing. For distribution, set `MACUS_SIGN_IDENTITY`
to your Developer ID Application identity and `MACUS_NOTARY_PROFILE` to a
`notarytool` Keychain profile. Then run:

```sh
bash scripts/build_app.sh
bash scripts/notarize_app.sh
```

The notarization script verifies Apple's acceptance, staples tickets to the app
and DMG, and checks Gatekeeper. Create the release ZIP and checksum manifest only
after stapling. Credentials and private keys must stay outside the repository.
