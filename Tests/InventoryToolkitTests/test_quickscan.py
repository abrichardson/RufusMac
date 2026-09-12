import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'diagnostics/quickscan'))
sys.path.insert(0, str(ROOT / 'diagnostics'))
sys.path.insert(0, str(ROOT / 'Sources/MacusKit/Resources/InventoryToolkit'))
import quickscan as quick


class QuickScanTests(unittest.TestCase):
    def test_only_selects_own_boot_usb(self):
        own, other = Path('/own/MacusReports'), Path('/other/MacusReports')
        with patch.object(quick.storage, 'find_storage', return_value=[other, own]), patch.object(quick, 'usb_disks', side_effect=lambda p: {'/dev/sda'} if p != other else {'/dev/sdb'}):
            self.assertEqual(quick.destination(), own)
        with patch.object(quick, 'usb_disks', return_value=set()):
            with self.assertRaises(OSError):
                quick.destination()
        with patch.object(quick.storage, 'find_storage', return_value=[own, own]), patch.object(quick, 'usb_disks', return_value={'/dev/sda'}):
            with self.assertRaises(OSError):
                quick.destination()

    def test_probe_budget_and_unique_fallback(self):
        normal = quick.inventory.run
        with patch.object(quick.inventory, 'run', return_value={'status': 'unavailable'}) as run:
            report = quick.collect_quick(budget=0)
            self.assertEqual(run.call_count, 0)
        self.assertIs(quick.inventory.run, normal)
        self.assertTrue(report['asset_id'].startswith('PC-'))
        self.assertTrue(report['quick_scan']['skipped_commands'])
        self.assertEqual(report['tests']['cpu']['status'], 'not tested')
        self.assertTrue(all(v == 'not tested' for v in report['manual_checks'].values()))

    def test_save_failure_never_powers_off(self):
        report = {'quick_scan': {}}
        with patch.object(quick, 'announce'), patch.object(quick, 'collect_quick', return_value=report), patch.object(quick, 'destination', side_effect=OSError('disk full')), patch.object(quick.inventory, 'save', return_value=Path('/run/recovery')), patch.object(quick.inventory, 'run') as run:
            self.assertEqual(quick.main(), 1)
            run.assert_not_called()

    def test_write_failure_stays_on_and_attempts_ram_recovery(self):
        output = Path('/usb/MacusReports')
        report = {'quick_scan': {}}
        with patch.object(quick, 'announce'), patch.object(quick, 'collect_quick', return_value=report), patch.object(quick, 'destination', return_value=output), patch.object(quick, 'usb_disks', return_value={'/dev/sda'}), patch.object(quick.storage, 'marked', return_value=True), patch.object(quick.inventory, 'save', side_effect=[OSError(28, 'No space left on device'), Path('/run/recovery')]) as save, patch.object(quick.inventory, 'run') as run:
            self.assertEqual(quick.main(), 1)
            run.assert_not_called()
            self.assertEqual(save.call_count, 2)
            self.assertEqual(save.call_args.args[1], Path('/run/macus-quickscan'))

    def test_saves_before_shutdown(self):
        output = Path('/usb/MacusReports')
        report = {'quick_scan': {}}
        order = []
        with patch.object(quick, 'announce'), patch.object(quick, 'collect_quick', return_value=report), patch.object(quick, 'destination', return_value=output), patch.object(quick, 'usb_disks', return_value={'/dev/sda'}), patch.object(quick.storage, 'marked', return_value=True), patch.object(quick.inventory, 'save', side_effect=lambda r, p: order.append('save') or output), patch.object(quick.inventory, 'run', side_effect=lambda *a, **kw: order.append('poweroff') or {'exit_code': 0}), patch.object(quick.time, 'sleep'):
            self.assertEqual(quick.main(), 0)
            self.assertEqual(order, ['save', 'poweroff'])


if __name__ == '__main__':
    unittest.main()
