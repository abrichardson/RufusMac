#!/usr/bin/env python3
"""Macus Inventory & Diagnostics. Python 3 standard library; Linux live sessions."""
import argparse
import csv
import datetime as dt
import html
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

VERSION = '1.1.0'
CHECKS = {
    'display': 'Inspect solid colors, dead pixels, backlight, touch (if fitted).',
    'keyboard': 'Type every key in a text editor; check modifiers and backlight.',
    'pointer': 'Check touchpad, buttons, pointing stick and gestures if fitted.',
    'ports': 'Connect a known-good device to EACH USB/video/audio port.',
    'audio': 'Play audio and record/play back the microphone in the live desktop.',
    'camera': 'Open a camera application and check its image.',
    'network': 'Connect Wi-Fi/Ethernet and load a page; detection alone is not a test.',
    'charging': 'Connect/disconnect AC and observe the charging indicator.',
    'firmware': 'Inspect BIOS password and organization/security restrictions in firmware.',
}


def read(path):
    try:
        return Path(path).read_text(errors='replace').strip() or None
    except OSError:
        return None


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def run(args, timeout=20):
    if not shutil.which(args[0]):
        return {'status': 'unavailable', 'reason': args[0] + ' is not installed'}
    try:
        result = subprocess.run(args, capture_output=True, text=True, errors='replace', timeout=timeout, env={**os.environ, 'LC_ALL': 'C'})
        return {'status': 'ok' if result.returncode == 0 else 'error', 'exit_code': result.returncode,
                'stdout': result.stdout[:150000], 'stderr': result.stderr[:4000]}
    except subprocess.TimeoutExpired:
        return {'status': 'unknown', 'reason': 'Timed out; no result'}
    except OSError as error:
        return {'status': 'unknown', 'reason': str(error)}


def decoded(result):
    try:
        return json.loads(result.get('stdout', ''))
    except (ValueError, TypeError):
        return {}


def smart_health(result):
    """smartctl uses an exit bitmask; failed collection must never become a pass."""
    data = decoded(result)
    code = result.get('exit_code', 0)
    if code & 7 or not data:
        return 'unknown'
    if data.get('smart_status', {}).get('passed') is False or code & 24:
        return 'failed'
    nvme = data.get('nvme_smart_health_information_log', {})
    if nvme.get('critical_warning', 0) or code & 224:
        return 'warning'
    if data.get('smart_status', {}).get('passed') is True:
        return 'passed'
    return 'unknown'


def batteries(root=Path('/sys/class/power_supply')):
    result = []
    for path in sorted(root.glob('*')):
        if read(path / 'type') != 'Battery':
            continue
        entry = {key: read(path / key) for key in ('manufacturer', 'model_name', 'status', 'cycle_count', 'capacity')}
        entry['name'] = path.name
        # Never mix charge (uAh) and energy (uWh).
        for unit in ('energy', 'charge'):
            full, design = number(read(path / (unit + '_full'))), number(read(path / (unit + '_full_design')))
            if full is not None and design and full >= 0:
                entry.update(full_capacity=full, design_capacity=design, capacity_unit='uWh' if unit == 'energy' else 'uAh',
                             health_percent=round(100 * full / design, 1))
                break
        entry.setdefault('health_percent', None)
        result.append(entry)
    return result


def flatten(devices):
    for device in devices:
        yield device
        yield from flatten(device.get('children', []))


def usb_output(path):
    mount = decoded(run(['findmnt', '--json', '--target', str(path), '--output', 'SOURCE,FSTYPE,TARGET']))
    filesystems = mount.get('filesystems', [])
    if not filesystems:
        return False
    source = filesystems[0].get('source', '').split('[')[0]
    tree = decoded(run(['lsblk', '--json', '--tree', '--inverse', '--output', 'PATH,TRAN', source]))
    return any(d.get('tran') == 'usb' for d in flatten(tree.get('blockdevices', [])))


