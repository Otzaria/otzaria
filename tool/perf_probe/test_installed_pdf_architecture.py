"""Regression cases for actual native x64/ARM64 bundle provenance."""

import copy
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

try:
    from .installed_pdf_architecture import MODULES, binary_architecture, validate_bundle
except ImportError:
    from installed_pdf_architecture import MODULES, binary_architecture, validate_bundle

COMMIT = "a" * 40


def native_bytes(platform, architecture, marker=0):
    data = bytearray(512)
    if platform == "linux":
        data[:7] = b"\x7fELF\x02\x01\x01"
        struct.pack_into("<HHI", data, 16, 3, 183 if architecture == "arm64" else 62, 1)
        struct.pack_into("<H", data, 52, 64)
    else:
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 60, 128)
        data[128:132] = b"PE\x00\x00"
        struct.pack_into("<HH", data, 132, 0xAA64 if architecture == "arm64" else 0x8664, 1)
        struct.pack_into("<H", data, 148, 240)
        struct.pack_into("<H", data, 152, 0x20B)
    data[-1] = marker
    return data


class NativeArchitectureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def fixture(self, platform="linux", architecture="arm64"):
        directory = self.root / f"{platform}-{architecture}"
        directory.mkdir(exist_ok=True)
        executable = directory / ("otzaria.exe" if platform == "windows" else "otzaria")
        executable.write_bytes(native_bytes(platform, architecture))
        libraries = directory if platform == "windows" else directory / "lib"
        libraries.mkdir(exist_ok=True)
        modules = []
        for index, name in enumerate(MODULES[platform], 1):
            path = libraries / name
            data = native_bytes(platform, architecture, index)
            path.write_bytes(data)
            modules.append({"name": name, "path": str(path), "bytes": len(data),
                            "sha256": hashlib.sha256(data).hexdigest()})
        report = {"status": "passed", "platform": platform, "buildMode": "profile",
                  "commit": COMMIT, "flutterVersion": "3.47.7", "pid": 123,
                  "runId": "123-fresh", "errors": [], "contractErrors": [],
                  "pdfRuntime": {
                      "status": "passed", "platform": platform,
                      "executable": str(executable), "bundlePathsVerified": True,
                      "ownedTabsRemaining": 0, "ownedDocumentsRemaining": 0,
                      "indexingActiveAfter": False,
                      "steps": {"loadedModules": {"status": "passed", "modules": modules,
                                                 "observedModulePaths": [item["path"] for item in modules]}}}}
        return report, executable

    def validate(self, report, executable, platform="linux", architecture="arm64"):
        return validate_bundle(report, executable=executable, platform=platform,
                               architecture=architecture, commit=COMMIT)

    def test_real_header_variants_are_distinguished(self):
        for platform in MODULES:
            for architecture in ("x64", "arm64"):
                with self.subTest(platform=platform, architecture=architecture):
                    report, executable = self.fixture(platform, architecture)
                    result = self.validate(report, executable, platform, architecture)
                    self.assertEqual(result["architecture"], architecture)
                    self.assertEqual(len(result["modules"]), 3)
                    self.assertEqual(result["executable"]["architecture"], architecture)
                    self.assertTrue(all(item["architecture"] == architecture for item in result["modules"]))

    def test_x64_executable_cannot_satisfy_arm64_job(self):
        for platform in MODULES:
            with self.subTest(platform=platform):
                report, executable = self.fixture(platform, "x64")
                with self.assertRaisesRegex(ValueError, "Expected native arm64"):
                    self.validate(report, executable, platform)

    def test_one_wrong_architecture_library_fails_even_with_matching_hash(self):
        for platform in MODULES:
            with self.subTest(platform=platform):
                report, executable = self.fixture(platform)
                module = report["pdfRuntime"]["steps"]["loadedModules"]["modules"][1]
                data = native_bytes(platform, "x64", 2)
                Path(module["path"]).write_bytes(data)
                module["sha256"] = hashlib.sha256(data).hexdigest()
                with self.assertRaisesRegex(ValueError, "Expected native arm64"):
                    self.validate(report, executable, platform)

    def test_stale_module_hash_is_rejected(self):
        report, executable = self.fixture()
        module = report["pdfRuntime"]["steps"]["loadedModules"]["modules"][0]
        module["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "differs from the native receipt"):
            self.validate(report, executable)

    def test_native_receipt_requires_integer_size(self):
        report, executable = self.fixture()
        report["pdfRuntime"]["steps"]["loadedModules"]["modules"][0]["bytes"] = True
        with self.assertRaisesRegex(ValueError, "differs from the native receipt"):
            self.validate(report, executable)

    def test_foreign_executable_report_is_rejected(self):
        report, executable = self.fixture()
        foreign = self.root / "foreign"
        foreign.write_bytes(executable.read_bytes())
        report["pdfRuntime"]["executable"] = str(foreign)
        with self.assertRaisesRegex(ValueError, "expected bundled executable"):
            self.validate(report, executable)

    def test_foreign_loaded_library_is_rejected(self):
        report, executable = self.fixture()
        loaded = report["pdfRuntime"]["steps"]["loadedModules"]
        foreign = self.root / "libpdfium.so"
        foreign.write_bytes(Path(loaded["modules"][0]["path"]).read_bytes())
        loaded["observedModulePaths"][0] = str(foreign)
        with self.assertRaisesRegex(ValueError, "uniquely loaded from the bundle"):
            self.validate(report, executable)

    def test_duplicate_mapped_library_is_rejected(self):
        report, executable = self.fixture()
        loaded = report["pdfRuntime"]["steps"]["loadedModules"]
        loaded["observedModulePaths"].append(loaded["observedModulePaths"][0])
        with self.assertRaisesRegex(ValueError, "uniquely loaded"):
            self.validate(report, executable)

    def test_linux_library_directory_symlink_cannot_escape_bundle(self):
        report, executable = self.fixture()
        libraries = executable.parent / "lib"
        external = self.root / "external"
        libraries.rename(external)
        libraries.symlink_to(external, target_is_directory=True)
        loaded = report["pdfRuntime"]["steps"]["loadedModules"]
        for module in loaded["modules"]:
            module["path"] = str(external / module["name"])
        loaded["observedModulePaths"] = [module["path"] for module in loaded["modules"]]
        with self.assertRaisesRegex(ValueError, "escapes the actual bundle"):
            self.validate(report, executable)

    def test_deleted_linux_mapping_cannot_hide_an_extra_module(self):
        report, executable = self.fixture()
        paths = report["pdfRuntime"]["steps"]["loadedModules"]["observedModulePaths"]
        paths.append(str(self.root / "libpdfium.so") + " (deleted)")
        with self.assertRaisesRegex(ValueError, "uniquely loaded"):
            self.validate(report, executable)

    def test_missing_mapped_library_is_rejected(self):
        report, executable = self.fixture()
        report["pdfRuntime"]["steps"]["loadedModules"]["observedModulePaths"].pop()
        with self.assertRaisesRegex(ValueError, "uniquely loaded"):
            self.validate(report, executable)

    def test_duplicate_module_receipt_is_rejected(self):
        report, executable = self.fixture()
        modules = report["pdfRuntime"]["steps"]["loadedModules"]["modules"]
        modules[1] = copy.deepcopy(modules[0])
        with self.assertRaisesRegex(ValueError, "duplicate or unexpected"):
            self.validate(report, executable)

    def test_replaced_printing_pdfium_is_rejected(self):
        report, executable = self.fixture()
        modules = report["pdfRuntime"]["steps"]["loadedModules"]["modules"]
        Path(modules[1]["path"]).write_bytes(Path(modules[0]["path"]).read_bytes())
        modules[1]["sha256"] = modules[0]["sha256"]
        with self.assertRaisesRegex(ValueError, "separate PDFium"):
            self.validate(report, executable)

    def test_previous_commit_and_failed_run_are_rejected(self):
        report, executable = self.fixture()
        for key, value in (("commit", "b" * 40), ("status", "failed"),
                           ("platform", "windows"), ("buildMode", "release"),
                           ("errors", ["native error"]), ("contractErrors", ["bad evidence"]),
                           ("flutterVersion", "3.50.0"), ("pid", True), ("runId", "")):
            with self.subTest(key=key):
                modified = copy.deepcopy(report)
                modified[key] = value
                with self.assertRaises(ValueError):
                    self.validate(modified, executable)

    def test_retained_native_ownership_is_rejected(self):
        report, executable = self.fixture()
        for key, value in (("ownedTabsRemaining", 1), ("ownedDocumentsRemaining", True),
                           ("indexingActiveAfter", True), ("bundlePathsVerified", False),
                           ("status", "failed")):
            with self.subTest(key=key):
                modified = copy.deepcopy(report)
                modified["pdfRuntime"][key] = value
                with self.assertRaises(ValueError):
                    self.validate(modified, executable)

    def test_malformed_native_headers_are_rejected(self):
        cases = []
        elf = native_bytes("linux", "arm64")
        for offset, value in ((4, 1), (5, 2), (6, 0), (18, 40), (52, 0)):
            data = bytearray(elf)
            data[offset] = value
            cases.append(data)
        pe = native_bytes("windows", "arm64")
        for offset, value in ((128, 0), (134, 0), (148, 0), (153, 1)):
            data = bytearray(pe)
            data[offset] = value
            cases.append(data)
        arm64ec = bytearray(pe)
        struct.pack_into("<H", arm64ec, 132, 0xA641)
        cases.extend((arm64ec, pe[:200], bytearray(64), pe[:20]))
        for index, data in enumerate(cases):
            with self.subTest(index=index):
                path = self.root / f"bad-{index}"
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    binary_architecture(path)

    def test_wrong_binary_format_for_platform_is_rejected(self):
        report, executable = self.fixture()
        executable.write_bytes(native_bytes("windows", "arm64"))
        with self.assertRaisesRegex(ValueError, "Wrong native binary format"):
            self.validate(report, executable)

    def test_unobserved_native_library_cannot_use_relative_evidence(self):
        report, executable = self.fixture()
        report["pdfRuntime"]["steps"]["loadedModules"]["modules"][0]["path"] = "lib/libpdfium.so"
        with self.assertRaisesRegex(ValueError, "must be absolute"):
            self.validate(report, executable)


if __name__ == "__main__":
    unittest.main()
