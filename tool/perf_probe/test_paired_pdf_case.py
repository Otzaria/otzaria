"""Input ownership and actual-run identity contracts for paired PDF cases."""

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tool.perf_probe import paired_pdf_case as cases


class PdfCaseSnapshotTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="paired PDF corpus ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.input = self.root / "user corpus"
        self.input.mkdir()
        self.pdf = self.input / "ספר PDF.pdf"
        self.pdf.write_bytes(b"external contract PDF bytes\n")
        self.manifest = self.input / "case.json"
        self.canonical = {"schemaVersion": 1, "source": {
            "kind": "external", "path": str(self.pdf), "pageCount": 17,
            "sha256": hashlib.sha256(self.pdf.read_bytes()).hexdigest()},
            "navigation": {"initialPage": 2, "forwardPage": 15, "backwardPage": 3, "zoomFactor": 2.5}}
        self.requested = copy.deepcopy(self.canonical)
        self.requested["source"]["path"] = self.pdf.name
        self.manifest.write_text(json.dumps(self.requested), encoding="utf-8")
        self.output = self.root / "owned run"
        self.output.mkdir()

    def canonicalize(self, input_case, output):
        # Schema/default behavior is covered by the existing Dart parser tests.
        self.assertEqual(input_case, self.manifest)
        output.write_text(json.dumps(self.canonical), encoding="utf-8")

    def prepare(self):
        return cases.PdfCaseSnapshot.prepare(self.manifest, self.output, self.canonicalize)

    def run_files(self, snapshot):
        directory = self.output / "baseline"
        directory.mkdir()
        (directory / "pdf-case.json").write_text(json.dumps(snapshot.case), encoding="utf-8")
        report = {"metadata": {"settings": {
            "pdfReaderCase": copy.deepcopy(snapshot.comparison), "pdfPageCount": 17}}}
        return directory, report

    def test_external_case_is_private_exact_and_leaves_user_inputs_untouched(self):
        originals = {path: path.read_bytes() for path in (self.pdf, self.manifest)}
        snapshot = self.prepare()
        private = Path(snapshot.case["source"]["path"])
        self.assertTrue(private.is_relative_to(self.output))
        self.assertNotEqual(private.resolve(), self.pdf.resolve())
        self.assertEqual(private.read_bytes(), originals[self.pdf])
        self.assertEqual(snapshot.case["navigation"], self.canonical["navigation"])
        self.assertEqual(snapshot.comparison["source"]["sha256"], self.canonical["source"]["sha256"])
        self.assertNotIn("path", snapshot.comparison["source"])
        self.assertEqual(snapshot.comparison["navigation"]["zoomPage"], 3)
        self.assertEqual(snapshot.comparison["navigation"]["zoomAnchor"], "pageCenter")
        for path, original in originals.items():
            self.assertEqual(path.read_bytes(), original)
        snapshot.verify_run(*self.run_files(snapshot))

    def test_a_hash_mismatch_cannot_become_a_usable_snapshot(self):
        self.canonical["source"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "source.sha256"):
            self.prepare()
        self.assertFalse((self.output / "pdf-case.json").exists())
        self.assertFalse((self.output / "corpus-source.pdf").exists())

    def test_failed_copy_removes_only_its_own_staging_file(self):
        private = self.output / "corpus-source.pdf"
        source = self.pdf.read_bytes()
        def failed_copy(path, *, target, maximum):
            target.write(source[:4])
            raise OSError("injected write failure")
        with patch.object(cases, "_capture_input", side_effect=failed_copy), \
                self.assertRaisesRegex(OSError, "injected write failure"):
            cases._capture(self.pdf, copy_to=private)
        self.assertFalse(private.exists())

        private.write_bytes(b"preexisting file")
        with self.assertRaises(FileExistsError):
            cases._capture(self.pdf, copy_to=private)
        self.assertEqual(private.read_bytes(), b"preexisting file")
        self.assertEqual(self.pdf.read_bytes(), source)

    def test_manifest_changed_while_dart_validates_is_rejected(self):
        def changed(input_case, output):
            self.canonicalize(input_case, output)
            self.manifest.write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "during validation"):
            cases.PdfCaseSnapshot.prepare(self.manifest, self.output, changed)
        self.assertFalse((self.output / "corpus-source.pdf").exists())

    def test_invalid_dart_case_never_reads_or_stages_the_external_pdf(self):
        def reject(*_):
            raise ValueError("canonical parser rejected invalid navigation")
        with self.assertRaisesRegex(ValueError, "invalid navigation"):
            cases.PdfCaseSnapshot.prepare(self.manifest, self.output, reject)
        self.assertFalse((self.output / "corpus-source.pdf").exists())

    def test_original_and_private_content_or_manifests_cannot_change_after_validation(self):
        for kind in ("input_manifest", "input_pdf", "private_pdf", "private_manifest"):
            with self.subTest(kind=kind):
                self.output = self.root / kind
                self.output.mkdir()
                snapshot = self.prepare()
                path = {"input_manifest": self.manifest, "input_pdf": self.pdf,
                        "private_pdf": self.output / "corpus-source.pdf", "private_manifest": snapshot.path}[kind]
                original = path.read_bytes()
                path.write_bytes(original + b"changed")
                with self.assertRaisesRegex(ValueError, "changed"):
                    snapshot.verify()
                path.write_bytes(original)
                # Restoring bytes does not erase evidence of an edit during a run.
                with self.assertRaisesRegex(ValueError, "changed"):
                    snapshot.verify()

    def test_a_source_edit_during_copy_is_rejected(self):
        fstat = cases.os.fstat
        calls = 0
        def edit_after_read(fd):
            nonlocal calls
            calls += 1
            if calls == 2:
                self.pdf.write_bytes(b"changed while the original descriptor was open")
            return fstat(fd)
        with patch.object(cases.os, "fstat", side_effect=edit_after_read), \
                self.assertRaisesRegex(ValueError, "changed while reading"):
            cases._capture(self.pdf, copy_to=self.output / "copy.pdf")

    def descriptor_stat(self, value, **changes):
        return SimpleNamespace(**({key: getattr(value, key) for key in (
            "st_mode", "st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")} | changes))

    def test_path_and_descriptor_ctime_can_have_different_windows_meanings(self):
        fstat = cases.os.fstat
        def changed_meaning(fd):
            value = fstat(fd)
            return self.descriptor_stat(value, st_ctime_ns=value.st_ctime_ns + 1000000)
        with patch.object(cases.os, "fstat", side_effect=changed_meaning):
            snapshot = self.prepare()
            snapshot.verify_run(*self.run_files(snapshot))

    def test_descriptor_change_time_still_detects_an_edit_during_read(self):
        fstat, calls = cases.os.fstat, 0
        def changed_after_read(fd):
            nonlocal calls
            calls += 1
            value = fstat(fd)
            return self.descriptor_stat(value, st_ctime_ns=value.st_ctime_ns + calls)
        with patch.object(cases.os, "fstat", side_effect=changed_after_read), \
                self.assertRaisesRegex(ValueError, "changed while reading"):
            cases._capture(self.pdf)

    def test_saved_descriptor_change_time_still_detects_a_later_edit(self):
        fstat, delta = cases.os.fstat, 1000000
        def change_time(fd):
            value = fstat(fd)
            return self.descriptor_stat(value, st_ctime_ns=value.st_ctime_ns + delta)
        with patch.object(cases.os, "fstat", side_effect=change_time):
            snapshot = self.prepare()
            delta += 1000000
            with self.assertRaisesRegex(ValueError, "changed"):
                snapshot.verify()

    def test_path_and_open_descriptor_must_identify_the_same_file(self):
        fstat = cases.os.fstat
        def different_file(fd):
            value = fstat(fd)
            return self.descriptor_stat(value, st_ino=value.st_ino + 1)
        with patch.object(cases.os, "fstat", side_effect=different_file), \
                self.assertRaisesRegex(ValueError, "changed while reading"):
            cases._capture(self.pdf)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "Requires POSIX named pipes")
    def test_input_replaced_by_fifo_during_open_is_rejected_without_blocking(self):
        result = subprocess.run(
            [sys.executable, "-B", "-c", """
import os
from pathlib import Path
import sys
from unittest.mock import patch

from tool.perf_probe.paired_pdf_case import _capture

source = Path(sys.argv[1])
original_stat = Path.stat

def swap_after_stat(path, *args, **kwargs):
    observed = original_stat(path, *args, **kwargs)
    if path == source:
        path.unlink()
        os.mkfifo(path)
    return observed

with patch.object(Path, "stat", swap_after_stat):
    try:
        _capture(source)
    except ValueError as error:
        if str(error) != "PDF case input changed while reading.":
            raise
    else:
        raise AssertionError("Accepted a FIFO in place of a regular input")
""", str(self.pdf)],
            capture_output=True, text=True, timeout=3,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_same_content_replacement_is_detected(self):
        snapshot = self.prepare()
        replacement = self.input / "replacement.pdf"
        replacement.write_bytes(self.pdf.read_bytes())
        replacement.replace(self.pdf)
        with self.assertRaisesRegex(ValueError, "changed"):
            snapshot.verify()

    def test_a_modified_private_copy_during_staging_is_rejected(self):
        original_capture = cases._capture
        def damaged(path, **kwargs):
            identity = original_capture(path, **kwargs)
            if kwargs.get("copy_to"):
                kwargs["copy_to"].write_bytes(b"damaged private PDF")
            return identity
        with patch.object(cases, "_capture", side_effect=damaged), \
                self.assertRaisesRegex(ValueError, "private PDF copy differs"):
            self.prepare()
        self.assertFalse((self.output / "corpus-source.pdf").exists())

    def test_two_agreeing_reports_still_must_match_the_requested_case(self):
        snapshot = self.prepare()
        directory, original = self.run_files(snapshot)
        for field, value in (("pageCount", 18), ("sha256", "f" * 64)):
            report = copy.deepcopy(original)
            report["metadata"]["settings"]["pdfReaderCase"]["source"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "requested canonical"):
                snapshot.verify_run(directory, report)
        for field, value in (("initialPage", 1), ("forwardPage", 14), ("zoomFactor", 2.0)):
            report = copy.deepcopy(original)
            report["metadata"]["settings"]["pdfReaderCase"]["navigation"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "requested canonical"):
                snapshot.verify_run(directory, report)

    def test_runner_copy_cannot_redirect_to_the_user_file_or_another_case(self):
        snapshot = self.prepare()
        directory, report = self.run_files(snapshot)
        actual = copy.deepcopy(snapshot.case)
        actual["source"]["path"] = str(self.pdf)
        (directory / "pdf-case.json").write_text(json.dumps(actual), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "requested canonical"):
            snapshot.verify_run(directory, report)

    def test_generated_cases_use_the_same_canonical_parser_without_a_pdf_copy(self):
        self.canonical["source"] = {"kind": "generated", "pageCount": 17, "mixedPageSizes": True}
        snapshot = self.prepare()
        self.assertFalse((self.output / "corpus-source.pdf").exists())
        self.assertEqual(snapshot.case["source"], self.canonical["source"])
        self.assertNotIn("sourceSha256", snapshot.receipt)
        snapshot.verify_run(*self.run_files(snapshot))

    def test_empty_missing_oversized_and_non_file_inputs_are_rejected(self):
        for path in (self.input / "missing.json", self.input):
            with self.subTest(path=path), self.assertRaises((OSError, ValueError)):
                cases.PdfCaseSnapshot.prepare(path, self.output, self.canonicalize)
        for value in (b"", b"x" * (64 * 1024 + 1)):
            self.manifest.write_bytes(value)
            with self.subTest(size=len(value)), self.assertRaises(ValueError):
                self.prepare()


if __name__ == "__main__":
    unittest.main()