def known(value):
    if value is None or str(value).strip().lower() in {'', 'unknown', 'not specified', 'none', 'not provided', 'to be filled by o.e.m.'}:
        return None
    return str(value).strip()


def memory_inventory(result):
    """SMBIOS-reported modules, including explicitly empty slots; never infer DDR type."""
    modules = []
    for block in re.split(r'\n\s*\n', result.get('stdout', '')):
        lines = block.splitlines()
        if not any(line.strip() == 'Memory Device' for line in lines):
            continue
        fields = dict(line.strip().split(': ', 1) for line in lines if ': ' in line)
        size = fields.get('Size', '')
        populated = False if size == 'No Module Installed' else (None if not known(size) else True)
        match = re.fullmatch(r'(\d+) (kB|KB|MB|GB|TB)', size)
        capacity = int(match[1]) * 1024 ** {'kB': 1, 'KB': 1, 'MB': 2, 'GB': 3, 'TB': 4}[match[2]] if match else None
        entry = {'populated': populated, 'size_bytes': capacity}
        for dest, src in {'locator': 'Locator', 'bank': 'Bank Locator', 'type': 'Type',
                          'form_factor': 'Form Factor', 'speed': 'Speed',
                          'configured_speed': 'Configured Memory Speed', 'manufacturer': 'Manufacturer',
                          'part_number': 'Part Number', 'serial': 'Serial Number',
                          'rank': 'Rank', 'data_width': 'Data Width', 'total_width': 'Total Width'}.items():
            entry[dest] = known(fields.get(src))
        if entry['configured_speed'] is None:
            entry['configured_speed'] = known(fields.get('Configured Clock Speed'))
        modules.append(entry)
    populated = [m for m in modules if m['populated'] is True]
    complete = bool(modules) and all(m['populated'] is False or m['size_bytes'] is not None for m in modules)
    return {'status': 'reported' if modules else 'unknown', 'modules': modules,
            'installed_bytes': sum(m['size_bytes'] for m in populated) if complete else None,
            'reported_slots': len(modules) if modules else None,
            'populated_slots': len(populated) if complete else None,
            'types': sorted({m['type'] for m in populated if m['type']}),
            'configured_speeds': sorted({m['configured_speed'] for m in populated if m['configured_speed']})}


def pci_inventory(result, sysfs=Path('/sys/bus/pci/devices')):
    """Parse lspci's documented machine-readable records; PCI aperture is not VRAM."""
    devices = []
    for block in re.split(r'\n\s*\n', result.get('stdout', '')):
        fields = dict(line.split(':\t', 1) for line in block.splitlines() if ':\t' in line)
        slot = fields.get('Slot', '')
        if not re.fullmatch(r'[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]', slot):
            continue
        class_match = re.search(r'\[([0-9a-fA-F]{4})\]', fields.get('Class', ''))
        if not class_match:
            continue
        def label(key):
            return known(re.sub(r'\s*\[[0-9a-fA-F]{4}\]$', '', fields.get(key, '')))
        def pci_id(key):
            match = re.search(r'\[([0-9a-fA-F]{4})\]$', fields.get(key, ''))
            return match[1].lower() if match else None
        vendor_id, device_id = pci_id('Vendor'), pci_id('Device')
        vendor, model = label('Vendor'), label('Device')
        if vendor in (None, 'Vendor'):
            vendor = 'Unknown vendor [' + (vendor_id or '?') + ']'
        if model in (None, 'Device'):
            model = 'Unknown device [' + (device_id or '?') + ']'
        driver = known(fields.get('Driver'))
        if not driver and (sysfs / slot / 'driver').is_symlink():
            driver = (sysfs / slot / 'driver').resolve().name
        vram = read(sysfs / slot / 'mem_info_vram_total')
        vram = int(vram) if vram and vram.isdigit() and int(vram) > 0 else None
        devices.append({'slot': slot, 'class_id': class_match[1].lower(),
                        'vendor': vendor, 'model': model, 'vendor_id': vendor_id, 'device_id': device_id, 'driver': driver,
                        'vram_bytes': vram})
    return devices


