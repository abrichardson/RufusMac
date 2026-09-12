#!/usr/bin/env python3
"""Unattended quick inventory: bounded probes, same-USB reports, power off on success."""
import json
from pathlib import Path
import time
import inventory
import storage
import enhancements
enhancements.install(inventory)


def announce(message):
    print(message, flush=True)
    try:
        with open('/dev/ttyS0', 'w') as stream:
            stream.write(message + '\n')
    except OSError:
        pass


def usb_disks(path):
    mount = inventory.decoded(inventory.run(['findmnt', '--json', '--target', str(path), '--output', 'SOURCE']))
    rows = mount.get('filesystems', [])
    if not rows:
        return set()
    source = rows[0].get('source', '').split('[')[0]
    if not source.startswith('/dev/'):
        return set()
    tree = inventory.decoded(inventory.run(['lsblk', '--json', '--paths', '--tree', '--inverse', '--output', 'PATH,TYPE,TRAN', source]))
    return {d['path'] for d in inventory.flatten(tree.get('blockdevices', []))
            if d.get('type') == 'disk' and d.get('tran') == 'usb' and d.get('path')}


def destination():
    boot = usb_disks('/run/live/medium')
    if len(boot) != 1:
        raise OSError('Cannot identify the boot USB. Use the Quick Scan USB image, not a CD/DVD.')
    matches = [p for p in storage.find_storage() if usb_disks(p) == boot]
    if len(matches) != 1:
        raise OSError('No unique writable reports partition on the boot USB. Recreate the Quick Scan USB.')
    return matches[0]


def collect_quick(budget=45):
    start = time.monotonic()
    normal_run = inventory.run
    skipped = []
    def bounded(args, timeout=20):
        remaining = budget - (time.monotonic() - start)
        if remaining <= 0:
            skipped.append(args[0])
            return {'status': 'unknown', 'reason': 'Quick Scan time budget exhausted'}
        return normal_run(args, timeout=min(timeout, 8, remaining))
    inventory.run = bounded
    try:
        report = inventory.collect()
        enhancements.enrich(report, inventory)
    finally:
        inventory.run = normal_run
    serial = inventory.known(report['system'].get('serial'))
    if serial and serial.lower() not in {'0', 'default string', 'system serial number'}:
        report['asset_id'] = serial[:80]
    else:
        report['asset_id'] = 'PC-' + report['report_id'][:12]
    report['quick_scan'] = {'mode': 'unattended', 'collection_seconds': round(time.monotonic() - start, 2),
                            'probe_budget_seconds': budget, 'skipped_commands': sorted(set(skipped))}
    report['notes'] = 'Automatic Quick Scan. Manual checks and CPU/RAM stress tests were not performed.'
    report['limitations'].append('Quick Scan limits each probe to 8 seconds and external probes to a 45-second total budget; timeouts remain unknown.')
    return report


def main():
    announce('MACUS QUICK SCAN — automatic inventory and health checks')
    announce('Scanning CPU, GPU, RAM, drives and battery. No input is needed.')
    report = None
    try:
        report = collect_quick()
        announce('Scan complete. Saving to the boot USB…')
        output = destination()
        # Revalidate after discovery and immediately before publishing the report.
        boot = usb_disks('/run/live/medium')
        if len(boot) != 1 or usb_disks(output) != boot or not storage.marked(output.parent):
            raise OSError('Boot USB changed before saving.')
        uptime = (inventory.read('/proc/uptime') or '').split()
        report['quick_scan']['boot_elapsed_at_save_seconds'] = inventory.number(uptime[0]) if uptime else None
        saved = inventory.save(report, output)
        announce('QUICKSCAN_SAVED: ' + str(saved))
        announce('Reports saved successfully. Shutting down; remove the USB after power is off.')
        time.sleep(3)
        result = inventory.run(['systemctl', 'poweroff'], timeout=10)
        if result.get('exit_code') != 0:
            raise OSError('Report is saved, but automatic shutdown failed. Shut down using the power button.')
        return 0
    except Exception as error:
        announce('QUICKSCAN_ERROR: ' + str(error))
        if report:
            try:
                saved = inventory.save(report, Path('/run/macus-quickscan'))
                announce('Temporary recovery copy in RAM: ' + str(saved))
            except Exception:
                pass
        announce('The PC will stay on. Do not assume a report was saved to USB unless success is shown.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
