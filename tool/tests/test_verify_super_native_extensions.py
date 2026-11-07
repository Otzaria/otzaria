"""The provenance gate replaces formatting/analysis only for unchanged upstream."""

import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "verify_vendor", Path(__file__).resolve().parents[1] / "verify_super_native_extensions.py"
)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class ProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.upstream = {
            "lib/reader.dart": ("100644", b"upstream Dart"),
            "rust/src/linux/reader.rs": ("100644", b"upstream Linux"),
            "cargokit/run_build_tool.sh": ("100755", b"upstream build"),
            "rust/src/win32/reader.rs": ("100644", b"upstream Windows"),
            "LICENSE": ("100644", b"license"),
        }
        self.local = dict(self.upstream)
        for name in verifier.ADDED:
            self.local[name] = ("100644", b"local addition")

    def test_windows_reader_change_is_allowed(self):
        self.local["rust/src/win32/reader.rs"] = ("100644", b"patched Windows")
        verifier.verify_sources(self.upstream, self.local)

    def test_dart_other_platform_build_and_license_changes_fail(self):
        for name in ("lib/reader.dart", "rust/src/linux/reader.rs", "cargokit/run_build_tool.sh", "LICENSE"):
            with self.subTest(name=name):
                changed = dict(self.local)
                changed[name] = (changed[name][0], b"changed")
                with self.assertRaises(ValueError):
                    verifier.verify_sources(self.upstream, changed)

    def test_removing_source_or_license_fails(self):
        for name in self.upstream:
            with self.subTest(name=name):
                changed = dict(self.local)
                del changed[name]
                with self.assertRaises(ValueError):
                    verifier.verify_sources(self.upstream, changed)

    def test_executable_mode_change_fails(self):
        self.local["cargokit/run_build_tool.sh"] = ("100644", b"upstream build")
        with self.assertRaises(ValueError):
            verifier.verify_sources(self.upstream, self.local)

    def test_added_unreviewed_file_fails(self):
        self.local["lib/override.dart"] = ("100644", b"new")
        with self.assertRaises(ValueError):
            verifier.verify_sources(self.upstream, self.local)

    def test_missing_regression_tests_fail(self):
        del self.local["rust/src/win32/bitmap_reader_tests.rs"]
        with self.assertRaises(ValueError):
            verifier.verify_sources(self.upstream, self.local)

    def test_archive_hash_mismatch_fails_before_tar_parsing(self):
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            verifier.archive_sources(b"wrong archive")


if __name__ == "__main__":
    unittest.main()