def hardware_details(report):
    """Shared text for the live UI and readable HTML; old reports remain valid."""
    def value(v):
        return str(v) if v is not None and v != '' else 'Unknown'
    def size(v):
        return f'{v / 1024**3:g} GiB' if isinstance(v, (int, float)) else 'Unknown'
    memory = report.get('memory', {})
    lines = ['Installed RAM: ' + size(memory.get('installed_bytes')),
             'RAM type: ' + (', '.join(memory.get('types', [])) or 'Unknown')]
    for m in memory.get('modules', []):
        if m.get('populated') is False:
            lines.append('Memory slot ' + value(m.get('locator')) + ': empty (firmware-reported)')
            continue
        lines.append('Memory module ' + value(m.get('locator')) + ': ' + size(m.get('size_bytes')) + ' · ' +
                     value(m.get('type')) + ' · ' + value(m.get('form_factor')) + ' · configured ' +
                     value(m.get('configured_speed')) + ' · rated ' + value(m.get('speed')) + '\n  ' +
                     value(m.get('manufacturer')) + ' · part ' + value(m.get('part_number')) +
                     ' · serial ' + value(m.get('serial')))
    gpus = report.get('gpus', [])
    if not gpus:
        lines.append('GPU: Unknown / not reported')
    for gpu in gpus:
        lines.append('GPU: ' + value(gpu.get('vendor')) + ' ' + value(gpu.get('model')) +
                     '\n  Driver: ' + value(gpu.get('driver')) + ' · Reported VRAM: ' +
                     size(gpu.get('vram_bytes')))
    for adapter in report.get('network_adapters', []):
        lines.append('Network adapter: ' + value(adapter.get('vendor')) + ' ' + value(adapter.get('model')) +
                     ' · driver ' + value(adapter.get('driver')))
    for disk in report.get('storage', []):
        capacity = disk.get('size')
        capacity = f'{int(capacity) / 1_000_000_000:g} GB' if capacity is not None else 'Unknown'
        lines.append('Drive: ' + value(disk.get('model')) + ' · ' + capacity + ' · ' +
                     value(disk.get('drive_type')) + ' · ' + value(disk.get('interface')) +
                     '\n  Serial: ' + value(disk.get('serial')) + ' · health: ' + value(disk.get('health')))
    system = report.get('system', {})
    lines.append('BIOS: ' + value(system.get('bios_version')) + ' · ' + value(system.get('bios_date')))
    return '\n\n'.join(lines)


