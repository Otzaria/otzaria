"""Evidence contract tests; these fixtures do not execute a macOS native app."""

import copy
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zlib

from tool.perf_probe import validate_installed_plugin_macos as subject

COMMIT = "a" * 40
CORE_GRAPHICS = "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics"


def png(width, height):
    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff" * width * 4) * height)) + chunk(b"IEND", b""))


def pixel_proof(page):
    width, height = subject.PAGE_SIZES[page - 1]
    return {"page": page, "width": width, "height": height,
            "contentPixelsVerified": True, "pixelSha256": "b" * 64}


class MacosInstalledPdfContracts(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.products = self.root / "Profile"
        self.bundle = self.products / "אוצריא with spaces.app"
        self.executable = self.bundle / "Contents/MacOS/אוצריא"
        self.pdfium = self.bundle / "Contents/Frameworks/PDFium.framework/Versions/A/PDFium"
        for path in (self.executable, self.pdfium):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"Contract binary fixture: " + path.name.encode())
        with (self.bundle / "Contents/Info.plist").open("wb") as target:
            plistlib.dump({"CFBundleExecutable": self.executable.name}, target)
        self.output = self.root / "device"
        self.output.mkdir()
        self.loaded = {
            "status": "passed", "durationMs": 1.0, "source": subject.SOURCE, "pid": 173,
            "bundle": str(self.bundle), "executable": str(self.executable),
            "configuredPdfrxModule": None, "printingBackend": subject.PRINTING,
            "images": [str(self.executable), str(self.pdfium), CORE_GRAPHICS],
            "symbols": {name: {"image": str(self.pdfium) if role == "pdfium" else CORE_GRAPHICS,
                               "canonicalImage": str(self.pdfium) if role == "pdfium" else CORE_GRAPHICS,
                               "address": "0x10100", "imageBase": "0x10000"}
                        for role, names in subject.SYMBOLS.items() for name in names},
            "bundledFiles": [{"path": str(path), "bytes": path.stat().st_size, "sha256": subject.digest(path)}
                             for path in (self.executable, self.pdfium)],
        }
        for name in ("bundle-runtime.pdf", "bundle-runtime-cancel.pdf"):
            (self.output / name).write_bytes(b"%PDF-1.7\ncontract PDF fixture\n")
        export_path = self.output / "bundle-runtime-export.pdf"
        export_path.write_bytes(b"%PDF-1.7\ncontract exported PDF fixture\n")
        export = {"sourcePages": [2, 3], "sheets": 1, "textPreserved": True, "rightToLeft": True,
                  "printingRasterVerified": True, "printingInkPixels": 200,
                  "bytes": export_path.stat().st_size, "sha256": subject.digest(export_path)}
        steps = {name: {"status": "passed", "durationMs": 1.0} for name in subject.PDF_STEPS}
        for name, page in (("view", 1), ("reopen", 2)):
            steps[name].update(visibleRenderState="ready", targetPage=page, targetCenterVisible=True,
                               raster=pixel_proof(page))
        steps["reopen"].update(differentDocument=True, previousNativeCloseCompleted=True)
        steps["concurrentWork"].update(indexedPages=[0, 1, 2, 3], viewerTargetPage=4,
                                       targetCenterVisible=True, viewerRaster=pixel_proof(4),
                                       printingRasters=[pixel_proof(page) for page in range(1, 5)], vectorExport=export)
        steps["cancelAndRecover"].update(preCanceledPdfrxRenderReturnedNull=True, indexCancellationObserved=True,
                                         originalIndexPreserved=True, printingSubscriptionCanceledAfterPages=1,
                                         printingRecoveryPage=4, indexRecoveryPages=4, pdfrxRecovery=pixel_proof(1))
        steps["loadedModules"] = self.loaded
        steps["teardown"].update(viewerDetached=True, viewerNativeCloseCompleted=True, viewerLoadingCount=0)
        fixture_path = self.output / "bundle-runtime.pdf"
        steps["desktopLifecycle"] = json.loads((Path(__file__).resolve().parents[2] / "test/tool/perf_probe/fixtures/installed_pdf_desktop.json").read_text())
        steps["repeatedLifecycle"] = json.loads((Path(__file__).resolve().parents[2] / "test/tool/perf_probe/fixtures/installed_pdf_repeated.json").read_text())
        self.report = {
            "schemaVersion": 1, "status": "passed", "platform": "macos", "buildMode": "profile",
            "flutterVersion": "3.47.7", "commit": COMMIT, "pid": 173, "runId": "173-1234",
            "osVersion": "contract fixture", "frameworkPassed": True, "policyRestored": True,
            "physicalDeviceAcceptance": False, "errors": [], "contractErrors": [], "testFailures": [],
            "platformMatrix": {name: {"status": "passed" if name == "macos" else "notRun"}
                               for name in ("macos", "windows", "linux", "android", "ios")},
            "phases": [{"name": name, "status": "passed"} for name in subject.PHASES],
            "pdfRuntime": {"status": "passed", "platform": "macos", "physicalPrinter": "notRun",
                           "bundlePathsVerified": True, "ownedDocumentsRemaining": 0, "ownedTabsRemaining": 0,
                           "indexingActiveAfter": False, "steps": steps,
                           "fixture": {"path": str(fixture_path), "pages": 4, "bytes": fixture_path.stat().st_size,
                                       "sha256": subject.digest(fixture_path)}},
        }
        for name, size in (("bundle-runtime-print.png", (240, 320)), ("bundle-runtime-export.png", (480, 320))):
            (self.output / name).write_bytes(png(*size))
        self.save_images()

    def save_images(self):
        (self.output / "bundle-runtime-macos-images.json").write_text(
            json.dumps({k: v for k, v in self.loaded.items() if k not in ("status", "durationMs")}), encoding="utf-8")

    def accept(self, report=None):
        return subject.validate({"installedPluginProbe": self.report if report is None else report},
                                self.bundle, self.output, COMMIT)

    def test_complete_profile_scenario_rehashes_the_actual_bundle_and_artifacts(self):
        result = self.accept()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(len(result["bundledFiles"]), 2)
        self.assertEqual(result["pdfSteps"], [*subject.PDF_STEPS, "desktopLifecycle", "repeatedLifecycle"])
        self.assertEqual(len(result["pngArtifacts"]), 2)
        self.assertFalse(result["physicalDeviceAcceptance"])

    def test_statically_linked_pdfium_uses_the_app_executable_hash(self):
        for name in subject.SYMBOLS["pdfium"]:
            self.loaded["symbols"][name].update(image=str(self.executable), canonicalImage=str(self.executable))
        self.loaded["bundledFiles"] = self.loaded["bundledFiles"][:1]
        self.save_images()
        self.assertEqual(len(self.accept()["bundledFiles"]), 1)

    def test_missing_or_skipped_pdf_steps_cannot_pass(self):
        for name in (*subject.PDF_STEPS, "desktopLifecycle", "repeatedLifecycle"):
            for status in (None, "notRun", "failed"):
                with self.subTest(name=name, status=status):
                    report = copy.deepcopy(self.report)
                    if status is None:
                        del report["pdfRuntime"]["steps"][name]
                    else:
                        report["pdfRuntime"]["steps"][name]["status"] = status
                    with self.assertRaisesRegex(ValueError, "PDF step"):
                        self.accept(report)

    def test_pdf_runtime_not_run_is_not_a_successful_macos_scenario(self):
        for value in (None, {"status": "notRun"}, {"status": "failed"}):
            report = copy.deepcopy(self.report)
            report["pdfRuntime"] = value
            with self.assertRaisesRegex(ValueError, "PDF runtime"):
                self.accept(report)

    def test_wrong_platform_mode_commit_framework_or_unrun_matrix_is_rejected(self):
        for key, value in (("schemaVersion", True), ("platform", "linux"), ("buildMode", "debug"), ("commit", "b" * 40),
                           ("frameworkPassed", False), ("testFailures", ["native error"])):
            report = copy.deepcopy(self.report)
            report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.accept(report)
        self.report["platformMatrix"]["ios"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "Unexecuted"):
            self.accept()

    def test_app_phase_and_process_identity_must_be_complete(self):
        for mutate in (lambda r: r["phases"].pop(), lambda r: r["phases"].append(r["phases"][0]),
                       lambda r: r.update(runId="another-run")):
            report = copy.deepcopy(self.report)
            mutate(report)
            with self.assertRaises(ValueError):
                self.accept(report)

    def test_owned_resources_and_native_close_must_finish(self):
        for key, value in (("ownedDocumentsRemaining", 1), ("ownedTabsRemaining", False),
                           ("indexingActiveAfter", True)):
            report = copy.deepcopy(self.report)
            report["pdfRuntime"][key] = value
            with self.assertRaisesRegex(ValueError, "ownership"):
                self.accept(report)
        self.report["pdfRuntime"]["steps"]["reopen"]["previousNativeCloseCompleted"] = False
        with self.assertRaisesRegex(ValueError, "native teardown"):
            self.accept()

    def test_pixels_indexing_export_and_cancellation_are_required(self):
        for step, key, value in (("view", "visibleRenderState", "pending"),
                                 ("concurrentWork", "indexedPages", [0]),
                                 ("concurrentWork", "printingRasters", []),
                                 ("concurrentWork", "vectorExport", {}),
                                 ("cancelAndRecover", "printingRecoveryPage", 1)):
            report = copy.deepcopy(self.report)
            report["pdfRuntime"]["steps"][step][key] = value
            with self.subTest(step=step, key=key), self.assertRaises(ValueError):
                self.accept(report)

    def test_missing_symbol_and_fabricated_address_are_rejected(self):
        for name in (name for names in subject.SYMBOLS.values() for name in names):
            report = copy.deepcopy(self.report)
            del report["pdfRuntime"]["steps"]["loadedModules"]["symbols"][name]
            with self.assertRaisesRegex(ValueError, "loaded owner"):
                self.accept(report)
        self.loaded["symbols"]["FPDF_LoadDocument"]["address"] = "0x0"
        with self.assertRaisesRegex(ValueError, "native address"):
            self.accept()

    def test_printing_canonical_owner_cannot_hide_a_foreign_loaded_image(self):
        foreign = "/tmp/foreign-CoreGraphics"
        self.loaded["images"].append(foreign)
        self.loaded["symbols"]["CGContextDrawPDFPage"]["image"] = foreign
        self.save_images()
        with self.assertRaisesRegex(ValueError, "loaded Apple CoreGraphics framework"):
            self.accept()

    def test_cached_pdfium_and_non_system_printing_owner_are_rejected(self):
        foreign = self.root / "cached-pdfium"
        foreign.write_bytes(b"foreign image")
        for name in ("FPDF_LoadDocument", "CGContextDrawPDFPage"):
            report = copy.deepcopy(self.report)
            loaded = report["pdfRuntime"]["steps"]["loadedModules"]
            loaded["images"].append(str(foreign))
            loaded["symbols"][name].update(image=str(foreign), canonicalImage=str(foreign))
            with self.assertRaises(ValueError):
                self.accept(report)

    def test_printing_owner_must_match_the_loaded_core_graphics_image(self):
        foreign = str(self.root / "foreign-core-graphics")
        umbrella = "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"
        for image, canonical in ((foreign, CORE_GRAPHICS), (umbrella, umbrella)):
            loaded = copy.deepcopy(self.loaded)
            loaded["images"].append(image)
            loaded["symbols"]["CGContextDrawPDFPage"].update(image=image, canonicalImage=canonical)
            with self.subTest(image=image), self.assertRaisesRegex(ValueError, "CoreGraphics"):
                subject.verify_images(loaded, self.bundle, self.report["pid"])

    def test_symlink_escape_cannot_claim_the_bundle_as_its_owner(self):
        foreign = self.root / "foreign-binary"
        foreign.write_bytes(self.pdfium.read_bytes())
        self.pdfium.unlink()
        self.pdfium.symlink_to(foreign)
        with self.assertRaisesRegex(ValueError, "outside"):
            self.accept()

    def test_modified_binary_is_detected_even_when_length_is_unchanged(self):
        self.pdfium.write_bytes(b"x" * self.pdfium.stat().st_size)
        with self.assertRaisesRegex(ValueError, "differs"):
            self.accept()

    def test_missing_duplicate_or_stale_binary_hash_is_rejected(self):
        for change in ("missing", "duplicate", "hash"):
            report = copy.deepcopy(self.report)
            files = report["pdfRuntime"]["steps"]["loadedModules"]["bundledFiles"]
            if change == "missing":
                files.pop()
            elif change == "duplicate":
                files.append(files[0])
            else:
                files[0]["sha256"] = "e" * 64
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.accept(report)

    def test_missing_pdf_changed_output_or_wrong_png_dimensions_are_rejected(self):
        path = self.output / "bundle-runtime-export.pdf"
        original = path.read_bytes()
        path.write_bytes(b"x" * len(original))
        with self.assertRaisesRegex(ValueError, "PDF artifact"):
            self.accept()
        path.write_bytes(original)
        (self.output / "bundle-runtime-print.png").write_bytes(png(1, 1))
        with self.assertRaisesRegex(ValueError, "PNG artifact"):
            self.accept()

    def test_loaded_image_artifact_must_equal_the_native_report(self):
        (self.output / "bundle-runtime-macos-images.json").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "artifact differs"):
            self.accept()

    def test_foreign_pid_or_loader_override_cannot_pass(self):
        for key, value in (("pid", 174), ("configuredPdfrxModule", "/tmp/override")):
            report = copy.deepcopy(self.report)
            report["pdfRuntime"]["steps"]["loadedModules"][key] = value
            with self.assertRaises(ValueError):
                self.accept(report)

    def test_fresh_reports_and_exactly_one_built_app_are_required(self):
        reports = self.root / "host"
        reports.mkdir()
        with self.assertRaisesRegex(ValueError, "fresh driver report"):
            subject.validate_directory(reports, self.products, self.output, COMMIT)
        first = reports / "run-first"
        first.mkdir()
        (first / "report.json").write_text(json.dumps({"installedPluginProbe": self.report}), encoding="utf-8")
        self.assertEqual(subject.validate_directory(reports, self.products, self.output, COMMIT)["status"], "passed")
        second = reports / "run-second"
        second.mkdir()
        (second / "report.json").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "fresh driver report"):
            subject.validate_directory(reports, self.products, self.output, COMMIT)
        (self.products / "second.app").mkdir()
        with self.assertRaisesRegex(ValueError, "exactly one"):
            subject.profile_bundle(self.products)

    def test_profile_product_cannot_be_a_link_to_an_unrelated_app(self):
        real = self.root / "somewhere-else.app"
        self.bundle.rename(real)
        self.bundle.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "outside"):
            subject.profile_bundle(self.products)


if __name__ == "__main__":
    unittest.main()
