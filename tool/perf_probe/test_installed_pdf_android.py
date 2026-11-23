"""Synthetic negative controls for provenance; these are not emulator results."""

import copy
import hashlib
import io
from pathlib import Path
import struct
import tempfile
import tracemalloc
import unittest
import warnings
import zipfile

from tool.perf_probe import installed_pdf_android as pdf

PACKAGE = "org.otzaria.otzaria.installedprobe"
APK_PATH = f"/data/app/~~install-id/{PACKAGE}-package-id/base.apk"
MODULE_PATH = pdf.installed_module_path(APK_PATH)
SYSTEM_PATH = "/system/lib64/libpdfium.so"


def native_elf():
    value = bytearray(1024)
    value[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HH", value, 16, 3, 62)
    value[128:] = b"native fixture bytes " * 42 + b"x" * 14
    return bytes(value)


def apk_bytes(payload=None, *, entry=pdf.PDFIUM_ENTRY, compression=zipfile.ZIP_DEFLATED):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=compression) as archive:
        archive.writestr(entry, native_elf() if payload is None else payload)
        archive.writestr("assets/irrelevant-fixture", b"unrelated resource")
    return buffer.getvalue()


def apk_evidence():
    module_hash = hashlib.sha256(native_elf()).hexdigest()
    return {"package": PACKAGE, "debuggable": True, "sha256": "a" * 64,
            "pdfium": {"entry": pdf.PDFIUM_ENTRY, "abi": "x86_64", "bytes": len(native_elf()),
                       "sha256": module_hash},
            "installed": {"apkPath": APK_PATH, "apkSha256": "a" * 64, "modulePath": MODULE_PATH,
                          "moduleSha256": module_hash}}


def pdf_maps(paths=(MODULE_PATH, SYSTEM_PATH), *, executable=True):
    return "\n".join(f"{(i + 1) * 4096:08x}-{(i + 2) * 4096:08x} "
                     f"{'r-xp' if executable else 'r--p'} 00000000 00:04 {i + 10} {path}"
                     for i, path in enumerate(paths)) + "\n"


def host_maps():
    return {"pid": 123, "observedModulePaths": [MODULE_PATH, SYSTEM_PATH],
            "executableModulePaths": [MODULE_PATH, SYSTEM_PATH]}


def pdf_report():
    report = {"status": "passed", "platform": "android", "bundlePathsVerified": True,
              "physicalPrinter": "notRun", "ownedDocumentsRemaining": 0,
              "ownedTabsRemaining": 0, "indexingActiveAfter": False,
              "steps": {name: {"status": "passed"} for name in pdf.PDF_RUNTIME_STEPS}}
    report["steps"]["loadedModules"].update(
        source="/proc/self/maps", package=PACKAGE, abi="x86_64", processId=123,
        printingBackend="android.graphics.pdf.PdfRenderer", configuredPdfrxModule=None,
        observedModulePaths=[MODULE_PATH, SYSTEM_PATH], executableModulePaths=[MODULE_PATH, SYSTEM_PATH],
        systemModulePaths=[SYSTEM_PATH],
        appModule={"name": "libpdfium.so", "path": MODULE_PATH, "bytes": len(native_elf()),
                   "sha256": hashlib.sha256(native_elf()).hexdigest()},
    )
    return report


class ApkPdfiumTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.apk = Path(temporary.name) / "probe.apk"

    def test_hashes_the_exact_uncompressed_x86_64_entry(self):
        self.apk.write_bytes(apk_bytes())
        self.assertEqual(pdf.apk_pdfium_module(self.apk), apk_evidence()["pdfium"])

    def test_rejects_missing_wrong_abi_wrong_elf_and_changed_packaging(self):
        for invalid in (
            apk_bytes(entry="lib/arm64-v8a/libpdfium.so"),
            apk_bytes(payload=b"not a library"),
            apk_bytes(payload=native_elf()[:18] + b"\xb7\x00" + native_elf()[20:]),
            apk_bytes(payload=native_elf()[:4] + b"\x01" + native_elf()[5:]),
            apk_bytes(compression=zipfile.ZIP_STORED),
        ):
            self.apk.write_bytes(invalid)
            with self.subTest(size=len(invalid)), self.assertRaises(ValueError):
                pdf.apk_pdfium_module(self.apk)

    def test_duplicate_zip_entries_cannot_choose_different_binary_bytes(self):
        self.apk.write_bytes(apk_bytes())
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.apk, "a", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(pdf.PDFIUM_ENTRY, native_elf() + b"second")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            pdf.apk_pdfium_module(self.apk)

    def test_large_apk_member_is_hashed_with_bounded_memory(self):
        payload = native_elf() + b"x" * (8 * 1024 * 1024)
        expected = hashlib.sha256(payload).hexdigest()
        self.apk.write_bytes(apk_bytes(payload))
        tracemalloc.start()
        try:
            result = pdf.apk_pdfium_module(self.apk)
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertEqual(result["sha256"], expected)
        self.assertEqual(result["bytes"], len(payload))
        self.assertLess(peak, 3 * 1024 * 1024)

    def test_installed_path_and_digest_require_the_actual_package_receipts(self):
        self.assertEqual(pdf.installed_apk_path("package:" + APK_PATH + "\n", PACKAGE), APK_PATH)
        self.assertEqual(pdf.sha256_receipt("a" * 64 + "  " + APK_PATH + "\n", APK_PATH), "a" * 64)
        for invalid in ("", "package:/tmp/base.apk", "package:" + APK_PATH.replace(PACKAGE, "foreign.app"),
                        "package:" + APK_PATH + "\npackage:/data/app/split.apk",
                        "package:" + APK_PATH.replace("lib", "../lib") + ";echo BAD"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                pdf.installed_apk_path(invalid, PACKAGE)
        for invalid in ("a" * 64, "a" * 64 + "  /different.apk", "a" * 64 + "  " + APK_PATH + "\nextra"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                pdf.sha256_receipt(invalid, APK_PATH)


class AndroidPdfEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.report = pdf_report()
        self.apk = apk_evidence()
        self.host = host_maps()

    def verify(self):
        return pdf.verify_pdf_runtime(self.report, self.apk, self.host, package=PACKAGE, process_id=123)

    def test_system_pdfrenderer_and_app_pdfium_are_both_allowed(self):
        self.assertEqual(self.verify()["path"], MODULE_PATH)
        for system_path in (SYSTEM_PATH, "/apex/com.android.mediaprovider/lib64/libpdfium.so"):
            self.report["steps"]["loadedModules"].update(
                observedModulePaths=[MODULE_PATH, system_path], executableModulePaths=[MODULE_PATH, system_path],
                systemModulePaths=[system_path])
            self.host.update(observedModulePaths=[MODULE_PATH, system_path],
                             executableModulePaths=[MODULE_PATH, system_path])
            self.verify()

    def test_only_app_library_is_required_when_os_links_pdfium_statically(self):
        self.report["steps"]["loadedModules"].update(
            observedModulePaths=[MODULE_PATH], executableModulePaths=[MODULE_PATH], systemModulePaths=[])
        self.host.update(observedModulePaths=[MODULE_PATH], executableModulePaths=[MODULE_PATH])
        self.verify()

    def test_missing_or_skipped_phases_and_incomplete_teardown_fail(self):
        original = copy.deepcopy(self.report)
        for name in pdf.PDF_RUNTIME_STEPS:
            for status in (None, "notRun", "unsupported", "running", "failed"):
                self.report = copy.deepcopy(original)
                self.report["steps"][name]["status"] = status
                with self.subTest(name=name, status=status), self.assertRaises(ValueError):
                    self.verify()
        for key, value in (("bundlePathsVerified", False), ("ownedDocumentsRemaining", 1),
                           ("ownedTabsRemaining", 1), ("indexingActiveAfter", True), ("platform", "linux"),
                           ("ownedDocumentsRemaining", False), ("ownedTabsRemaining", False),
                           ("indexingActiveAfter", 0), ("bundlePathsVerified", 1)):
            self.report = {**original, key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify()

    def test_no_claimed_hash_or_path_can_replace_apk_and_native_evidence(self):
        for field in ("apkSha256", "moduleSha256", "modulePath", "apkPath"):
            original = self.apk["installed"][field]
            self.apk["installed"][field] = "changed"
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.verify()
            self.apk["installed"][field] = original
        module = self.report["steps"]["loadedModules"]["appModule"]
        for field in ("sha256", "path", "bytes", "name"):
            original = module[field]
            module[field] = "changed"
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.verify()
            module[field] = original
        self.host["pid"] = 124
        with self.assertRaises(ValueError):
            self.verify()

    def test_missing_apk_binary_identity_cannot_be_matched_by_missing_report_values(self):
        for key in ("entry", "abi", "bytes", "sha256"):
            self.apk = apk_evidence()
            self.apk["pdfium"].pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify()

    def test_foreign_deleted_duplicate_and_nonexecutable_maps_fail_on_either_side(self):
        for key in ("app", "host"):
            for paths in ([SYSTEM_PATH], [MODULE_PATH + " (deleted)"],
                          [MODULE_PATH, "/data/local/tmp/libpdfium.so"],
                          [MODULE_PATH, MODULE_PATH], [MODULE_PATH.replace(PACKAGE, "foreign.app")],
                          [MODULE_PATH, "/system/../data/local/tmp/libpdfium.so"]):
                self.report, self.host = pdf_report(), host_maps()
                target = self.report["steps"]["loadedModules"] if key == "app" else self.host
                target["observedModulePaths"] = paths
                with self.subTest(key=key, paths=paths), self.assertRaises(ValueError):
                    self.verify()
            self.report, self.host = pdf_report(), host_maps()
            target = self.report["steps"]["loadedModules"] if key == "app" else self.host
            target["executableModulePaths"] = [SYSTEM_PATH]
            with self.subTest(key=key, executable=False), self.assertRaises(ValueError):
                self.verify()

    def test_maps_parser_keeps_deleted_paths_and_distinguishes_executable_segments(self):
        raw = pdf_maps() + pdf_maps(executable=False) + pdf_maps([MODULE_PATH + " (deleted)"])
        self.assertEqual(pdf.pdfium_mapped_paths(raw), {MODULE_PATH, SYSTEM_PATH, MODULE_PATH + " (deleted)"})
        self.assertEqual(pdf.pdfium_mapped_paths(pdf_maps(executable=False), executable_only=True), set())
        self.assertEqual(pdf.pdfium_mapped_paths(pdf_maps(), executable_only=True), {MODULE_PATH, SYSTEM_PATH})


if __name__ == "__main__":
    unittest.main()