def collect(asset_id=''):
    dmi = Path('/sys/class/dmi/id')
    system = {name: read(dmi / field) for name, field in {
        'manufacturer': 'sys_vendor', 'model': 'product_name', 'version': 'product_version',
        'serial': 'product_serial', 'bios_version': 'bios_version', 'bios_date': 'bios_date'}.items()}
    cpu = decoded(run(['lscpu', '--json']))
    fields = {row.get('field', '').rstrip(':'): row.get('data') for row in cpu.get('lscpu', [])}
    system['cpu'] = fields.get('Model name')
    system['logical_cpus'] = fields.get('CPU(s)')
    system['cores_per_socket'] = fields.get('Core(s) per socket')
    system['sockets'] = fields.get('Socket(s)')
    system['threads_per_core'] = fields.get('Thread(s) per core')
    mem = read('/proc/meminfo') or ''
    match = re.search(r'^MemTotal:\s+(\d+)', mem, re.M)
    system['usable_memory_bytes'] = int(match[1]) * 1024 if match else None
    system['architecture'] = platform.machine()
    storage_result = run(['lsblk', '--json', '--bytes', '--output', 'NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,ROTA,RM'])
    drives = []
    for disk in flatten(decoded(storage_result).get('blockdevices', [])):
        if disk.get('type') != 'disk':
            continue
        # Exclude USB disks, including this toolkit's own boot/report media.
        if disk.get('tran') == 'usb':
            continue
        entry = {k: v for k, v in disk.items() if k != 'children'}
        device = disk.get('path', '')
        if re.fullmatch(r'/dev/[A-Za-z0-9_.-]+', device):
            probe = run(['smartctl', '--all', '--json', device], timeout=30)
        else:
            probe = {'status': 'unknown', 'reason': 'Invalid device path'}
        rotation = disk.get('rota')
        entry['drive_type'] = 'HDD' if rotation in (True, 1, '1') else ('SSD' if rotation in (False, 0, '0') else 'Unknown')
        entry['interface'] = {'nvme': 'NVMe', 'sata': 'SATA', 'ata': 'ATA', 'sas': 'SAS', 'mmc': 'eMMC/SD'}.get(disk.get('tran'), disk.get('tran') or 'Unknown')
        if entry['interface'] == 'eMMC/SD':
            entry['drive_type'] = 'Flash'
        entry.update(health=smart_health(probe), smart=probe)
        drives.append(entry)
    secureboot = None
    for var in Path('/sys/firmware/efi/efivars').glob('SecureBoot-*'):
        try:
            data = var.read_bytes()
            if len(data) >= 5:
                secureboot = bool(data[4])
        except OSError:
            pass
    displays = []
    for connector in sorted(Path('/sys/class/drm').glob('card*-*')):
        if read(connector / 'status') == 'connected':
            displays.append({'connector': connector.name, 'advertised_modes': (read(connector / 'modes') or '').splitlines()})
    temperatures = [{'sensor': read(p / 'type'), 'millidegrees_c': number(read(p / 'temp'))}
                    for p in Path('/sys/class/thermal').glob('thermal_zone*')]
    memory_raw = run(['dmidecode', '--type', 'memory'])
    pci_raw = run(['lspci', '-D', '-vmm', '-nn', '-k'])
    pci = pci_inventory(pci_raw)
    return {
        'schema_version': 1, 'toolkit_version': VERSION, 'report_id': str(uuid.uuid4()),
        'collected_at': dt.datetime.now(dt.timezone.utc).isoformat(), 'asset_id': asset_id,
        'system': system, 'batteries': batteries(), 'storage': drives,
        'storage_collection': storage_result, 'displays': displays, 'temperatures': temperatures,
        'firmware': {'uefi': Path('/sys/firmware/efi').exists(), 'secure_boot': secureboot,
                     'tpm_versions': [read(p / 'tpm_version_major') for p in Path('/sys/class/tpm').glob('tpm*')],
                     'bios_password': 'unknown', 'organization_enrollment': 'unknown', 'windows_11_eligibility': 'not assessed'},
        'memory_modules': memory_raw, 'memory': memory_inventory(memory_raw),
        'gpus': [d for d in pci if d['class_id'].startswith('03')],
        'network_adapters': [d for d in pci if d['class_id'].startswith('02')],
        'pci_devices': pci_raw, 'usb_devices': run(['lsusb']),
        'network': run(['ip', '-json', 'link']),
        'manual_checks': {key: 'not tested' for key in CHECKS},
        'cosmetics': 'not graded', 'notes': '',
        'tests': {'memory': {'status': 'not tested'}, 'cpu': {'status': 'not tested'}},
        'limitations': ['Inventory is not a full hardware test.', 'USB storage is excluded from drive-health checks.',
                         'Usable memory is not installed module capacity; see memory_modules when available.',
                         'Display modes are advertised modes, not a verified native resolution.',
                         'Firmware passwords, Absolute/Computrace and Autopilot require separate checks.',
                         'No Windows licensing or Windows 11 compatibility conclusion is inferred.'],
    }


def ask_choice(prompt, choices, default):
    while True:
        value = input(prompt + ' [' + '/'.join(choices) + '] (' + default + '): ').strip().lower()
        if not value:
            return default
        if value in choices:
            return value


