# RufusMac — Windows installer fixes

A fork of [h4rithd/RufusMac](https://github.com/h4rithd/RufusMac), focused on creating Windows installation USBs on macOS 26 and Apple Silicon. Original app by Harith Dilshan; GPLv3 license retained. This is not the official Rufus project.

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

## Build

```sh
brew install wimlib
bash scripts/bundle_wimlib.sh
swift test
bash scripts/build_app.sh
```

Open `dist/RufusMac.app`. The build bundles wimlib and its library so it does not depend on Homebrew at runtime. It is locally ad-hoc signed, **not Apple notarized**. Building this fork does not provide a Developer ID or eliminate Gatekeeper checks on downloaded distributions.

## Use

1. Select **Single ISO** and your Windows ISO.
2. Select a USB disk, FAT32, and UEFI. GPT is the default.
3. Review the destination and confirm **Erase & Write**. All data on that USB is erased.
4. Wait for copying, verification, and successful eject, then boot the destination PC from the USB.

For a Windows x64 ISO, the target is an Intel/AMD PC. Creating the USB on Apple Silicon does not make the x64 installer bootable on that Mac.

## Limits and validation

- No physical USB write or PC boot test has been performed for this fork yet.
- Tests execute the Windows pipeline using fake disk/mount commands and real temporary file copies. They cover WIM/ESD/SWM copies, GPT/MBR, missing wimlib, oversized ESD rejection, an internal disk appearing at execution time, corruption detection, and subprocess pipe draining.
- Large ESD files and other files over FAT32's limit are rejected **before erase**. ESD conversion is not implemented.
- Multiboot is disabled because upstream references an installer script that is not supplied. Legacy Windows BIOS boot, NTFS writing, and full formatting are not implemented.
- Raw/Linux writing and reclaim are inherited features, not the focus of this validation.
- Disk name, size, bus, and identifier checks reduce mistakes but are not a unique hardware serial-number binding. Keep the selected USB connected throughout the operation.

Read-only diagnostics:

```sh
swift run rmctl inspect /path/to/Windows.iso
swift run rmctl list
swift run rmctl preview windows /path/to/Windows.iso
```

## Credits

Original RufusMac: Harith Dilshan / h4rithd.com. wimlib: Eric Biggers and contributors, https://wimlib.net/. See `LICENSE` and the licenses bundled with wimlib.
