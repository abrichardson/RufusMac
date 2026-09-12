import csv
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[2] / 'Sources/MacusKit/Resources/InventoryToolkit/inventory.py'
spec = importlib.util.spec_from_file_location('inventory', MODULE)
inv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inv)


class InventoryTests(unittest.TestCase):
    def test_smart_bitmask_and_missing_data(self):
        def smart(code, data):
            return inv.smart_health({'exit_code': code, 'stdout': json.dumps(data)})
        self.assertEqual(smart(0, {}), 'unknown')
        self.assertEqual(inv.smart_health({'status': 'unavailable'}), 'unknown')
        self.assertEqual(smart(2, {'smart_status': {'passed': True}}), 'unknown')
        self.assertEqual(smart(0, {'smart_status': {'passed': True}}), 'passed')
        self.assertEqual(smart(8, {'smart_status': {'passed': False}}), 'failed')
        self.assertEqual(smart(64, {'smart_status': {'passed': True}}), 'warning')
        self.assertEqual(smart(0, {'nvme_smart_health_information_log': {'critical_warning': 1}}), 'warning')

    def test_battery_units_and_unknowns(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            battery = root / 'BAT0'
            battery.mkdir()
            for key, value in {'type': 'Battery', 'energy_full': '40000', 'charge_full_design': '50000'}.items():
                (battery / key).write_text(value)
            self.assertIsNone(inv.batteries(root)[0]['health_percent'])
            (battery / 'energy_full_design').write_text('50000')
            self.assertEqual(inv.batteries(root)[0]['health_percent'], 80)
            (battery / 'energy_full_design').write_text('0')
            self.assertIsNone(inv.batteries(root)[0]['health_percent'])

    def test_collection_missing_commands_does_not_pass(self):
        with patch.object(inv, 'run', return_value={'status': 'unavailable'}):
            report = inv.collect('PC-001')
        self.assertIsNone(report['system']['cpu'])
        self.assertEqual(report['storage'], [])
        self.assertEqual(report['tests']['memory']['status'], 'not tested')
        self.assertTrue(all(x == 'not tested' for x in report['manual_checks'].values()))
        self.assertEqual(report['firmware']['organization_enrollment'], 'unknown')

    def test_usb_guard_requires_usb_ancestry(self):
        mount = {'stdout': json.dumps({'filesystems': [{'source': '/dev/sdb1'}]})}
        def tree(transport):
            return {'stdout': json.dumps({'blockdevices': [{'path': '/dev/sdb1', 'children': [{'tran': transport}]}]})}
        with patch.object(inv, 'run', side_effect=[mount, tree('usb')]):
            self.assertTrue(inv.usb_output(Path('/reports')))
        with patch.object(inv, 'run', side_effect=[mount, tree('nvme')]):
            self.assertFalse(inv.usb_output(Path('/reports')))
        with patch.object(inv, 'run', return_value={'status': 'error'}):
            self.assertFalse(inv.usb_output(Path('/reports')))

    def test_storage_excludes_usb_and_preserves_smart_error(self):
        def fake(args, **kwargs):
            if args[0] == 'lsblk':
                return {'stdout': json.dumps({'blockdevices': [
                    {'type': 'disk', 'path': '/dev/sda', 'tran': 'usb'},
                    {'type': 'disk', 'path': '/dev/nvme0n1', 'tran': 'nvme', 'size': 1000}]})}
            return {'status': 'unavailable'}
        with patch.object(inv, 'run', side_effect=fake):
            report = inv.collect()
        self.assertEqual(len(report['storage']), 1)
        self.assertEqual(report['storage'][0]['health'], 'unknown')

    def test_safe_exports_and_unique_runs(self):
        with patch.object(inv, 'run', return_value={'status': 'unavailable'}):
            report = inv.collect('../../=malicious')
        report['notes'] = '=HYPERLINK("bad")\n<script>alert(1)</script>'
        with tempfile.TemporaryDirectory() as folder:
            first = inv.save(report, Path(folder))
            second = inv.save(report, Path(folder))
            self.assertNotEqual(first, second)
            self.assertEqual(first.parent, Path(folder).resolve())
            rendered = (first / 'report.html').read_text()
            self.assertNotIn('<script>', rendered)
            self.assertIn('&lt;script&gt;', rendered)
            with (first / 'summary.csv').open(newline='') as stream:
                row = next(csv.DictReader(stream))
            self.assertTrue(row['notes'].startswith("'="))
            self.assertEqual(json.loads((first / 'report.json').read_text())['notes'], report['notes'])
            self.assertFalse(any(p.name.startswith('.collecting-') for p in Path(folder).iterdir()))

    def test_failed_save_does_not_publish_partial_report(self):
        with patch.object(inv, 'run', return_value={'status': 'unavailable'}):
            report = inv.collect()
        with tempfile.TemporaryDirectory() as folder, patch.object(inv, 'write_csv', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                inv.save(report, Path(folder))
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_ram_modules_type_speed_and_empty_slots(self):
        output = """Handle 0x0010, DMI type 17, 40 bytes
Memory Device
    Size: 8192 MB
    Locator: DIMM 0
    Form Factor: SODIMM
    Type: DDR4
    Speed: 3200 MT/s
    Configured Memory Speed: 2667 MT/s
    Manufacturer: Samsung
    Part Number: TEST123

Handle 0x0011, DMI type 17, 40 bytes
Memory Device
    Size: No Module Installed
    Locator: DIMM 1
    Type: Unknown
"""
        memory = inv.memory_inventory({'stdout': output})
        self.assertEqual(memory['installed_bytes'], 8 * 1024**3)
        self.assertEqual(memory['types'], ['DDR4'])
        self.assertEqual(memory['configured_speeds'], ['2667 MT/s'])
        self.assertFalse(memory['modules'][1]['populated'])
        self.assertIsNone(inv.memory_inventory({'status': 'unavailable'})['installed_bytes'])
        self.assertIsNone(inv.memory_inventory({'stdout': output.replace('8192 MB', 'Unknown')})['installed_bytes'])

    def test_gpu_records_include_multiple_devices_and_unknown_vram(self):
        output = """Slot:\t0000:00:02.0
Class:\tVGA compatible controller [0300]
Vendor:\tIntel Corporation [8086]
Device:\tUHD Graphics 620 [5917]
Driver:\ti915

Slot:\t0000:01:00.0
Class:\t3D controller [0302]
Vendor:\tNVIDIA Corporation [10de]
Device:\tGeForce MX150 [1d10]

Slot:\t0000:02:00.0
Class:\tEthernet controller [0200]
Vendor:\tIntel Corporation [8086]
Device:\tEthernet [1234]
"""
        with tempfile.TemporaryDirectory() as tmp:
            devices = inv.pci_inventory({'stdout': output}, Path(tmp))
        self.assertEqual(len(devices), 3)
        self.assertEqual(devices[0]['model'], 'UHD Graphics 620')
        self.assertEqual(devices[0]['driver'], 'i915')
        self.assertEqual(devices[0]['device_id'], '5917')
        self.assertIsNone(devices[1]['vram_bytes'])
        self.assertEqual(devices[1]['class_id'], '0302')
        self.assertEqual(inv.pci_inventory({'status': 'unavailable'}), [])
        unnamed = inv.pci_inventory({'stdout': output.replace('UHD Graphics 620', 'Device')})
        self.assertIn('5917', unnamed[0]['model'])

    def test_drive_kind_size_and_exports(self):
        disks = [
            {'type': 'disk', 'path': '/dev/sda', 'tran': 'sata', 'rota': True, 'size': 1000000000000, 'model': 'HDD model'},
            {'type': 'disk', 'path': '/dev/nvme0n1', 'tran': 'nvme', 'rota': False, 'size': 512000000000, 'model': 'SSD model'},
            {'type': 'disk', 'path': '/dev/sdb', 'tran': 'usb', 'rota': False, 'size': 16000000000}]
        def fake(args, **kwargs):
            return {'stdout': json.dumps({'blockdevices': disks})} if args[0] == 'lsblk' else {'status': 'unavailable'}
        with patch.object(inv, 'run', side_effect=fake):
            report = inv.collect()
        self.assertEqual([d['drive_type'] for d in report['storage']], ['HDD', 'SSD'])
        self.assertEqual(report['storage'][1]['interface'], 'NVMe')
        details = inv.hardware_details(report)
        self.assertIn('1000 GB · HDD · SATA', details)
        self.assertIn('512 GB · SSD · NVMe', details)
        self.assertIn('SSD model', inv.summary(report)['storage_details'])
        self.assertIn('Hardware details', inv.make_html(report))

    def test_formula_prefixes(self):
        for value in ['=1', '+1', '-1', '@bad', '\t=1', '\n@bad']:
            self.assertTrue(inv.safe_cell(value).startswith("'"))
        self.assertEqual(inv.safe_cell('PC-001'), 'PC-001')


if __name__ == '__main__':
    unittest.main()
