"""Negative evidence contracts; synthetic reports here are not native iOS runs."""

import contextlib
import copy
import io
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.perf_probe import installed_pdf_ios as subject
from tool.perf_probe import run_installed_pdf_ios as runner
from tool.perf_probe import test_installed_plugin_macos as fixtures
from tool.perf_probe.installed_pdf_evidence import PDF_STEPS, digest

COMMIT = "a" * 40
UDID = "A916179E-C19B-44CD-B606-25F904E6B567"


def macho(*, architecture="arm64", platform=7, executable=False):
    return (struct.pack("<8I", 0xFEEDFACF, subject.ARCHITECTURES[architecture][0], 0,
                        2 if executable else 6, 1, 24, 0, 0)
            + struct.pack("<6I", 0x32, 24, platform, 15 << 16, 26 << 16, 0)
            + b"contract fixture, not executable code")


class IosPdfEvidence(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.built = self.root / "build/ios/iphonesimulator/אוצריא.app"
        containers = self.root / "Simulator/Devices" / UDID / "data/Containers"
        self.installed = containers / "Bundle/Application/11111111-1111-1111-1111-111111111111/אוצריא.app"
        self.data = containers / "Data/Application/22222222-2222-2222-2222-222222222222"
        self.output = self.data / "tmp/otzaria-pdf-ios-test/output"
        self.output.mkdir(parents=True)
        (self.output.parent / "fixture").mkdir()
        self.runtime = self.root / "iOS 26.1.simruntime/Contents/Resources/RuntimeRoot"
        self.runtime.mkdir(parents=True)
        self.system = str(self.runtime / "System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        self.relative_pdfium = Path("Frameworks/PDFium.framework/PDFium")
        for bundle in (self.built, self.installed):
            (bundle / self.relative_pdfium).parent.mkdir(parents=True)
            (bundle / "Runner").write_bytes(macho(executable=True))
            (bundle / self.relative_pdfium).write_bytes(macho())
            with (bundle / "Info.plist").open("wb") as target:
                plistlib.dump({"CFBundleExecutable": "Runner", "CFBundleIdentifier": "org.sefaria.otzaria",
                              "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
                              "DTPlatformName": "iphonesimulator"}, target)
        self.receipt = {"schemaVersion": 1, "campaign": "contract-campaign", "udid": UDID,
                        "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
                        "runtimeVersion": "26.1", "runtimeBuild": "23B74", "runtimeRoot": str(self.runtime),
                        "model": "iPhone18,1", "stateBefore": "Booted", "stateAfter": "Booted",
                        "name": "otzaria-pdf-contract-campaign",
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}
        self.receipt.update(runtimeBefore=self.receipt["runtimeIdentifier"], runtimeAfter=self.receipt["runtimeIdentifier"])
        self.executable, self.pdfium = self.installed / "Runner", self.installed / self.relative_pdfium
        self.loaded = {"status": "passed", "durationMs": 1.0, "source": subject.SOURCE, "pid": 173,
                       "abi": "ios_arm64", "bundle": str(self.installed), "executable": str(self.executable),
                       "configuredPdfrxModule": None, "printingBackend": subject.PRINTING,
                       "simulatorEnvironmentSource": subject.ENVIRONMENT_SOURCE,
                       "simulatorEnvironmentAvailability": "collected",
                       "simulator": {"udid": UDID, "model": self.receipt["model"], "runtimeRoot": str(self.runtime)},
                       "images": [str(self.executable), str(self.pdfium), self.system],
                       "symbols": {name: {"image": str(self.pdfium) if role == "pdfium" else self.system,
                                          "canonicalImage": str(self.pdfium) if role == "pdfium" else self.system,
                                          "address": "0x10100", "imageBase": "0x10000"}
                                   for role, names in subject.SYMBOLS.items() for name in names}}
        self.hash_files([self.executable, self.pdfium])
        for name in ("bundle-runtime.pdf", "bundle-runtime-cancel.pdf", "bundle-runtime-export.pdf"):
            (self.output / name).write_bytes(b"%PDF-1.7\ncontract fixture\n")
        export_path = self.output / "bundle-runtime-export.pdf"
        export = {"sourcePages": [2, 3], "sheets": 1, "textPreserved": True, "rightToLeft": True,
                  "printingRasterVerified": True, "printingInkPixels": 200,
                  "bytes": export_path.stat().st_size, "sha256": digest(export_path)}
        steps = {name: {"status": "passed", "durationMs": 1.0} for name in PDF_STEPS}
        for name, page in (("view", 1), ("reopen", 2)):
            steps[name].update(visibleRenderState="ready", targetPage=page, targetCenterVisible=True,
                               raster=fixtures.pixel_proof(page))
        steps["reopen"].update(differentDocument=True, previousNativeCloseCompleted=True)
        steps["concurrentWork"].update(indexedPages=[0, 1, 2, 3], viewerTargetPage=4, targetCenterVisible=True,
                                       viewerRaster=fixtures.pixel_proof(4),
                                       printingRasters=[fixtures.pixel_proof(page) for page in range(1, 5)], vectorExport=export)
        steps["cancelAndRecover"].update(preCanceledPdfrxRenderReturnedNull=True, indexCancellationObserved=True,
                                         originalIndexPreserved=True, printingSubscriptionCanceledAfterPages=1,
                                         printingRecoveryPage=4, indexRecoveryPages=4, pdfrxRecovery=fixtures.pixel_proof(1))
        steps["loadedModules"] = self.loaded
        steps["teardown"].update(viewerDetached=True, viewerNativeCloseCompleted=True, viewerLoadingCount=0)
        fixture_path = self.output / "bundle-runtime.pdf"
        self.report = {"schemaVersion": 1, "scenario": "installed-pdf-ios-simulator-v1", "status": "passed",
                       "platform": "ios", "buildMode": "debug", "flutterVersion": "3.47.7", "commit": COMMIT,
                       "campaign": self.receipt["campaign"], "pid": 173, "runId": "173-1234", "osVersion": "iOS fixture",
                       "frameworkPassed": True, "physicalDeviceAcceptance": False, "physicalPrinter": "notRun",
                       "errors": [], "contractErrors": [], "testFailures": [], "appUnmounted": True,
                       "webViewScenario": {"status": "notRun"}, "bundleIdentifier": "org.sefaria.otzaria",
                       "bootstrap": {"status": "passed", "fixtureSha256": "synthetic-v4-pdf-cases:" + "b" * 64,
                                     "startupTimeline": {"revealMs": 100.0}},
                       "isolatedPaths": {"root": str(self.output.parent), "fixture": str(self.output.parent / "fixture"),
                                         "output": str(self.output)},
                       "pdfRuntime": {"status": "passed", "platform": "ios", "physicalPrinter": "notRun",
                                      "bundlePathsVerified": True, "ownedDocumentsRemaining": 0, "ownedTabsRemaining": 0,
                                      "indexingActiveAfter": False, "steps": steps,
                                      "fixture": {"path": str(fixture_path), "pages": 4, "bytes": fixture_path.stat().st_size,
                                                  "sha256": digest(fixture_path)}}}
        for name, size in (("bundle-runtime-print.png", (240, 320)), ("bundle-runtime-export.png", (480, 320))):
            (self.output / name).write_bytes(fixtures.png(*size))
        self.save_artifacts()

    def hash_files(self, paths):
        self.loaded["bundledFiles"] = [{"path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)} for path in paths]

    def save_artifacts(self):
        (self.output / "bundle-runtime-ios-images.json").write_text(json.dumps(
            {key: value for key, value in self.loaded.items() if key not in ("status", "durationMs")}), encoding="utf-8")
        (self.output / "installed-pdf-ios-report.json").write_text(json.dumps(self.report), encoding="utf-8")

    def accept(self, report=None, receipt=None):
        return subject.validate({"installedPdfIosProbe": self.report if report is None else report}, self.built, self.installed,
                                self.data, self.receipt if receipt is None else receipt, COMMIT)

    def test_complete_native_evidence_rehashes_built_installed_and_mapped_images(self):
        result = self.accept()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(len(result["bundledFiles"]), 2)
        self.assertTrue(all(entry["macho"]["platform"] == 7 for entry in result["bundledFiles"]))
        self.assertEqual(result["webViewScenario"], "notRun")
        self.assertFalse(result["physicalDeviceAcceptance"])
        self.assertEqual(result["abiEvidence"], {"source": subject.ABI_SOURCE,
                                               "abi": "ios_arm64", "architecture": "arm64"})

    def test_current_app_fixture_identity_is_accepted(self):
        source = (Path(__file__).resolve().parents[2]
                  / "integration_test/support/perf_fixture.dart").read_text(encoding="utf-8")
        versions = re.findall(r"^const perfFixtureVersion = '([^']+)';$", source, re.MULTILINE)
        self.assertEqual(len(versions), 1)
        self.report["bootstrap"]["fixtureSha256"] = versions[0] + ":" + "b" * 64
        self.save_artifacts()
        self.assertEqual(self.accept()["status"], "passed")

    def test_stale_unknown_and_malformed_fixture_identities_are_rejected(self):
        for identity in (None, "synthetic-v2:" + "b" * 64,
                         "synthetic-v999:" + "b" * 64,
                         "synthetic-v4-pdf-cases:" + "g" * 64,
                         "synthetic-v4-pdf-cases:" + "b" * 63,
                         "synthetic-v4-pdf-cases:" + "b" * 64 + "\n"):
            report = copy.deepcopy(self.report)
            report["bootstrap"]["fixtureSha256"] = identity
            with self.subTest(identity=identity), self.assertRaisesRegex(ValueError, "fixture identity"):
                self.accept(report)

    def test_valid_fixture_still_requires_successful_bootstrap_and_reveal(self):
        for change in (lambda record: record.update(status="failed"),
                       lambda record: record.pop("startupTimeline"),
                       lambda record: record["startupTimeline"].update(revealMs=None),
                       lambda record: record["startupTimeline"].update(revealMs=True)):
            report = copy.deepcopy(self.report)
            change(report["bootstrap"])
            with self.assertRaisesRegex(ValueError, "bootstrap did not reveal"):
                self.accept(report)


    def test_absent_environment_uses_owned_containers_and_native_image_proof(self):
        self.loaded.update(simulator={}, simulatorEnvironmentAvailability="unavailable")
        self.save_artifacts()
        result = self.accept()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["simulatorIdentityEvidence"]["udid"], UDID)
        self.assertEqual(result["simulatorIdentityEvidence"]["environmentAvailability"], "unavailable")
        self.assertTrue(all(entry["macho"]["platform"] == 7 for entry in result["bundledFiles"]))

    def test_partial_environment_is_allowed_but_available_values_cannot_conflict(self):
        self.loaded.update(simulator={"udid": UDID}, simulatorEnvironmentAvailability="partial")
        self.save_artifacts()
        self.assertEqual(self.accept()["status"], "passed")
        self.loaded["simulator"]["udid"] = "B916179E-C19B-44CD-B606-25F904E6B567"
        self.save_artifacts()
        with self.assertRaisesRegex(ValueError, "another Simulator"):
            self.accept()

    def test_optional_environment_requires_honest_source_availability_and_keys(self):
        for change in (
                lambda record: record.pop("simulatorEnvironmentSource"),
                lambda record: record.update(simulatorEnvironmentSource="host override"),
                lambda record: record.pop("simulatorEnvironmentAvailability"),
                lambda record: record.update(simulatorEnvironmentAvailability="unavailable"),
                lambda record: record["simulator"].update(unknown="value")):
            report = copy.deepcopy(self.report)
            change(report["pdfRuntime"]["steps"]["loadedModules"])
            with self.assertRaisesRegex(ValueError, "Simulator environment"):
                self.accept(report)

    def test_missing_environment_cannot_move_a_bundle_to_another_simulator(self):
        self.loaded.update(simulator={}, simulatorEnvironmentAvailability="unavailable")
        self.save_artifacts()
        receipt = {**self.receipt, "udid": "B916179E-C19B-44CD-B606-25F904E6B567"}
        with self.assertRaisesRegex(ValueError, "owned Simulator UDID"):
            self.accept(receipt=receipt)

    def test_missing_environment_cannot_accept_an_ios_device_binary(self):
        self.loaded.update(simulator={}, simulatorEnvironmentAvailability="unavailable")
        for bundle in (self.built, self.installed):
            (bundle / self.relative_pdfium).write_bytes(macho(platform=2))
        self.hash_files([self.executable, self.pdfium])
        self.save_artifacts()
        with self.assertRaisesRegex(ValueError, "iOS Simulator"):
            self.accept()

    def test_missing_environment_still_requires_the_selected_coregraphics_runtime(self):
        self.loaded.update(simulator={}, simulatorEnvironmentAvailability="unavailable")
        foreign = str(self.root / "other.simruntime/Contents/Resources/RuntimeRoot"
                      / "System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        self.loaded["images"].append(foreign)
        for symbol in subject.SYMBOLS["printing"]:
            self.loaded["symbols"][symbol].update(image=foreign, canonicalImage=foreign)
        self.save_artifacts()
        with self.assertRaisesRegex(ValueError, "selected Apple runtime"):
            self.accept()

    def test_app_and_data_containers_must_belong_to_the_same_owned_simulator(self):
        with self.assertRaisesRegex(ValueError, "container layout"):
            subject.verify_owned_container(self.installed.parent, self.receipt, "Bundle")
        with self.assertRaisesRegex(ValueError, "owned Simulator UDID"):
            subject.verify_owned_container(self.data, {**self.receipt, "udid": "other"}, "Data")

    def test_iOS_debug_dylib_and_static_pdfium_are_valid_owners(self):
        for relative in (Path("Runner.debug.dylib"), Path("Runner")):
            with self.subTest(relative=relative):
                if relative.name != "Runner":
                    for bundle in (self.built, self.installed):
                        (bundle / relative).write_bytes(macho())
                image = self.installed / relative
                if str(image) not in self.loaded["images"]:
                    self.loaded["images"].append(str(image))
                for name in subject.SYMBOLS["pdfium"]:
                    self.loaded["symbols"][name].update(image=str(image), canonicalImage=str(image))
                self.hash_files(sorted({self.executable, image}))
                self.save_artifacts()
                self.assertEqual(self.accept()["status"], "passed")

    def test_x64_simulator_abi_is_validated_against_real_binary_headers(self):
        self.loaded["abi"] = "ios_x64"
        for bundle in (self.built, self.installed):
            (bundle / "Runner").write_bytes(macho(architecture="x86_64", executable=True))
            (bundle / self.relative_pdfium).write_bytes(macho(architecture="x86_64"))
        self.hash_files([self.executable, self.pdfium])
        self.save_artifacts()
        result = self.accept()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["abiEvidence"]["architecture"], "x86_64")

    def test_running_abi_is_required_and_must_match_the_native_images(self):
        for abi in (None, "arm64", "macos_arm64", "ios_x64"):
            self.loaded["abi"] = abi
            self.save_artifacts()
            with self.subTest(abi=abi), self.assertRaisesRegex(ValueError, "running iOS ABI|Mach-O ABI"):
                self.accept()

    def test_shared_cache_system_coregraphics_does_not_require_an_unreadable_file(self):
        system = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        self.loaded["images"].append(system)
        for name in subject.SYMBOLS["printing"]:
            self.loaded["symbols"][name].update(image=system, canonicalImage=system)
        self.save_artifacts()
        self.assertEqual(self.accept()["status"], "passed")

    def test_missing_skipped_and_failed_pdf_steps_are_not_success(self):
        for name in PDF_STEPS:
            for status in (None, "notRun", "unsupported", "failed"):
                report = copy.deepcopy(self.report)
                if status is None:
                    del report["pdfRuntime"]["steps"][name]
                else:
                    report["pdfRuntime"]["steps"][name]["status"] = status
                with self.subTest(name=name, status=status), self.assertRaisesRegex(ValueError, "PDF step"):
                    self.accept(report)

    def test_simulator_report_cannot_claim_profile_physical_or_webview_acceptance(self):
        for key, value in (("buildMode", "profile"), ("physicalDeviceAcceptance", True), ("physicalPrinter", "passed"),
                           ("frameworkPassed", False), ("commit", "c" * 40), ("campaign", "stale"), ("appUnmounted", False)):
            report = copy.deepcopy(self.report)
            report[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.accept(report)
        report = copy.deepcopy(self.report)
        report["webViewScenario"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "WKWebView"):
            self.accept(report)

    def test_owned_runtime_udid_model_and_abi_must_match_app_observation(self):
        for field, value in (("udid", "B916179E-C19B-44CD-B606-25F904E6B567"), ("model", "iPhone17,1"),
                             ("runtimeRoot", str(self.root / "other.simruntime/Contents/Resources/RuntimeRoot"))):
            report = copy.deepcopy(self.report)
            report["pdfRuntime"]["steps"]["loadedModules"]["simulator"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "another Simulator"):
                self.accept(report)
        for field, value in (("stateAfter", "Shutdown"), ("runtimeAfter", "another")):
            receipt = copy.deepcopy(self.receipt)
            receipt[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.accept(receipt=receipt)

    def test_built_installed_and_reported_hashes_cannot_diverge(self):
        original = self.pdfium.read_bytes()
        self.pdfium.write_bytes(original[:-1] + b"X")
        with self.assertRaisesRegex(ValueError, "bytes do not match"):
            self.accept()
        self.pdfium.write_bytes(original)
        (self.built / self.relative_pdfium).write_bytes(original[:-1] + b"Y")
        with self.assertRaisesRegex(ValueError, "bytes do not match"):
            self.accept()

    def test_wrong_native_platform_or_architecture_is_rejected_even_with_matching_hashes(self):
        for content in (macho(platform=1), macho(platform=2), macho(architecture="x86_64")):
            for bundle in (self.built, self.installed):
                (bundle / self.relative_pdfium).write_bytes(content)
            self.hash_files([self.executable, self.pdfium])
            self.save_artifacts()
            with self.assertRaisesRegex(ValueError, "Mach-O"):
                self.accept()

    def test_another_app_and_foreign_symbol_owners_are_rejected(self):
        for name in ("FPDF_LoadDocument", "CGContextDrawPDFPage"):
            report = copy.deepcopy(self.report)
            record = report["pdfRuntime"]["steps"]["loadedModules"]
            foreign = self.root / "foreign-image"
            foreign.write_bytes(macho())
            record["images"].append(str(foreign))
            record["symbols"][name].update(image=str(foreign), canonicalImage=str(foreign))
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.accept(report)
        report = copy.deepcopy(self.report)
        report["bundleIdentifier"] = "another.app"
        with self.assertRaisesRegex(ValueError, "another application"):
            self.accept(report)

    def test_missing_and_fabricated_symbol_evidence_is_rejected(self):
        for name in (name for names in subject.SYMBOLS.values() for name in names):
            report = copy.deepcopy(self.report)
            del report["pdfRuntime"]["steps"]["loadedModules"]["symbols"][name]
            with self.assertRaisesRegex(ValueError, "loaded owner"):
                self.accept(report)
        self.loaded["symbols"]["FPDF_LoadDocument"]["address"] = "0x0"
        self.save_artifacts()
        with self.assertRaisesRegex(ValueError, "native symbol"):
            self.accept()

    def test_printing_canonical_owner_cannot_hide_a_foreign_loaded_image(self):
        foreign = "/tmp/foreign-CoreGraphics"
        self.loaded["images"].append(foreign)
        self.loaded["symbols"]["CGContextDrawPDFPage"]["image"] = foreign
        self.save_artifacts()
        with self.assertRaisesRegex(ValueError, "selected Apple runtime"):
            self.accept()

    def test_unrelated_system_framework_cannot_claim_core_graphics_symbols(self):
        other = str(self.runtime / "System/Library/Frameworks/Foundation.framework/Foundation")
        self.loaded["images"].append(other)
        self.loaded["symbols"]["CGContextDrawPDFPage"].update(image=other, canonicalImage=other)
        self.save_artifacts()
        with self.assertRaisesRegex(ValueError, "selected Apple runtime"):
            self.accept()

    def test_duplicate_missing_and_foreign_binary_hashes_are_rejected(self):
        for action in (lambda files: files.pop(), lambda files: files.append(files[0]),
                       lambda files: files[0].update(path="/foreign/image")):
            report = copy.deepcopy(self.report)
            action(report["pdfRuntime"]["steps"]["loadedModules"]["bundledFiles"])
            with self.assertRaises(ValueError):
                self.accept(report)

    def test_symlink_escape_cannot_claim_the_built_or_installed_app(self):
        foreign = self.root / "cached-pdfium"
        foreign.write_bytes(self.pdfium.read_bytes())
        self.pdfium.unlink()
        self.pdfium.symlink_to(foreign)
        with self.assertRaisesRegex(ValueError, "outside"):
            self.accept()

    def test_native_outputs_pixels_indexing_cancellation_and_teardown_are_required(self):
        mutations = [lambda pdf: pdf.update(ownedDocumentsRemaining=1),
                     lambda pdf: pdf["steps"]["teardown"].update(viewerNativeCloseCompleted=False),
                     lambda pdf: pdf["steps"]["view"].update(visibleRenderState="pending"),
                     lambda pdf: pdf["steps"]["concurrentWork"].update(indexedPages=[0]),
                     lambda pdf: pdf["steps"]["concurrentWork"].update(printingRasters=[]),
                     lambda pdf: pdf["steps"]["cancelAndRecover"].update(indexRecoveryPages=0)]
        for change in mutations:
            report = copy.deepcopy(self.report)
            change(report["pdfRuntime"])
            with self.assertRaises(ValueError):
                self.accept(report)

    def test_changed_pdf_png_or_completion_artifacts_are_rejected(self):
        for name in ("bundle-runtime.pdf", "bundle-runtime-export.png", "installed-pdf-ios-report.json",
                     "bundle-runtime-ios-images.json"):
            path = self.output / name
            original = path.read_bytes()
            path.write_bytes(b"{}")
            try:
                with self.subTest(name=name), self.assertRaises(ValueError):
                    self.accept()
            finally:
                path.write_bytes(original)

    def test_output_cannot_escape_its_owned_data_container(self):
        report = copy.deepcopy(self.report)
        report["isolatedPaths"]["root"] = str(self.root)
        with self.assertRaisesRegex(ValueError, "owned app data"):
            self.accept(report)
        (self.output / "foreign-link").symlink_to(self.executable)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.accept()

    def test_nonzero_driver_exit_is_failure_even_when_a_report_claims_success(self):
        evidence = self.root / "evidence"
        host = evidence / "host/run-one"
        host.mkdir(parents=True)
        (host / "report.json").write_text(json.dumps({"installedPdfIosProbe": self.report}), encoding="utf-8")
        devices = {self.receipt["runtimeIdentifier"]: [{"udid": UDID, "name": self.receipt["name"],
                    "state": "Booted", "deviceTypeIdentifier": self.receipt["deviceTypeIdentifier"]}]}
        def fake(*args, **kwargs):
            if args[:1] == ("get_app_container",):
                return str(self.installed if args[-1] == "app" else self.data)
            return json.dumps({"devices": devices})
        previous = Path.cwd()
        try:
            os.chdir(self.root)
            with patch.object(runner, "simctl", side_effect=fake), self.assertRaisesRegex(ValueError, "driver failed"):
                runner.collect_and_validate(evidence, self.receipt, COMMIT, 1)
        finally:
            os.chdir(previous)
        self.assertTrue((evidence / "device-output/installed-pdf-ios-report.json").is_file())


class IosMachOContracts(unittest.TestCase):
    def test_universal_binary_selects_exactly_one_matching_simulator_slice(self):
        arm, intel = macho(), macho(architecture="x86_64")
        offset1, offset2 = 128, 128 + len(arm)
        header = struct.pack(">II", 0xCAFEBABE, 2)
        header += struct.pack(">IIIII", 0x0100000C, 0, offset1, len(arm), 0)
        header += struct.pack(">IIIII", 0x01000007, 0, offset2, len(intel), 0)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "PDFium"
            path.write_bytes(header.ljust(offset1, b"\0") + arm + intel)
            for architecture in subject.ARCHITECTURES:
                proof = subject.macho_simulator_image(path, architecture, executable=False)
                self.assertEqual(proof["architecture"], architecture)

    def test_truncated_wrong_kind_and_invalid_command_bounds_fail_closed(self):
        invalid = [b"", macho()[:12], macho(executable=True), macho(platform=2)]
        header = bytearray(macho())
        struct.pack_into("<I", header, 20, 5 * 1024 * 1024)
        invalid.append(header)
        command = bytearray(macho())
        struct.pack_into("<I", command, 36, 0)
        invalid.append(command)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "PDFium"
            for content in invalid:
                path.write_bytes(content)
                with self.assertRaises(ValueError):
                    subject.macho_simulator_image(path, "arm64", executable=False)


class OwnedSimulatorContracts(unittest.TestCase):
    def receipt(self):
        return {"udid": UDID, "campaign": "contract", "name": "otzaria-pdf-contract",
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}

    def device(self, receipt):
        return {"udid": receipt["udid"], "name": receipt["name"], "state": "Booted",
                "deviceTypeIdentifier": receipt["deviceTypeIdentifier"]}


    def test_driver_keeps_the_owned_install_for_post_run_binary_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = runner.subprocess.CompletedProcess([], 0)
            with patch.object(runner.subprocess, "run", return_value=result) as process:
                self.assertEqual(runner.run_driver(root, self.receipt(), COMMIT), 0)
            arguments = process.call_args.args[0]
            self.assertEqual(arguments[arguments.index("-d") + 1], UDID)
            self.assertIn("--verbose", arguments)
            self.assertIn("--keep-app-running", arguments)
            self.assertNotIn("--use-existing-app", arguments)
            self.assertEqual(json.loads((root / "driver-command.json").read_text()), arguments)

    def test_failed_driver_keeps_its_error_when_no_app_bundle_was_built(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"
            with patch.object(runner, "command", return_value=COMMIT), \
                    patch.object(runner, "create_simulator", return_value=self.receipt()), \
                    patch.object(runner, "boot_simulator"), \
                    patch.object(runner, "run_driver", return_value=1), \
                    patch.object(runner, "collect_and_validate", side_effect=FileNotFoundError("missing bundle")) as collect, \
                    patch.object(runner, "preserve_partial_output") as preserve, \
                    patch.object(runner, "cleanup_simulator") as cleanup:
                with self.assertRaisesRegex(ValueError, r"driver failed.*exit=1.*run.log"):
                    runner.run(evidence, COMMIT)
                collect.assert_not_called()
                preserve.assert_called_once()
                cleanup.assert_called_once()
            self.assertTrue((evidence / "simulator.json").is_file())

    def test_boot_does_not_require_unix_executables_in_the_ios_runtime(self):
        receipt = self.receipt()
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "iOS.simruntime"
            runtime = bundle / "Contents/Resources/RuntimeRoot"
            runtime.mkdir(parents=True)
            receipt["runtimeBundle"] = str(bundle)
            replies = {
                ("boot", UDID): "",
                ("bootstatus", UDID, "-b"): "",
                ("list", "-j", "devices"): json.dumps({"devices": {
                    receipt["runtimeIdentifier"]: [self.device(receipt)]}}),
                ("getenv", UDID, "SIMULATOR_ROOT"): str(runtime),
                ("getenv", UDID, "SIMULATOR_MODEL_IDENTIFIER"): "iPhone18,1",
            }

            def native_call(*arguments, **_):
                if arguments not in replies:
                    raise RuntimeError(f"Simulator executable is unavailable: {arguments}")
                return replies[arguments]

            with patch.object(runner, "simctl", side_effect=native_call):
                runner.boot_simulator(receipt)
            self.assertEqual(receipt["runtimeRoot"], str(runtime.resolve()))
            self.assertEqual(receipt["model"], "iPhone18,1")
            self.assertEqual(receipt["stateBefore"], "Booted")
            self.assertNotIn("architecture", receipt)

    def test_boot_status_timeout_restarts_the_owned_simulator_once(self):
        receipt = self.receipt()
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "iOS.simruntime"
            runtime = bundle / "Contents/Resources/RuntimeRoot"
            runtime.mkdir(parents=True)
            receipt["runtimeBundle"] = str(bundle)
            calls = []

            def native_call(*arguments, **_):
                calls.append(arguments[0])
                if arguments[0] == "bootstatus" and calls.count("bootstatus") == 1:
                    raise subprocess.TimeoutExpired(["xcrun", "simctl", *arguments], 300)
                if arguments[0] == "list":
                    device = self.device(receipt)
                    if calls.count("list") == 1:
                        device["state"] = initial_state
                    return json.dumps({"devices": {receipt["runtimeIdentifier"]: [device]}})
                return str(runtime) if arguments[-1] == "SIMULATOR_ROOT" else ""

            for initial_state, shutdown_calls in (("Booted", ["shutdown"]), ("Shutdown", [])):
                with self.subTest(initial_state=initial_state), \
                        patch.object(runner, "simctl", side_effect=native_call), \
                        contextlib.redirect_stderr(io.StringIO()):
                    calls.clear()
                    runner.boot_simulator(receipt)
                    self.assertEqual(calls, ["boot", "bootstatus", "list", *shutdown_calls,
                                             "boot", "bootstatus", "list", "getenv", "getenv"])
                    self.assertEqual(receipt["stateBefore"], "Booted")

    def test_cleanup_rejects_another_device_before_any_mutation(self):
        receipt = self.receipt()
        device = self.device(receipt)
        device["name"] = "user device"
        with patch.object(runner, "simctl", return_value=json.dumps({"devices": {
                receipt["runtimeIdentifier"]: [device]}})) as calls:
            with self.assertRaisesRegex(ValueError, "identity changed"):
                runner.cleanup_simulator(receipt)
            self.assertEqual(calls.call_count, 1)

    def test_receipt_write_failure_still_cleans_the_created_simulator(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"
            original_save = runner.save
            def failing_receipt(path, value):
                if path.name == "simulator.json":
                    raise OSError("receipt write failed")
                original_save(path, value)
            with patch.object(runner, "command", return_value=COMMIT), \
                    patch.object(runner, "create_simulator", return_value=self.receipt()), \
                    patch.object(runner, "preserve_partial_output"), \
                    patch.object(runner, "cleanup_simulator") as cleanup, \
                    patch.object(runner, "save", side_effect=failing_receipt):
                with self.assertRaisesRegex(OSError, "receipt write failed"):
                    runner.run(evidence, COMMIT)
                cleanup.assert_called_once()

    def test_cleanup_deletes_only_the_owned_device_and_verifies_removal(self):
        receipt = self.receipt()
        device = self.device(receipt)
        other = {**device, "udid": "B916179E-C19B-44CD-B606-25F904E6B567", "name": "user device"}
        with patch.object(runner, "simctl", side_effect=[
            json.dumps({"devices": {receipt["runtimeIdentifier"]: [device, other]}}), "", "",
            json.dumps({"devices": {receipt["runtimeIdentifier"]: [other]}}),
        ]) as calls:
            runner.cleanup_simulator(receipt)
            self.assertEqual(calls.call_args_list[1].args, ("shutdown", UDID))
            self.assertEqual(calls.call_args_list[2].args, ("delete", UDID))
        self.assertEqual(receipt["cleanup"], "deletedOwnedSimulator")

    def test_repeated_cleanup_preserves_verified_deletion_receipt(self):
        receipt = self.receipt()
        receipt["cleanup"] = "deletedOwnedSimulator"
        with patch.object(runner, "simctl", return_value='{"devices": {}}') as calls:
            runner.cleanup_simulator(receipt)
        calls.assert_called_once_with("list", "-j", "devices")
        self.assertEqual(receipt["cleanup"], "deletedOwnedSimulator")

    def test_selection_requires_available_compatible_ios_runtime(self):
        runtimes = [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1", "version": "26.1", "isAvailable": True}]
        device = {**self.device(self.receipt()), "isAvailable": True}
        self.assertEqual(runner.choose_simulator(runtimes, {runtimes[0]["identifier"]: [device]})[0], runtimes[0])
        for devices in ({}, {runtimes[0]["identifier"]: [{**device, "isAvailable": False}]}):
            with self.assertRaisesRegex(ValueError, "No available"):
                runner.choose_simulator(runtimes, devices)


if __name__ == "__main__":
    unittest.main()
