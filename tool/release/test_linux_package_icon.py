"""Release-package icon contract; uses only Python's standard library.

The icon file under each Linux hicolor path is currently copied from the
single file declared by make_config.yaml. Keep that source compact and ensure
that it is a valid 256x256 PNG before packaging.
"""
from pathlib import Path
import re
import struct
import unittest


ROOT = Path(__file__).resolve().parents[2]
ICON = ROOT / "assets/icon/icon_256.png"
FULL_ICON = ROOT / "assets/icon/icon.png"
MANIFESTS = [
    ROOT / "linux/packaging/deb/make_config.yaml",
    ROOT / "linux/packaging/rpm/make_config.yaml",
]


class LinuxPackageIconContract(unittest.TestCase):
    def test_png_signature_dimensions_and_size(self):
        data = ICON.read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(data[12:16], b"IHDR")
        width, height = struct.unpack_from(">II", data, 16)
        self.assertEqual((width, height), (256, 256))
        self.assertLess(len(data), FULL_ICON.stat().st_size)

    def test_both_package_manifests_use_compact_asset(self):
        for path in MANIFESTS:
            with self.subTest(path=path):
                content = path.read_text(encoding="utf-8")
                icons = re.findall(r"(?m)^icon:\s*(\S+)\s*$", content)
                self.assertEqual(icons, ["assets/icon/icon_256.png"])

    def test_source_file_is_tracked_for_release_packaging(self):
        self.assertTrue(ICON.is_file())
        self.assertGreater(ICON.stat().st_size, 512)


if __name__ == "__main__":
    unittest.main()
