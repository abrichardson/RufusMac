"""Find explicitly prepared USB report storage; never mount internal disks."""
import json
import os
from pathlib import Path
import re
import tempfile
from inventory import run, decoded

MARKER = '.macus-diagnostics.json'
REPORTS = 'MacusReports'
SUPPORTED = {'exfat', 'vfat', 'ntfs', 'ntfs3'}


def candidates(tree):
    result = []
    def visit(nodes, usb=False):
        for node in nodes:
            on_usb = usb or node.get('tran') == 'usb'
            path = node.get('path', '')
            if on_usb and node.get('fstype') in SUPPORTED and re.fullmatch(r'/dev/[A-Za-z0-9_./-]+', path):
                result.append(node)
            visit(node.get('children', []), on_usb)
    visit(tree)
    return result


def marked(root):
    marker = root / MARKER
    reports = root / REPORTS
    try:
        if marker.is_symlink() or reports.is_symlink() or marker.stat().st_size > 1024:
            return False
        data = json.loads(marker.read_text())
        return data.get('schema_version') == 1 and data.get('purpose') == 'macus-diagnostics'
    except (OSError, ValueError, AttributeError):
        return False


def find_storage():
    devices = decoded(run(['lsblk', '--json', '--tree', '--paths', '--output', 'PATH,TYPE,TRAN,FSTYPE,MOUNTPOINTS']))
    found = []
    seen = set()
    for node in candidates(devices.get('blockdevices', [])):
        device = node['path']
        identity = os.path.realpath(device)
        if identity in seen:
            continue
        seen.add(identity)
        mounts = [Path(p) for p in node.get('mountpoints', []) if p]
        owned = False
        if mounts:
            root = mounts[0]
        else:
            root = Path('/run/macus-media') / Path(device).name
            root.mkdir(parents=True, exist_ok=True)
            mounted = run(['mount', '-o', 'ro,nosuid,nodev,noexec', device, str(root)])
            if mounted.get('exit_code') != 0:
                continue
            owned = True
        if not marked(root):
            if owned:
                run(['umount', str(root)])
            continue
        # The marker was created explicitly by Macus's USB preparation action.
        if owned:
            result = run(['mount', '-o', 'remount,rw,nosuid,nodev,noexec', str(root)])
            if result.get('exit_code') != 0:
                run(['umount', str(root)])
                continue
        try:
            destination = root / REPORTS
            destination.mkdir(exist_ok=True)
            with tempfile.TemporaryFile(dir=destination):
                pass
            found.append(destination)
        except OSError:
            if owned:
                run(['umount', str(root)])
    # Multiple marked USBs require explicit selection by the operator.
    return sorted(set(found))
