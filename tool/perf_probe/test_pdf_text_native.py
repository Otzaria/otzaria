import copy
import hashlib
import json
from pathlib import Path
import subprocess
import struct
import tempfile
import unittest
from unittest.mock import patch

from . import run_pdf_text_profile as probe


class SourceReceiptTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-q")
        for name in probe.SOURCE_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name + "\n", encoding="utf-8")
        self.git("add", ".")
        self.git("-c", "user.name=Probe Test", "-c", "user.email=probe@example.invalid", "commit", "-qm", "fixture")

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.root, check=True, capture_output=True, text=True).stdout.strip()

    def test_all_measured_blobs_are_tied_to_the_real_commit(self):
        receipt = probe.source_receipt(self.root)
        self.assertEqual(receipt["commit"], self.git("rev-parse", "HEAD"))
        self.assertEqual(set(receipt["files"]), set(probe.SOURCE_FILES))
        self.assertEqual(receipt, probe.source_receipt(self.root))

    def test_shallow_checkout_records_the_actual_commit_parent(self):
        parent = self.git("rev-parse", "HEAD")
        self.git("-c", "user.name=Probe Test", "-c", "user.email=probe@example.invalid",
                 "commit", "--allow-empty", "-qm", "second commit")
        with tempfile.TemporaryDirectory() as temporary:
            subprocess.run(["git", "clone", "-q", "--depth=1", self.root.as_uri(), temporary], check=True)
            self.assertEqual(probe.source_receipt(Path(temporary))["parents"], [parent])

    def test_dirty_measurement_source_is_rejected(self):
        (self.root / probe.SOURCE_FILES[4]).write_text("changed")
        with self.assertRaisesRegex(ValueError, "dirty"):
            probe.source_receipt(self.root)

    def test_assume_unchanged_cannot_hide_a_different_blob(self):
        name = probe.SOURCE_FILES[4]
        self.git("update-index", "--assume-unchanged", name)
        (self.root / name).write_text("hidden modification")
        with self.assertRaisesRegex(ValueError, "HEAD blob"):
            probe.source_receipt(self.root)

    def test_missing_measured_input_cannot_be_an_empty_receipt(self):
        name = probe.SOURCE_FILES[4]
        self.git("rm", name)
        self.git("-c", "user.name=Probe Test", "-c", "user.email=probe@example.invalid", "commit", "-qm", "remove input")
        with self.assertRaisesRegex(ValueError, "missing from HEAD"):
            probe.source_receipt(self.root)

    def test_compiler_depfile_cannot_import_unrecorded_app_source(self):
        unknown = self.root / "lib/unknown.dart"
        unknown.write_text("void extra() {}")
        depfile = self.root / "compile.d"
        depfile.write_text(f"out: {unknown}\n")
        with self.assertRaisesRegex(ValueError, "Unrecorded repository"):
            probe.compiler_dependencies(depfile, self.root)

    def test_depfile_records_space_escaped_paths_and_detects_changes(self):
        entry = self.root / "tool/perf_probe/run_pdf_text_profile.dart"
        outside = Path(self.temporary.name + "-external space.dart")
        self.addCleanup(lambda: outside.unlink(missing_ok=True))
        outside.write_text("void helper() {}")
        depfile = self.root / "compile.d"
        escaped = str(outside).replace(" ", "\\ ")
        depfile.write_text(f"out: {entry} {escaped}\n")
        before = probe.compiler_dependencies(depfile, self.root)
        outside.write_text("void changed() {}")
        self.assertNotEqual(before, probe.compiler_dependencies(depfile, self.root))

    def test_depfile_resolves_a_symlinked_repository_root(self):
        entry = self.root / "tool/perf_probe/run_pdf_text_profile.dart"
        depfile = self.root / "compile.d"
        depfile.write_text(f"out: {entry.resolve()}\n")
        with tempfile.TemporaryDirectory() as temporary:
            alias = Path(temporary) / "repo"
            alias.symlink_to(self.root, target_is_directory=True)
            self.assertEqual(
                probe.compiler_dependencies(depfile, alias),
                {str(entry.resolve()): probe.digest(entry)},
            )


class NativeReportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        corpus = b"host-contract-fixture-not-a-native-PDF"
        (self.output / "corpus.pdf").write_bytes(corpus)
        corpus_hash = hashlib.sha256(corpus).hexdigest()
        self.patched_hash = patch.object(probe, "CORPUS_SHA256", corpus_hash)
        self.patched_hash.start()
        self.addCleanup(self.patched_hash.stop)
        pages = []
        (self.output / "rasters").mkdir()
        for number in range(1, 33):
            kind = probe.CORPUS_KINDS[(number - 1) % 8]
            page = {"pageNumber": number, "kind": kind, "rotationDegrees": 90 if kind == "rotate_90" else 270 if kind == "rotate_270" else 0,
                    "textSha256": hashlib.sha256(str(number).encode()).hexdigest(), "characters": 100,
                    "niqqudMarks": 60 if kind == "niqqud" else 0}
            if number <= 8:
                png = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + struct.pack(">II", 16, 16)
                name = f"{number:02d}-{kind}.png"
                (self.output / "rasters" / name).write_bytes(png)
                page["raster"] = {"darkBodyPixels": 101, "file": name, "width": 16, "height": 16, "bytes": 1024,
                                  "pngSha256": hashlib.sha256(png).hexdigest()}
            pages.append(page)
        rows = [
            {"iteration": iteration, "phase": phase, "pageNumber": page,
             "rawLoadCalls": 1, "formatRawCalls": int(phase == "pipeline"),
             "warmup": iteration == 0, "parity": True,
             "textSha256": pages[page - 1]["textSha256"], "textCharacters": 100}
            for iteration in range(2)
            for phase in ("pipeline", "cacheFirst", "cacheRepeat")
            for page in range(1, 33)
        ]
        self.report = {
            "protocolVersion": 1, "status": "passed", "component": "pdfrx-public-text-pipeline",
            "executionMode": "dart-aot", "dartVersion": "3.13.5 (stable) fixture",
            "pdfiumSha256": probe.PDFIUM_SHA256,
            "uiLatencyCollected": False, "nativeTransferSeparated": False, "osCacheCleared": False,
            "corpus": {"version": "otzaria-pdf-text-v2", "pageCount": 32, "bytes": len(corpus), "sha256": corpus_hash, "fontSha256": probe.FONT_SHA256},
            "corpusValidation": {"status": "passed", "pages": pages, "pointedTextObservation": copy.deepcopy(probe.POINTED_TEXT_OBSERVATION)},
            "profile": {
                "protocolVersion": 1, "status": "passed", "timeUnit": "microseconds",
                "rawLoadScope": "native-normalization-scheduling-transfer",
                "cacheState": "structured-cache-reset-per-iteration",
                "configuration": {"warmup": 1, "repetitions": 1, "pageNumbers": list(range(1, 33)), "normalizeHebrewText": True, "decodeLegacyHebrewText": True},
                "observations": rows,
            },
        }
        self.write_rows()

    def write_rows(self):
        (self.output / "observations.jsonl").write_text("".join(json.dumps(row) + "\n" for row in self.report["profile"]["observations"]))

    def validate(self, report=None):
        probe.validate_native_report(report or self.report, self.output, warmup=1, repetitions=1)

    def test_complete_stream_and_component_metadata_are_accepted(self):
        self.validate()

    def test_no_ui_cold_cache_or_transfer_claim_is_accepted(self):
        for field in ("uiLatencyCollected", "nativeTransferSeparated", "osCacheCleared"):
            with self.subTest(field=field):
                changed = copy.deepcopy(self.report)
                changed[field] = True
                with self.assertRaisesRegex(ValueError, "scope"):
                    self.validate(changed)

    def test_jit_cannot_be_presented_as_aot(self):
        self.report["executionMode"] = "dart-jit-validation"
        with self.assertRaisesRegex(ValueError, "AOT"):
            self.validate()

    def test_wrong_pdfium_cannot_be_presented_as_pinned_native(self):
        self.report["pdfiumSha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "library identity"):
            self.validate()

    def test_missing_observation_or_duplicate_is_rejected(self):
        rows = self.report["profile"]["observations"]
        rows[-1] = copy.deepcopy(rows[0])
        self.write_rows()
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.validate()

    def test_repeated_cache_pass_requires_actual_extraction(self):
        self.report["profile"]["observations"][-1]["rawLoadCalls"] = 0
        self.write_rows()
        with self.assertRaisesRegex(ValueError, "extraction"):
            self.validate()

    def test_partial_stream_is_not_a_completed_report(self):
        with (self.output / "observations.jsonl").open("a") as output:
            output.write('{}\n')
        with self.assertRaisesRegex(ValueError, "stream"):
            self.validate()

    def test_blank_body_and_failure_records_cannot_pass(self):
        self.report["corpusValidation"]["pages"][0]["raster"]["darkBodyPixels"] = 0
        with self.assertRaisesRegex(ValueError, "Hebrew body"):
            self.validate()
        self.report["corpusValidation"]["pages"][0]["raster"]["darkBodyPixels"] = 101
        (self.output / "failure.json").write_text('{}')
        with self.assertRaisesRegex(ValueError, "failure record"):
            self.validate()

    def test_page_number_kind_rotation_and_niqqud_must_match_the_corpus(self):
        for field, changed_value in (("pageNumber", 2), ("kind", "niqqud"), ("rotationDegrees", 270), ("niqqudMarks", 60)):
            with self.subTest(field=field):
                changed = copy.deepcopy(self.report)
                changed["corpusValidation"]["pages"][0][field] = changed_value
                with self.assertRaisesRegex(ValueError, "Corpus"):
                    self.validate(changed)

    def test_pointed_text_limitation_cannot_be_relabelled_as_successful_search(self):
        self.report["corpusValidation"]["pointedTextObservation"]["matchesPerPage"] = 12
        with self.assertRaisesRegex(ValueError, "pointed-text"):
            self.validate()

    def test_pipeline_text_is_tied_to_the_validated_native_corpus(self):
        self.report["profile"]["observations"][0]["textSha256"] = "0" * 64
        self.write_rows()
        with self.assertRaisesRegex(ValueError, "Measured text"):
            self.validate()

    def test_altered_png_cannot_use_the_old_native_receipt(self):
        (self.output / "rasters/01-hebrew.png").write_bytes(b"other image")
        with self.assertRaisesRegex(ValueError, "PNG differs"):
            self.validate()


class PackageResolutionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.config = self.repo / ".dart_tool/package_config.json"
        self.graph = self.repo / ".dart_tool/package_graph.json"
        self.config.parent.mkdir()
        self.config.write_text('{"configVersion":2,"packages":[]}')
        self.graph.write_text('{"configVersion":1,"roots":["fixture"],"packages":[]}')

    def test_generated_pair_is_recorded_and_graph_changes_are_visible(self):
        before = probe.package_resolution_receipt(self.repo, self.config)
        self.assertEqual(before["packageConfigSha256"], probe.digest(self.config))
        self.graph.write_text('{"configVersion":1,"roots":["changed"],"packages":[]}')
        self.assertNotEqual(before, probe.package_resolution_receipt(self.repo, self.config))

    def test_missing_graph_fails_before_silent_pub_resolution(self):
        self.graph.unlink()
        with self.assertRaisesRegex(ValueError, "Refusing implicit"):
            probe.package_resolution_receipt(self.repo, self.config)

    def test_external_config_cannot_mask_the_sdk_discovery_pair(self):
        alternate = self.repo / "alternate.json"
        alternate.write_bytes(self.config.read_bytes())
        with self.assertRaisesRegex(ValueError, "repository package config"):
            probe.package_resolution_receipt(self.repo, alternate)

    def test_nested_pair_cannot_change_the_sdk_discovery_root(self):
        nested = self.repo / "tool/perf_probe/.dart_tool"
        nested.mkdir(parents=True)
        (nested / "package_config.json").write_bytes(self.config.read_bytes())
        (nested / "package_graph.json").write_bytes(self.graph.read_bytes())
        with self.assertRaisesRegex(ValueError, "Nested Dart"):
            probe.package_resolution_receipt(self.repo, self.config)


class SdkReceiptTest(unittest.TestCase):
    def test_direct_dart_does_not_invent_a_flutter_observation(self):
        receipt = probe.sdk_receipt("Dart SDK version: 3.13.5 (stable)")
        self.assertIsNone(receipt["flutter"])

    def test_wrong_dart_version_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Dart SDK"):
            probe.sdk_receipt("Dart SDK version: 3.13.50 (stable)")

    def test_exact_flutter_framework_and_engine_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "flutter.json"
            value = {"frameworkVersion": "3.47.7", "dartSdkVersion": "3.13.5", "frameworkRevision": probe.FRAMEWORK_REVISION, "engineRevision": probe.ENGINE_REVISION}
            path.write_text(json.dumps(value))
            self.assertEqual(probe.sdk_receipt("Dart SDK version: 3.13.5 (stable)", path)["flutter"], value)
            value["engineRevision"] = "0" * 40
            path.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, "revision"):
                probe.sdk_receipt("Dart SDK version: 3.13.5 (stable)", path)


class CommandLogTest(unittest.TestCase):
    def test_timeout_keeps_partial_output_and_original_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            error = subprocess.TimeoutExpired(["compiler"], 1, output=b"native compilation reached\n")
            with patch.object(probe.subprocess, "run", side_effect=error):
                with self.assertRaises(subprocess.TimeoutExpired) as raised:
                    probe.run(["compiler"], root, log=root / "compile.log", timeout=1)
            self.assertIs(raised.exception, error)
            self.assertEqual((root / "compile.log").read_bytes(), error.output)


if __name__ == "__main__":
    unittest.main()
