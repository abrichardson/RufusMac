import sys
sys.dont_write_bytecode = True
from pathlib import Path
import tempfile
import json
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'diagnostics'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Sources/MacusKit/Resources/InventoryToolkit'))
import storage


class StorageTests(unittest.TestCase):
    def test_only_usb_backed_filesystems_including_ventoy_mapping(self):
        devices = [
            {'path': '/dev/nvme0n1', 'tran': 'nvme', 'children': [{'path': '/dev/nvme0n1p1', 'fstype': 'exfat'}]},
            {'path': '/dev/sda', 'tran': 'usb', 'children': [
                {'path': '/dev/sda1', 'fstype': 'exfat', 'children': [{'path': '/dev/mapper/sda1', 'fstype': 'exfat'}]},
                {'path': '/dev/sda2', 'fstype': 'iso9660'}]}]
        paths = [d['path'] for d in storage.candidates(devices)]
        self.assertEqual(paths, ['/dev/sda1', '/dev/mapper/sda1'])

    def test_marker_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertFalse(storage.marked(root))
            marker = root / storage.MARKER
            marker.write_text(json.dumps({'schema_version': 1, 'purpose': 'macus-diagnostics'}))
            self.assertTrue(storage.marked(root))
            (root / storage.REPORTS).symlink_to(root)
            self.assertFalse(storage.marked(root))
            (root / storage.REPORTS).unlink()
            marker.write_text('[]')
            self.assertFalse(storage.marked(root))

    def test_does_not_mount_internal_disk_even_when_label_looks_valid(self):
        output = {'stdout': json.dumps({'blockdevices': [{'path': '/dev/sda', 'tran': 'sata', 'fstype': 'exfat', 'label': 'Ventoy'}]})}
        with patch.object(storage, 'run', return_value=output) as run:
            self.assertEqual(storage.find_storage(), [])
            self.assertEqual(run.call_count, 1)
            self.assertIn("--tree", run.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