def guided(report):
    print('\nGuided checks: record only what you actually tested. Enter skips a check.')
    for name, help_text in CHECKS.items():
        print('\n' + help_text)
        report['manual_checks'][name] = ask_choice(name, ['pass', 'fail', 'not tested', 'not applicable'], 'not tested')
    report['cosmetics'] = ask_choice('Cosmetic grade', ['excellent', 'good', 'fair', 'poor', 'not graded'], 'not graded')
    report['notes'] = input('Damage, missing parts, accessories or other notes: ').strip()[:4000]


def longer_tests(report):
    print('\nOptional tests use CPU/RAM only. Connect AC; stop with Ctrl+C if needed.')
    if ask_choice('Run a 60-second CPU verification test?', ['yes', 'no'], 'no') == 'yes':
        result = run(['stress-ng', '--cpu', str(min(os.cpu_count() or 1, 4)), '--verify', '--timeout', '60s', '--metrics-brief'], timeout=80)
        result['status'] = 'passed' if result.get('exit_code') == 0 else ('failed' if result.get('exit_code') else result['status'])
        result['scope'] = '60 seconds, at most 4 workers; not a thermal certification'
        report['tests']['cpu'] = result
    if ask_choice('Run one 256 MiB memory test pass?', ['yes', 'no'], 'no') == 'yes':
        available = re.search(r'^MemAvailable:\s+(\d+)', read('/proc/meminfo') or '', re.M)
        if not available or int(available[1]) < 768 * 1024:
            report['tests']['memory'] = {'status': 'not tested', 'reason': 'Less than 768 MiB available or unknown'}
        else:
            result = run(['memtester', '256M', '1'], timeout=600)
            result['status'] = 'passed' if result.get('exit_code') == 0 else ('failed' if result.get('exit_code') else result['status'])
            result['scope'] = '256 MiB only; use a bootable memory tester for full RAM coverage'
            report['tests']['memory'] = result


def safe_cell(value):
    value = '' if value is None else str(value)
    return "'" + value if value.lstrip().startswith(('=', '+', '-', '@')) else value


def summary(report):
    system = report['system']
    return {
        'asset_id': report['asset_id'], 'collected_at': report['collected_at'],
        'manufacturer': system.get('manufacturer'), 'model': system.get('model'), 'serial': system.get('serial'),
        'cpu': system.get('cpu'), 'usable_memory_bytes': system.get('usable_memory_bytes'),
        'installed_memory_bytes': report.get('memory', {}).get('installed_bytes'),
        'ram_type': '; '.join(report.get('memory', {}).get('types', [])) or 'unknown',
        'ram_configured_speed': '; '.join(report.get('memory', {}).get('configured_speeds', [])) or 'unknown',
        'gpu': '; '.join((g.get('vendor') or '') + ' ' + (g.get('model') or 'unknown') for g in report.get('gpus', [])) or 'unknown',
        'storage_bytes': sum(int(d.get('size') or 0) for d in report['storage']),
        'storage_details': '; '.join((d.get('model') or 'Unknown') + ' | ' + str(d.get('size') or 'Unknown') + ' bytes | ' + d.get('drive_type', 'Unknown') + ' | ' + d.get('interface', 'Unknown') for d in report['storage']),
        'storage_health': '; '.join(d.get('health', 'unknown') for d in report['storage']) or 'unknown',
        'battery_health_percent': '; '.join(str(b.get('health_percent') if b.get('health_percent') is not None else 'unknown') for b in report['batteries']) or 'unknown / not present',
        'cosmetics': report['cosmetics'], 'failed_manual_checks': '; '.join(k for k, v in report['manual_checks'].items() if v == 'fail'),
        'memory_test': report['tests']['memory']['status'], 'cpu_test': report['tests']['cpu']['status'], 'notes': report['notes']}


