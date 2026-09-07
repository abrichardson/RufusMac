# Official Rufus comparison — 2026-09-07

Reviewed [Rufus 4.15 release notes](https://github.com/pbatard/rufus/releases/tag/v4.15), its [Windows User Experience implementation](https://github.com/pbatard/rufus/blob/master/src/wue.c), and the [official FAQ](https://github.com/pbatard/rufus/wiki/FAQ). This macOS project is an independent fork of RufusMac, not an official Rufus port.

## Implemented in this update

- Separate local-account creation and Microsoft-account bypass from hardware bypass.
- Create a named local administrator with an initially blank password, then request a password change at the next sign-in, following Rufus's approach. Do not collect passwords in this app or set persistent auto-login.
- Validate names before erasing; reject reserved names and unsupported characters rather than silently changing them. XML-escape generated values.
- Write account settings to `sources/$OEM$/$$/Panther/unattend.xml`, used by Windows Setup for later configuration passes. If hardware bypass is selected, the root answer file also includes those settings.
- Generate x64/ARM64 component names from the image's EFI bootloader, not the Mac CPU.
- Add optional `ProtectYourPC=3`. Microsoft's [documentation](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc) calls this disabling Express settings; it is not a promise to disable all telemetry. Leave the license page visible.
- Stream stage names, copy/split output, and elapsed time.

## Priorities for subsequent work

| Priority | Feature or fix | Reason / scope |
| --- | --- | --- |
| 1 | Physical Windows 11 25H2 boot and OOBE tests | Verify account creation, password-change behavior, network-connected/disconnected setup, and hardware-bypass combinations. XML tests cannot establish Windows behavior. |
| 1 | Safe cancellation and reliable error logs | Rufus 4.15 improves cancellation during retries and progress reporting. Our cancellation must stop the entire process tree and finish cleanup without reporting success. |
| 1 | Secure Boot certificate/revocation compatibility | The Rufus FAQ distinguishes old and new signing certificates; a writable, verified USB is not necessarily accepted by every firmware configuration. |
| 2 | Regional settings | Map macOS locale/timezone to Windows values; do not write IANA timezone IDs as Windows timezone names. |
| 2 | Optional automatic device-encryption control | Rufus offers this; keep it explicit and off by default, explaining that encryption can be configured later. |
| 2 | Large ESD conversion | Current fork rejects oversized ESD before erase. Add conversion with workspace/capacity checks. |
| 3 | UEFI:NTFS, legacy BIOS, bad-block tests | Substantial bootloader/filesystem work, not checkboxes. FAT32 + split WIM remains the supported Windows path. |
| Defer | Silent install, Windows To Go, broad app removal | Silent-install mistakes can erase the destination PC. These need a separate design and hardware validation. |

Rufus 4.15 also fixes XML-parser security issues and username handling. We generate XML rather than importing arbitrary answer files; any future answer-file import must prohibit external entities and impose size/depth limits.

## Limits

The Microsoft-account bypass alone may require an offline network; Windows S mode is incompatible with that bypass. A Windows installation test is still required. The running USB operation uses the previous build and cannot acquire these new account options midway through a write.

The original code and GPLv3 copyright notices remain in place. This implementation was informed by Rufus behavior and Microsoft's [LocalAccount schema](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts-localaccount), with new Swift code and tests.
