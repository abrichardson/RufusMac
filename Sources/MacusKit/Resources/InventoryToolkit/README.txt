MACUS INVENTORY & DIAGNOSTICS — 1.0

For PCs booted into a Linux live desktop. This folder is a toolkit, not an ISO.

PREPARE ON YOUR MAC
1. Prepare the USB with Ventoy (Ventoy installation is a separate operation).
2. Copy an official Ubuntu Desktop x64 ISO to the Ventoy data partition.
   https://ubuntu.com/download/desktop
3. Use Macus > Inventory & Diagnostics > Export toolkit. Select the same data
   partition. Keep this entire folder together. Existing ISOs are preserved.
   Alternatively export locally and copy the resulting folder to that partition.

RUN ON A PC
1. Boot the USB, select Ubuntu, and choose Try Ubuntu (not Install).
2. In the live desktop's file manager, open the Ventoy data partition and this
   folder. Right-click empty space > Open in Terminal.
3. Run: bash Start.sh
   Enter an optional asset ID. Collection works offline with Python 3.
4. Follow guided checks. Press Enter to leave an untested check as not tested.
5. Reports are saved in this folder's Reports directory: HTML, JSON and CSV.
   Shut down the live session before removing the USB.

If Ventoy's data partition is not visible or is read-only in that live session,
use a second writable USB, open it in the file manager, and select it explicitly:
  bash Start.sh --output "/media/ubuntu/YOUR_USB/Reports"
The toolkit refuses an unverified non-USB destination by default. It does not
mount internal disks or change partition layouts. --allow-local-output is an
explicit override for intentional local/VM testing, not needed for normal use.
The live desktop itself can mount disks if you open them: leave internal disks
alone. This tool cannot guarantee that the host live OS makes no writes.

OPTIONAL TOOLS
The toolkit records unknown/unavailable if a command is absent. To get SMART,
RAM module details and optional stress/memory tests in Ubuntu's live session,
connect to the Internet and run:
  sudo apt update
  sudo apt install smartmontools dmidecode pciutils usbutils stress-ng memtester
Installing tools changes the live session, not an installed OS. Some packages
may require Ubuntu's universe repository. An offline live image must include
these tools in advance for full coverage. Macus does not download them silently.

QUICK COLLECTION
  bash Start.sh --quick --asset-id PC-001

WHAT IS COLLECTED
Manufacturer/model/serial, CPU, usable RAM, raw DIMM information when available,
non-USB disks and SMART health, batteries and capacity ratios, connected display
modes, PCI/USB devices, network adapters, temperature sensors, UEFI/Secure Boot,
and TPM version when exposed. There are no automatic Windows compatibility,
license, BIOS password, Absolute/Computrace or Autopilot conclusions.

DIAGNOSTIC SCOPE
Guided checks cover screen, keyboard, pointer, ports, audio, camera, network,
charging and firmware restrictions. Optional tests: CPU verification for 60
seconds and one 256 MiB RAM pass. These are limited checks, not a full burn-in
or a full-memory test. Missing tools, permissions, timeouts or unavailable data
never mean pass. SMART passed is only the drive's reported health status.
No disk write benchmark, erase, firmware update or repair is performed.

REPORTS
Each run creates a unique folder; repeating an asset ID does not overwrite a
prior result. HTML is self-contained and works offline. CSV text cells are
protected against spreadsheet formulas. JSON preserves structured/raw data.
Reports contain device serials and technician notes; share intentionally.
Use Macus's Load reports button to review a batch and export one combined CSV.

Sources:
https://ubuntu.com/desktop/docs/en/latest/tutorial/try-ubuntu-desktop/
https://www.ventoy.net/en/doc_disk_layout.html
