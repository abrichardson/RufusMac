import importlib.util
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'diagnostics/quickscan'))
import enhancements as e


class EnhancementTests(unittest.TestCase):
    def test_clock_never_assumes_plausible_means_verified(self):
        self.assertEqual(e.clock_status('2026-09-12T13:00:00+00:00', '2026-09-12T17:00:00+00:00')['status'], 'suspect')
        self.assertEqual(e.clock_status('2026-09-13T13:00:00+00:00', '2026-09-12T17:00:00+00:00')['status'], 'unverified')
        self.assertEqual(e.clock_status('2026-09-13T13:00:00+00:00', '2026-09-12T17:00:00+00:00', True)['status'], 'synchronized')
        self.assertEqual(e.clock_status('bad', None)['status'], 'unverified')

    def test_gpu_memory_is_device_specific_and_not_aperture(self):
        log = 'nouveau 0000:01:00.0: DRM: VRAM: 4096 MiB\nnouveau 0000:02:00.0: DRM: VRAM: 2048 MiB\nBAR 1: 256 MiB\n[TTM] Available graphics memory: 16000 MiB'
        self.assertEqual(e.nouveau_memory(log), {'0000:01:00.0': 4*1024**3, '0000:02:00.0': 2*1024**3})
        self.assertEqual(e.nouveau_memory('nouveau 0000:01:00.0: DRM: VRAM: 0 MiB'), {})

    def test_repeated_saves_and_full_disk(self):
        spec = importlib.util.spec_from_file_location('isolated_inventory', ROOT / 'Sources/MacusKit/Resources/InventoryToolkit/inventory.py')
        inv = importlib.util.module_from_spec(spec); spec.loader.exec_module(inv)
        e.install(inv)
        with patch.object(inv, 'run', return_value={}):
            report = inv.collect('SAME-SERIAL')
            e.enrich(report, inv)
        report['system']['version'] = '<ThinkPad>'
        report['memory']['installed_bytes'] = 64*1024**3
        report['quick_scan'] = {'collection_seconds': 1.2}
        with tempfile.TemporaryDirectory() as folder, patch.object(inv.os, 'sync'):
            first = inv.save(report, Path(folder)); second = inv.save(report, Path(folder))
            self.assertNotEqual(first, second)
            self.assertEqual(len(list(Path(folder).iterdir())), 2)
            text = (first/'report.html').read_text()
            self.assertIn('&lt;ThinkPad&gt;', text)
            self.assertIn('64 GiB', text)
            self.assertNotIn('<th>installed memory bytes</th>', text)
            with patch.object(inv, 'write_csv', side_effect=OSError(28, 'No space left on device')):
                with self.assertRaises(OSError): inv.save(report, Path(folder))
            self.assertEqual(len(list(Path(folder).iterdir())), 2)
