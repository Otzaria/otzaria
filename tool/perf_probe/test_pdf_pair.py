from __future__ import annotations

import argparse
import copy
from pathlib import Path
import subprocess
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
            scenario="pdf-book-view", pages=1000, launches=3, repetitions=5,
            order="baseline-first", expected_engine_sha256="")

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
        return pair.validate_reports(reports or self.reports, self.commits, self.settings, self.hardware, self.sdk)

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
