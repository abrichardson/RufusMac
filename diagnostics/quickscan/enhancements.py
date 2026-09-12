"""Quick Scan report enhancements, deliberately separate from the Macus app."""
import datetime as dt
import html
from pathlib import Path
import re

VERSION = '1.1.0'


def clock_status(collected_at, build_time, synchronized=False):
    result = {'status': 'synchronized' if synchronized else 'unverified',
              'source': 'system clock', 'image_built_at': build_time,
              'warning': '' if synchronized else 'PC clock is unverified. Confirm the date before using it for inventory records.'}
    try:
        stamp = dt.datetime.fromisoformat(collected_at)
        built = dt.datetime.fromisoformat(build_time)
        if stamp < built:
            result.update(status='suspect', warning='PC clock predates this boot image. The recorded date may be incorrect.')
    except (TypeError, ValueError):
        result.update(status='unverified', warning='Clock or build timestamp could not be verified.')
    return result


def nouveau_memory(log):
    # Driver-reported available VRAM, never a PCI BAR/aperture or guessed model size.
    values = {}
    for slot, mib in re.findall(r'nouveau\s+([\da-fA-F]{4}:[\da-fA-F]{2}:[\da-fA-F]{2}\.[0-7]):[^\n]*?VRAM:\s*(\d+) MiB', log):
        if int(mib) > 0:
            values[slot.lower()] = int(mib) * 1024**2
    return values


def enrich(report, inv):
    report['quick_scan_version'] = VERSION
    report['clock'] = clock_status(report['collected_at'], inv.read('/opt/macus/image-built-at'),
                                   Path('/run/systemd/timesync/synchronized').exists())
    missing = [g for g in report.get('gpus', []) if not g.get('vram_bytes') and g.get('driver') == 'nouveau']
    log = inv.run(['dmesg', '--color=never'], timeout=3) if missing else {}
    detected = nouveau_memory(log.get('stdout', ''))
    for gpu in report.get('gpus', []):
        if gpu.get('vram_bytes'):
            gpu['vram_source'] = 'driver sysfs'
        elif gpu in missing and gpu.get('slot', '').lower() in detected:
            gpu['vram_bytes'] = detected[gpu['slot'].lower()]
            gpu['vram_source'] = 'nouveau driver-reported available VRAM'
        else:
            gpu['vram_source'] = 'unavailable; no capacity inferred'
    for disk in report.get('storage', []):
        smart = inv.decoded(disk.get('smart', {}))
        nvme = smart.get('nvme_smart_health_information_log', {})
        disk['health_details'] = {k: nvme.get(k) for k in
            ('percentage_used', 'media_errors', 'num_err_log_entries', 'critical_warning', 'unsafe_shutdowns')}
        disk['health_details']['power_on_hours'] = smart.get('power_on_time', {}).get('hours')
        disk['health_details']['temperature_c'] = smart.get('temperature', {}).get('current')


def size(value, memory=False):
    if not isinstance(value, (int, float)):
        return 'Unknown'
    if memory:
        return f'{value / 1024**3:g} GiB'
    return f'{value / 10**12:.2f} TB' if value >= 10**12 else f'{value / 10**9:.2f} GB'


def install(inv):
    original_summary, original_html = inv.summary, inv.make_html
    def summary(report):
        row = original_summary(report)
        system = report['system']
        row['model_name'] = inv.known(system.get('version')) or system.get('model')
        row['installed_ram'] = size(report.get('memory', {}).get('installed_bytes'), True)
        row['usable_ram'] = size(system.get('usable_memory_bytes'), True)
        row['storage_capacity'] = size(sum(d.get('size') or 0 for d in report.get('storage', []))) if report.get('storage') else 'Unknown'
        row['storage_details'] = '; '.join(f"{d.get('model') or 'Unknown'} | {size(d.get('size'))} | {d.get('drive_type', 'Unknown')} | {d.get('interface', 'Unknown')}" for d in report.get('storage', []))
        row['drive_health_details'] = '; '.join(f"{d.get('model') or 'Unknown'}: " + ', '.join(f'{k.replace("_", " ")}: {v if v is not None else "Unknown"}' for k, v in d.get('health_details', {}).items()) for d in report.get('storage', []))
        row['gpu_memory'] = '; '.join(f"{g.get('model')}: {size(g.get('vram_bytes'), True)} ({g.get('vram_source', 'unavailable')})" for g in report.get('gpus', []))
        row['clock_status'] = report.get('clock', {}).get('status', 'unverified')
        row['clock_warning'] = report.get('clock', {}).get('warning', 'PC clock is unverified.')
        row['scan_seconds'] = report.get('quick_scan', {}).get('collection_seconds')
        row['seconds_from_linux_boot_to_save'] = report.get('quick_scan', {}).get('boot_elapsed_at_save_seconds')
        return row
    def make_html(report):
        # Keep numeric byte fields in CSV/JSON for existing importers; hide them in HTML.
        rendered = original_html(report)
        for key in ('usable memory bytes', 'installed memory bytes', 'storage bytes'):
            rendered = re.sub(r'<tr><th>' + key + r'</th><td>.*?</td></tr>', '', rendered)
        row = summary(report)
        esc = lambda value: html.escape(str(value))
        head = '<h2>' + esc(row['model_name']) + '</h2><p><strong>Serial: ' + esc(report['system'].get('serial')) + '</strong></p>'
        head += '<p><strong>' + esc(row['installed_ram']) + ' RAM · ' + esc(row['storage_capacity']) + ' storage</strong></p>'
        head += '<p>Clock: <strong>' + esc(row['clock_status']) + '</strong>. ' + esc(row['clock_warning']) + '</p>'
        return rendered.replace('<table>', head + '<table>', 1)
    inv.summary, inv.make_html = summary, make_html
