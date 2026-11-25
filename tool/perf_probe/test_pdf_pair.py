from __future__ import annotations

import argparse
import copy
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tool.perf_probe import run_pdf_pair as pair


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "--quiet", str(self.repo)], check=True)
        self.git("config", "user.name", "PDF pair contract fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        for name in (*pair.HARNESS_PATHS, *pair.DEPENDENCY_PATHS):
            path = self.repo / name
            if "." not in path.name:
                path = path / "fixture.txt"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("same harness or dependency\n", encoding="utf-8")
        self.application = self.repo / "lib/application.txt"
        self.application.write_text("baseline\n", encoding="utf-8")
        self.baseline = self.commit("baseline fixture")
        self.application.write_text("candidate\n", encoding="utf-8")
        self.candidate = self.commit("candidate fixture")

    def git(self, *args):
        return pair.git(self.repo, *args)

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", message)
        return self.git("rev-parse", "HEAD")

    def commits(self):
        return {"baseline": self.baseline, "candidate": self.candidate}

    def test_immutable_sources_keep_their_tree_and_harness_identity(self):
        result = pair.verify_sources(self.repo, self.commits(), ["lib/application.txt"])
        self.assertEqual(result["changedPaths"], ["lib/application.txt"])
        self.assertEqual(result["sources"]["baseline"]["tree"], self.git("rev-parse", f"{self.baseline}^{{tree}}"))
        self.assertEqual(result["sources"]["baseline"]["harnessObjects"], result["sources"]["candidate"]["harnessObjects"])

    def test_moving_names_abbreviations_and_option_like_inputs_are_rejected(self):
        for value in ("HEAD", "dev", "a" * 39, "a" * 41, "A" * 40, "a" * 39 + "g", "--help", "HEAD^{tree}"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                pair.full_sha(value)

    def test_identical_commits_or_identical_source_trees_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "distinct"):
            pair.verify_sources(self.repo, {"baseline": self.baseline, "candidate": self.baseline})
        self.git("commit", "--allow-empty", "--quiet", "-m", "same tree")
        with self.assertRaisesRegex(ValueError, "distinct"):
            pair.verify_sources(self.repo, {"baseline": self.candidate, "candidate": self.git("rev-parse", "HEAD")})

    def test_a_changed_harness_cannot_be_hidden_by_matching_protocol_numbers(self):
        (self.repo / "integration_test/fixture.txt").write_text("different scheduling\n", encoding="utf-8")
        self.candidate = self.commit("changed harness")
        with self.assertRaisesRegex(ValueError, "harnessObjects"):
            pair.verify_sources(self.repo, self.commits())

    def test_changed_dependency_lock_is_rejected(self):
        (self.repo / "pubspec.lock").write_text("different engine\n", encoding="utf-8")
        self.candidate = self.commit("changed dependency")
        with self.assertRaisesRegex(ValueError, "dependencyObjects"):
            pair.verify_sources(self.repo, self.commits())

    def test_fixed_experiment_rejects_an_unrelated_extra_change(self):
        with self.assertRaisesRegex(ValueError, "declared source delta"):
            pair.verify_sources(self.repo, self.commits(), ["lib/other.txt"])

    def test_tracked_untracked_and_revision_changes_are_rejected(self):
        pair.verify_checkout(self.repo, self.candidate)
        self.application.write_text("uncommitted\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "dirty"):
            pair.verify_checkout(self.repo, self.candidate)
        self.git("restore", "lib/application.txt")
        (self.repo / "unexpected.txt").write_text("untracked\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "dirty"):
            pair.verify_checkout(self.repo, self.candidate)
        (self.repo / "unexpected.txt").unlink()
        with self.assertRaisesRegex(ValueError, "revision"):
            pair.verify_checkout(self.repo, self.baseline)

    def test_results_inside_a_measured_source_are_rejected(self):
        args = self.arguments(self.repo / "results")
        with self.assertRaisesRegex(ValueError, "outside"):
            pair.run_pair(args)
        self.assertFalse(args.output.exists())

    def arguments(self, output):
        return argparse.Namespace(source=self.repo, output=output, experiment=None,
            baseline=self.baseline, candidate=self.candidate, mode="profile", cache_state="cold",
            scenario="pdf-book-view", pages=1000, pdf_case=None, launches=3, repetitions=5,
            order="baseline-first", expected_engine_sha256="", display_mode="desktop")

    def test_prepare_failure_preserves_receipt_and_removes_only_owned_worktree(self):
        original = self.git("worktree", "list", "--porcelain")
        args = self.arguments(self.root / "results")
        with patch.object(pair.platform, "system", return_value="Windows"), \
                patch.object(pair.shutil, "which", side_effect=lambda name: name), \
                patch.object(pair, "sdk_identity", return_value={"frameworkRevision": "a" * 40}), \
                patch.object(pair, "run_logged", side_effect=RuntimeError("injected prepare failure")):
            with self.assertRaisesRegex(RuntimeError, "injected prepare failure"):
                pair.run_pair(args)
        receipt = pair.read_json(args.output / "pair.json")
        self.assertEqual(receipt["status"], "failed")
        self.assertIn("injected prepare failure", receipt["error"])
        self.assertEqual(self.git("worktree", "list", "--porcelain"), original)
        pair.verify_checkout(self.repo, self.candidate)

    def external_pair(self, system, mutation=None, private_input=False):
        pdf = self.root / "private Hebrew corpus.pdf"
        pdf.write_bytes(b"owned external-input contract bytes")
        digest = hashlib.sha256(pdf.read_bytes()).hexdigest()
        request = self.root / "requested-case.json"
        canonical = {"schemaVersion": 1, "source": {
            "kind": "external", "path": str(pdf), "sha256": digest, "pageCount": 17},
            "navigation": {"initialPage": 2, "forwardPage": 15, "backwardPage": 3, "zoomFactor": 2.5}}
        pair.write_json(request, canonical)
        if private_input:
            pdf.chmod(0o600)
            request.chmod(0o600)
        input_owners = [(path.stat().st_uid, path.stat().st_gid) for path in (pdf, request)]
        args = self.arguments(self.root / f"result-{system}-{mutation}")
        args.pdf_case, args.pages = request, None
        native_cases, preparations = [], []

        def logged(command, checkout, log):
            if command[1] == "tool/perf_probe/prepare_pdf_case.dart":
                preparations.append(command)
                self.assertEqual(Path(command[2]), request)
                pair.write_json(Path(command[3]), canonical)
            elif "-PdfCase" in command or "--pdf-case" in command:
                option = "-PdfCase" if system == "Windows" else "--pdf-case"
                output_option = "-OutputDirectory" if system == "Windows" else "--output"
                case_path = Path(command[command.index(option) + 1])
                native_cases.append(case_path)
                case = pair.read_json(case_path)
                self.assertNotEqual(Path(case["source"]["path"]), pdf)
                self.assertEqual(Path(case["source"]["path"]).read_bytes(), pdf.read_bytes())
                directory = Path(command[command.index(output_option) + 1])
                directory.mkdir(parents=True)
                pair.write_json(directory / "pdf-case.json", case)
                comparison = copy.deepcopy(case)
                comparison["source"].pop("path")
                comparison["navigation"].update(zoomPage=3, zoomAnchor="pageCenter")
                pair.write_json(directory / "report.json", {"metadata": {"settings": {
                    "pdfReaderCase": comparison, "pdfPageCount": 17}}})
                if mutation == "source":
                    pdf.write_bytes(b"changed while a native runner was active")
                elif mutation == "source_removed":
                    pdf.unlink()
                elif mutation == "private_manifest":
                    case_path.write_text("{}", encoding="utf-8")
                elif mutation == "runner_manifest":
                    case["navigation"]["forwardPage"] = 16
                    pair.write_json(directory / "pdf-case.json", case)
            return 0.01

        worktrees = self.git("worktree", "list", "--porcelain")
        with patch.object(pair.platform, "system", return_value=system), \
                patch.object(pair.shutil, "which", side_effect=lambda name: name), \
                patch.object(pair, "sdk_identity", return_value={"frameworkRevision": "a" * 40}), \
                patch.object(pair, "run_logged", side_effect=logged), \
                patch.object(pair, "verify_posix_engines"), \
                patch.object(pair, "validate_reports", return_value={"comparable": True}), \
                contextlib.redirect_stdout(io.StringIO()):
            if mutation:
                expected_error = FileNotFoundError if mutation == "source_removed" else ValueError
                with self.assertRaises(expected_error):
                    pair.run_pair(args)
            else:
                pair.run_pair(args)
        receipt = pair.read_json(args.output / "pair.json")
        self.assertEqual(len(preparations), 1)
        self.assertEqual(self.git("worktree", "list", "--porcelain"), worktrees)
        self.assertEqual(receipt["status"], "failed" if mutation else "passed")
        if mutation:
            self.assertEqual(len(native_cases), 1)
            self.assertNotIn(pdf.name, receipt["error"])
            self.assertNotIn(request.name, receipt["error"])
            if mutation == "source_removed":
                self.assertIn("FileNotFoundError", receipt["error"])
        else:
            self.assertEqual(len(native_cases), 2)
            self.assertEqual(native_cases[0], native_cases[1])
            self.assertEqual(receipt["pdfCase"]["sourceSha256"], digest)
            self.assertEqual(receipt["settings"]["pages"], 17)
            self.assertEqual(pair.read_json(request), canonical)
        if mutation != "source_removed":
            self.assertEqual([(path.stat().st_uid, path.stat().st_gid) for path in (pdf, request)], input_owners)
        return args.output, pdf, request

    def test_both_windows_and_posix_runners_receive_the_same_private_case(self):
        for system in ("Windows", "Linux", "Darwin"):
            with self.subTest(platform=system):
                self.external_pair(system)

    def test_edits_during_a_native_run_fail_the_pair_and_keep_worktree_cleanup(self):
        for mutation in ("source", "source_removed", "private_manifest", "runner_manifest"):
            with self.subTest(mutation=mutation):
                self.external_pair("Windows", mutation)

    @unittest.skipUnless(os.name == "posix", "POSIX permissions do not describe Windows ACLs")
    def test_private_inputs_stay_private_with_a_permissive_umask(self):
        previous = os.umask(0o022)
        try:
            output, pdf, request = self.external_pair("Linux", private_input=True)
        finally:
            os.umask(previous)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
        self.assertEqual((output / "corpus-source.pdf").read_bytes(), pdf.read_bytes())
        for original in (pdf, request):
            self.assertEqual(stat.S_IMODE(original.stat().st_mode), 0o600)


class PlatformArgumentsTests(unittest.TestCase):
    def arguments(self):
        return argparse.Namespace(mode="profile", cache_state="warm", scenario="pdf-book-view",
            launches=3, repetitions=5, expected_engine_sha256="", display_mode="desktop")

    def test_posix_uses_the_same_settings_under_the_framework_runner(self):
        for system in ("Linux", "Darwin"):
            with self.subTest(system=system):
                command = pair.native_arguments(Path("checkout"), self.arguments(), Path("result"),
                                                Path("case.json"), "same host", system)
                self.assertEqual(command[1:3], ["-B", str(Path("checkout") / "tool/perf_probe/run_perf_probe_posix.py")])
                options = dict(zip(command[3::2], command[4::2]))
                self.assertEqual(options, {"--mode": "profile", "--cache-state": "warm",
                    "--scenario-set": "pdf-book-view", "--binding-mode": "framework",
                    "--launches": "3", "--repetitions": "5", "--warmup": "1",
                    "--pdf-case": "case.json", "--output": "result", "--hardware-id": "same host",
                    "--display-mode": "desktop"})

    def test_windows_release_keeps_its_verified_engine_requirement(self):
        args = self.arguments()
        args.mode, args.expected_engine_sha256 = "release", "e" * 64
        command = pair.native_arguments(Path("checkout"), args, Path("result"),
                                         Path("case.json"), "same host", "Windows", "pwsh")
        self.assertEqual(command[0:3], ["pwsh", "-NoProfile", "-File"])
        self.assertEqual(command[-2:], ["-ExpectedEngineSha256", "e" * 64])
        self.assertIn("-BindingMode", command)

    def test_cli_accepts_an_external_case_or_generated_pages_but_not_both(self):
        for options in (("--pdf-case", "a case.json"), ("--pages", "100"), ()):
            with self.subTest(options=options), patch.object(sys, "argv", ["pair", "--output", "result", *options]), \
                    patch.object(pair, "run_pair") as run:
                self.assertEqual(pair.main(), 0)
                args = run.call_args.args[0]
                self.assertEqual(args.pdf_case, Path("a case.json") if "--pdf-case" in options else None)
                self.assertEqual(args.pages, 100 if "--pages" in options else None)
        with patch.object(sys, "argv", ["pair", "--output", "result", "--pages", "100", "--pdf-case", "case.json"]), \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            pair.main()
        self.assertEqual(error.exception.code, 2)


@unittest.skipUnless(sys.platform in ("linux", "darwin"), "POSIX receipts require a native POSIX filesystem")
class PosixEvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / "results"
        self.root.mkdir()
        self.reports = {}
        self.settings = {"mode": "profile", "cacheState": "warm", "launches": 2}
        for role in ("baseline", "candidate"):
            directory = self.root / role
            directory.mkdir()
            image = self.root.parent / "worktrees" / role / "bundle/lib/libflutter_linux_gtk.so"
            image.parent.mkdir(parents=True)
            image.write_bytes(b"the exact bundled engine contract fixture")
            identity = {"schemaVersion": 1, "platform": "linux", "buildMode": "profile",
                        "binaryName": image.name, **pair.binary_identity(image)}
            self.reports[role] = {"metadata": {"engineIdentity": identity}}
            st = image.stat()
            device = f"{os.major(st.st_dev):x}:{os.minor(st.st_dev):x}"
            image = str(image)
            pair.write_json(directory / "manifest.json", {"engineIdentity": identity,
                "engineEvidence": {"verifiedAfterRuns": True, "canonicalPath": image}})
            for name, index, preparation in (
                ("prepare-data", -1, True), ("prepare-warm", -1, False),
                ("launch-000", 0, False), ("launch-001", 1, False),
            ):
                launch = directory / name
                launch.mkdir()
                pair.write_json(launch / "launch.json", {"pid": 123, "engineVerifiedAfterCompletion": True,
                    "completedBeforeTermination": True, "preparationOnly": preparation, "launchIndex": index})
                pair.write_json(launch / "engine.json", {"pid": 123, "observedAfterCompletion": True,
                    "identity": identity, "canonicalPath": image, "source": "/proc/123/maps",
                    "rawObservation": f"1000-2000 r-xp 0 {device} {st.st_ino} {image}\n"})

    def test_every_warm_preparation_and_measured_launch_requires_mapping_evidence(self):
        pair.verify_posix_engines(self.root, self.reports, self.settings, "Linux")
        missing = self.root / "baseline/prepare-warm/engine.json"
        missing.unlink()
        with self.assertRaises(FileNotFoundError):
            pair.verify_posix_engines(self.root, self.reports, self.settings, "Linux")

    def test_false_completion_wrong_pid_or_foreign_engine_cannot_be_comparable(self):
        path = self.root / "candidate/launch-001/engine.json"
        original = pair.read_json(path)
        for key, value in (("pid", 124), ("pid", True), ("observedAfterCompletion", False),
                           ("canonicalPath", "/foreign/engine"), ("identity", {}), ("rawObservation", "")):
            with self.subTest(field=key), self.assertRaises(ValueError):
                pair.write_json(path, {**original, key: value})
                pair.verify_posix_engines(self.root, self.reports, self.settings, "Linux")

    def test_engine_evidence_requires_the_expected_completed_launch(self):
        path = self.root / "candidate/launch-001/launch.json"
        original = pair.read_json(path)
        for key, value in (("launchIndex", 0), ("preparationOnly", True), ("completedBeforeTermination", False)):
            with self.subTest(field=key), self.assertRaises(ValueError):
                pair.write_json(path, {**original, key: value})
                pair.verify_posix_engines(self.root, self.reports, self.settings, "Linux")

    def test_mapped_inode_must_match_the_bundled_engine(self):
        path = self.root / "candidate/launch-001/engine.json"
        proof = pair.read_json(path)
        fields = proof["rawObservation"].split(maxsplit=5)
        fields[4] = str(int(fields[4]) + 1)
        proof["rawObservation"] = " ".join(fields)
        pair.write_json(path, proof)
        with self.assertRaisesRegex(ValueError, "inode"):
            pair.verify_posix_engines(self.root, self.reports, self.settings, "Linux")

    def test_same_report_hash_does_not_replace_before_after_verification(self):
        path = self.root / "candidate/manifest.json"
        manifest = pair.read_json(path)
        manifest["engineEvidence"]["verifiedAfterRuns"] = False
        pair.write_json(path, manifest)
        with self.assertRaisesRegex(ValueError, "before and after"):
            pair.verify_posix_engines(self.root, self.reports, self.settings, "Linux")


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.commits = {"baseline": "a" * 40, "candidate": "b" * 40}
        self.settings = {"mode": "profile", "cacheState": "cold", "scenario": "pdf-book-view",
                         "pages": 1000, "launches": 3, "repetitions": 5}
        self.sdk = {"frameworkRevision": "c" * 40}
        self.hardware = "one actual host session"
        names = ["startup.first_content", "startup.window_useful"] + [f"pdf.book_view.{name}" for name in (
            "open", "thumbnails_first_image", "jump_forward", "jump_backward",
            "prepare_reversals", "rapid_reversals", "close", "idle_after_close")]
        self.reports = {}
        for role, commit in self.commits.items():
            self.reports[role] = {
                "sourceSchemaVersion": 2, "complete": True, "successful": True,
                "comparisonEligibility": [],
                "metadata": {"commit": commit, "dirty": False, "buildMode": "profile",
                    "cacheState": "cold", "launchCount": 3, "repetitions": 5, "warmup": 1,
                    "bindingMode": "framework", "hardwareId": self.hardware,
                    "flutterVersion": self.sdk["frameworkRevision"],
                    "settings": {"scenarioSet": "pdf-book-view",
                        "pdfReaderCase": {"source": {
                            "kind": "generated", "pageCount": 1000, "mixedPageSizes": True,
                        }}},
                    "machine": {"cpu": "fixture CPU"}, "engineIdentity": {"bundleSha256": "d" * 64}},
                "scenarios": [{"name": name, "status": "passed", "measured": 3 if name.startswith("startup.") else 15} for name in names],
            }
        self.reports["candidate"]["comparison"] = {
            "comparable": True, "reasons": [], "baselineCommit": self.commits["baseline"],
            "candidateCommit": self.commits["candidate"],
            "scenarios": [{"name": name, "status": "compared"} for name in names],
        }
        for report in self.reports.values():
            for row in report["scenarios"]:
                startup = row["name"].startswith("startup.")
                row["warmupExcluded"] = 0 if startup else 3
                row["samples"] = [{"status": "passed", "launchIndex": launch,
                    "warmup": False, "iteration": iteration} for launch in range(3)
                    for iteration in range(1 if startup else 5)]
                if not startup:
                    row["samples"] += [{"status": "passed", "launchIndex": launch,
                        "warmup": True, "iteration": 0} for launch in range(3)]

    def validate(self, reports=None):
        return pair.validate_reports(
            reports or self.reports, self.commits, self.settings, self.hardware, self.sdk,
            expected_corpus={"kind": "generated", "pageCount": 1000, "mixedPageSizes": True},
        )

    def test_complete_comparison_is_accepted_without_a_speed_threshold(self):
        self.reports["candidate"]["comparison"]["scenarios"][0]["metrics"] = {
            "latencyMs.p95": {"baseline": 10, "candidate": 50, "percentChange": 400}}
        self.assertTrue(self.validate()["comparable"])

    def test_partial_failed_dirty_or_wrong_source_reports_are_rejected(self):
        for role in self.reports:
            for field, value in (("complete", False), ("successful", False), ("comparisonEligibility", ["missing_samples"]), ("sourceSchemaVersion", 1)):
                with self.subTest(role=role, field=field), self.assertRaises(ValueError):
                    reports = copy.deepcopy(self.reports)
                    reports[role][field] = value
                    self.validate(reports)
            for field, value in (("dirty", True), ("commit", "d" * 40), ("hardwareId", "another host"),
                    ("flutterVersion", "e" * 40), ("buildMode", "debug"), ("cacheState", "warm"),
                    ("launchCount", 1), ("repetitions", 1), ("warmup", 0), ("warmup", True), ("bindingMode", "integration")):
                with self.subTest(role=role, field=field), self.assertRaises(ValueError):
                    reports = copy.deepcopy(self.reports)
                    reports[role]["metadata"][field] = value
                    self.validate(reports)

    def test_identical_but_wrong_pdf_corpus_is_rejected(self):
        for field, value in (("kind", "external"), ("pageCount", 600), ("mixedPageSizes", False)):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "wrong PDF corpus"):
                reports = copy.deepcopy(self.reports)
                for report in reports.values():
                    report["metadata"]["settings"]["pdfReaderCase"]["source"][field] = value
                self.validate(reports)

    def test_analyzer_exit_success_does_not_imply_comparability(self):
        for field, value in (("comparable", False), ("reasons", ["metadata:viewport"]),
                ("baselineCommit", "e" * 40), ("candidateCommit", "f" * 40)):
            with self.subTest(field=field), self.assertRaises(ValueError):
                reports = copy.deepcopy(self.reports)
                reports["candidate"]["comparison"][field] = value
                self.validate(reports)

    def test_comparable_flag_does_not_hide_uncompared_scenarios(self):
        for status in ("missing_in_baseline", "missing_in_candidate", "different_sample_count",
                "different_repetition_layout", "different_measurement_kind", "unavailable"):
            with self.subTest(status=status), self.assertRaises(ValueError):
                reports = copy.deepcopy(self.reports)
                reports["candidate"]["comparison"]["scenarios"][0]["status"] = status
                self.validate(reports)

    def test_missing_or_duplicate_observations_are_rejected(self):
        for role in self.reports:
            for operation in ("clear", "duplicate", "failed"):
                with self.subTest(role=role, operation=operation), self.assertRaises(ValueError):
                    reports = copy.deepcopy(self.reports)
                    rows = reports[role]["scenarios"]
                    if operation == "clear":
                        rows.clear()
                    elif operation == "duplicate":
                        rows.append(rows[0])
                    else:
                        rows[0]["status"] = "failed"
                    self.validate(reports)
        for operation in ("remove", "duplicate"):
            with self.subTest(comparison=operation), self.assertRaises(ValueError):
                reports = copy.deepcopy(self.reports)
                rows = reports["candidate"]["comparison"]["scenarios"]
                rows.pop() if operation == "remove" else rows.append(rows[0])
                self.validate(reports)

    def test_machine_engine_and_scenario_must_match_the_actual_pair(self):
        for field in ("machine", "engineIdentity", "settings"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                reports = copy.deepcopy(self.reports)
                reports["candidate"]["metadata"][field] = {"different": True}
                self.validate(reports)

    def add_uninstrumented_observation(self, name="queues.depth"):
        for report in self.reports.values():
            report["scenarios"].append({"name": name, "status": "skipped", "measured": 0,
                "latencyMs": None, "failures": 0, "samples": [
                    {"status": "skipped", "reason": "The application does not expose complete queue depths."}
                    for _ in range(3)]})
        self.reports["candidate"]["comparison"]["scenarios"].append({"name": name, "status": "unavailable"})

    def test_explicit_uninstrumented_observations_stay_unavailable_without_numbers(self):
        for name in ("queues.depth", "windows.native_open_close", "pdf.book_view.first_preview_image"):
            self.add_uninstrumented_observation(name)
        self.assertTrue(self.validate()["comparable"])

    def test_uninstrumented_does_not_allow_skipping_requested_actions(self):
        self.reports["baseline"]["scenarios"][2]["status"] = "skipped"
        self.reports["candidate"]["scenarios"][2]["status"] = "skipped"
        with self.assertRaisesRegex(ValueError, "unexpectedly skipped"):
            self.validate()

    def test_unavailable_requires_matching_reasons_and_no_numeric_comparison(self):
        self.add_uninstrumented_observation()
        for mutation in ("reason", "count", "measured", "metrics", "compared"):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                reports = copy.deepcopy(self.reports)
                row = reports["candidate"]["scenarios"][-1]
                if mutation == "reason":
                    row["samples"][0]["reason"] = ""
                elif mutation == "count":
                    row["samples"].pop()
                elif mutation == "measured":
                    row["measured"] = 1
                elif mutation == "metrics":
                    reports["candidate"]["comparison"]["scenarios"][-1]["metrics"] = {}
                else:
                    reports["candidate"]["comparison"]["scenarios"][-1]["status"] = "compared"
                self.validate(reports)

    def test_identically_missing_actions_or_iterations_are_still_rejected(self):
        for mutation in ("missing", "repetitions"):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                reports = copy.deepcopy(self.reports)
                for report in reports.values():
                    if mutation == "missing":
                        report["scenarios"].pop(3)
                    else:
                        report["scenarios"][3]["measured"] = 3
                self.validate(reports)

    def test_equal_counts_cannot_hide_missing_launches_or_warmup(self):
        for mutation in ("launch", "iteration", "warmup", "duplicate", "boolean-index"):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                reports = copy.deepcopy(self.reports)
                for report in reports.values():
                    row = report["scenarios"][3]
                    if mutation == "duplicate":
                        row["samples"][1] = row["samples"][0]
                    elif mutation == "warmup":
                        row["samples"][-1]["warmup"] = False
                    else:
                        key = "iteration" if mutation == "iteration" else "launchIndex"
                        row["samples"][0][key] = True if mutation == "boolean-index" else 99
                self.validate(reports)


if __name__ == "__main__":
    unittest.main()