def write_csv(path, rows):
    with path.open('x', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows({k: safe_cell(v) for k, v in row.items()} for row in rows)
        stream.flush()
        os.fsync(stream.fileno())


def make_html(report):
    esc = lambda value: html.escape(str(value if value is not None else 'Unknown'))
    rows = ''.join('<tr><th>' + esc(k.replace('_', ' ')) + '</th><td>' + esc(v) + '</td></tr>' for k, v in summary(report).items())
    checks = ''.join('<tr><th>' + esc(k) + '</th><td>' + esc(v) + '</td></tr>' for k, v in report['manual_checks'].items())
    return '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Macus Inventory Report</title><style>body{font:16px system-ui;max-width:1000px;margin:40px auto;padding:0 20px;color:#182738;background:#f5f7fa}h1{color:#145d72}table{width:100%;border-collapse:collapse;background:white}th,td{text-align:left;padding:10px;border-bottom:1px solid #ddd;overflow-wrap:anywhere}th{width:32%}pre{white-space:pre-wrap;overflow-wrap:anywhere}p{line-height:1.5}</style>
<h1>Macus · Inventory &amp; Diagnostics</h1><p>Unknown and not tested are not passing results. Hardware detection does not prove functionality.</p><table>''' + rows + '</table><h2>Hardware details</h2><pre>' + esc(hardware_details(report)) + '</pre><h2>Guided checks</h2><table>' + checks + '</table><h2>Scope and limitations</h2><ul>' + ''.join('<li>' + esc(x) + '</li>' for x in report['limitations']) + '</ul><details><summary>Full technical report</summary><pre>' + esc(json.dumps(report, indent=2)) + '</pre></details></html>'


def save(report, output):
    """Unique report directories prevent overwrite; publish only complete bundles."""
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    label = re.sub(r'[^A-Za-z0-9_-]', '_', report['asset_id'] or report['system'].get('serial') or 'device')[:60]
    name = label + '-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    staging = Path(tempfile.mkdtemp(prefix='.collecting-', dir=output))
    try:
        (staging / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        (staging / 'report.html').write_text(make_html(report), encoding='utf-8')
        write_csv(staging / 'summary.csv', [summary(report)])
        os.rename(staging, output / name)
        if hasattr(os, 'sync'):
            os.sync()
        return output / name
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset-id', default=None)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent / 'Reports')
    parser.add_argument('--quick', action='store_true', help='Collect only; skip guided/optional tests')
    parser.add_argument('--allow-local-output', action='store_true', help='Explicitly allow reports on non-USB storage')
    args = parser.parse_args()
    if platform.system() != 'Linux':
        parser.error('Run this toolkit inside a Linux live session on the PC being inspected.')
    if os.geteuid() != 0:
        print('Running without root: firmware, RAM module and SMART readings may be unavailable.')
    parent = args.output.resolve()
    while not parent.exists():
        parent = parent.parent
    if not args.allow_local_output and not usb_output(parent):
        parser.error('Report destination is not verified USB storage. Choose its mounted data partition with --output. Use --allow-local-output only for an intentional local destination.')
    # Fail before scanning if destination cannot be written.
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile(dir=args.output):
        pass
    asset = args.asset_id if args.asset_id is not None else ('' if args.quick else input('Asset ID (optional): ').strip()[:80])
    print('Collecting hardware information. Drives are not mounted, formatted or written by this tool.')
    report = collect(asset[:80])
    try:
        if not args.quick:
            guided(report)
            longer_tests(report)
    except (KeyboardInterrupt, EOFError):
        report['notes'] += '\nSession interrupted; uncompleted checks are not tested.'
        print('\nSaving collected results…')
    destination = save(report, args.output)
    print('Saved HTML, JSON and CSV reports to: ' + str(destination))
    print('Safely eject the USB after shutting down the live session.')


if __name__ == '__main__':
    try:
        main()
    except OSError as error:
        print('Could not complete or save report: ' + str(error), file=sys.stderr)
        sys.exit(1)
