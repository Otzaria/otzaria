#!/usr/bin/env python3
"""Freeze publication metadata after the actual local control gates pass."""

import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent / "pr4307-flat-control"
VALIDATION = ROOT / "validation"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(REPO), *args]).decode().strip()


def file_record(path):
    return {
        "relative_path": str(path.relative_to(ROOT)),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def main():
    manifest = read(ROOT / "publication_manifest.json")
    plan = read(ROOT / "validation_plan.json")
    source = read(ROOT / "source_provenance.json")
    pub_get = read(VALIDATION / "pub_get_status.json")
    analyze = read(VALIDATION / "analyze_status.json")
    tests = read(VALIDATION / "common_tests_status.json")
    original_test = plan["validation_overlay"]
    product = manifest["files"][0]
    assert pub_get["exit_code"] == analyze["exit_code"] == tests["exit_code"] == 0
    assert tests["all_tests_passed"] and tests["temporary_sibling_removed"]
    assert tests["original_test_product_lockfile_and_other_source_unchanged"]
    assert "Formatted 1 file (0 changed)" in (VALIDATION / "format_check.log").read_text()
    assert git("rev-parse", "HEAD") == manifest["parent_sha"]
    assert git("write-tree") == manifest["expected_tree"]
    assert git("diff", "--cached", "--name-only") == product["repo_path"]
    assert git("diff", "--name-only") == ""
    assert git("status", "--porcelain=v1", "--untracked-files=all") == "M  " + product["repo_path"]
    assert sha256(REPO / product["repo_path"]) == product["sha256"]
    assert git("hash-object", product["repo_path"]) == product["git_blob_sha"]
    assert sha256(REPO / original_test["original_repo_path"]) == original_test["original_sha256"]
    assert not (REPO / original_test["generated_repo_path"]).exists()
    lock = read(VALIDATION / "lockfile-proof.json")
    assert sha256(REPO / "pubspec.lock") == lock["originalSha256"] == lock["resolvedSha256"]
    test_log = (VALIDATION / "common_tests.log").read_text(encoding="utf-8")
    match = re.search(r"\+(\d+): All tests passed!", test_log)
    assert match is not None
    test_count = int(match.group(1))
    assert test_count == 220
    expected_test_files = plan["common_test_files"] + [original_test["generated_repo_path"]]
    assert tests["command"] == ["flutter", "test", "--no-pub", "--reporter", "expanded", *expected_test_files]
    now = datetime.now(timezone.utc).isoformat()
    summary = {
        "completed_at_utc": now,
        "candidate_parent_sha": manifest["parent_sha"],
        "tested_staged_control_tree": manifest["expected_tree"],
        "tested_product_git_blob": product["git_blob_sha"],
        "tested_product_sha256": product["sha256"],
        "pub_get_enforce_lockfile": {"passed": True, **pub_get},
        "format_check": {
            "passed": True,
            "exit_code": 0,
            "changed_files": 0,
            "command": plan["mandatory_gates"][0],
            "note": "Successful check after dependency resolution, before analyze/tests; source hash unchanged after all gates.",
        },
        "full_flutter_analyze": {"passed": True, **analyze},
        "common_flutter_tests": {
            "passed": True,
            "exit_code": 0,
            "count": test_count,
            "test_files": 18,
            "seconds_including_native_build": tests["seconds"],
            "command": tests["command"],
            "reporter_scope": "Aggregate successful run of the 18 explicitly named files; expanded parallel reporter can show another active suite on a completion line, so no per-file count is inferred from those line labels.",
            "temporary_sibling_removed": True,
            "only_representation_assertion_removed_from_temporary_sibling": True,
        },
        "pubspec_lock_sha256_before_and_after": lock["originalSha256"],
        "all_other_sources_unchanged": True,
        "uncommitted_control_only": True,
        "source_audit": file_record(ROOT / "independent-source-qa.json"),
        "remaining_gates": [
            "Publish one control commit with candidate as its only parent and this exact tree.",
            "Run controlled Windows validation/builds for both fixed SHAs before accepting performance measurements.",
            "Analyze the paired Windows raw results; physical GPU verification remains unavailable and separate.",
        ],
        "evidence": [file_record(VALIDATION / name) for name in [
            "toolchain.json", "pub_get.log", "pub_get_status.json", "lockfile-proof.json",
            "format_check.log", "analyze.log", "analyze_status.json", "common_tests.log",
            "common_tests_status.json",
        ]],
    }
    write(VALIDATION / "local_validation_summary.json", summary)
    plan["local_tools"] = {
        "initially_available_on_PATH": False,
        "restored_after_explicit_parent_instruction": True,
        "flutter_directory": str(ROOT.parent / "flutter-sdk4307"),
        "native_toolchain_directory": str(ROOT.parent / "toolchain4307"),
        "toolchain_provenance": "validation/toolchain.json",
    }
    plan["local_validation"] = {
        "passed": True,
        "summary": "validation/local_validation_summary.json",
        "test_count": test_count,
        "format_changed_files": 0,
        "full_analyze_issues": 0,
        "source_and_lockfile_unchanged": True,
    }
    plan["not_run_locally"] = ["Windows builds", "New Windows performance measurements", "Physical GPU measurements"]
    write(ROOT / "validation_plan.json", plan)
    source["validation"] = {
        "source_structure_checks": "passed",
        "independent_source_audit": "passed; see independent-source-qa.json (runtime statements there reflect its earlier audit time)",
        "dart_format": "passed locally with pinned SDK; 0 files changed",
        "flutter_analyze": "passed full repository locally; no issues found",
        "flutter_behavioral_tests": "passed locally: 220 tests in 17 common files and the narrow temporary validation sibling; original test unchanged and sibling removed",
        "pubspec_lock": "unchanged byte-for-byte after --enforce-lockfile",
        "local_validation_summary": "validation/local_validation_summary.json",
        "windows_profile_build": "pending CI for both fixed source SHAs",
    }
    write(ROOT / "source_provenance.json", source)
    manifest["frozen_at_utc"] = now
    manifest["validation_status"] = "Local format, full Flutter analyze and all 220 common behavioral tests passed before any control commit; Windows validation/builds and performance interpretation remain pending."
    manifest["publication_state"] = "validated and ready for parent-controlled publication; no local commit or remote mutation performed by this agent"
    manifest["local_validation_summary"] = file_record(VALIDATION / "local_validation_summary.json")
    manifest["one_commit_requirement"] = {
        "only_parent": manifest["candidate_sha"],
        "only_changed_path": product["repo_path"],
        "expected_tree": manifest["expected_tree"],
        "do_not_rebase_onto_moving_dev": True,
    }
    included = [
        "prepare_flat_control.py", "source_provenance.json", "representation_only.patch",
        "validation_plan.json", "validation_overlay.py", "validation_overlay_provenance.json",
        "run_local_control_validation.py", "finalize_local_validation.py", "independent-source-qa.json",
    ]
    included += [str(path.relative_to(ROOT)) for path in sorted(VALIDATION.iterdir()) if path.is_file() and path.name != "pubspec.lock.original"]
    manifest["evidence_files"] = [file_record(ROOT / name) for name in included]
    manifest["evidence_paths"] = {name: str(ROOT / name) for name in included}
    manifest["evidence_total_bytes_excluding_manifest"] = sum(row["bytes"] for row in manifest["evidence_files"])
    write(ROOT / "publication_manifest.json", manifest)
    print(json.dumps({
        "manifest": str(ROOT / "publication_manifest.json"),
        "manifest_sha256": sha256(ROOT / "publication_manifest.json"),
        "expected_tree": manifest["expected_tree"],
        "git_blob_sha": product["git_blob_sha"],
        "product_sha256": product["sha256"],
        "tests_passed": test_count,
        "evidence_file_count_excluding_manifest": len(manifest["evidence_files"]),
        "evidence_bytes_excluding_manifest": manifest["evidence_total_bytes_excluding_manifest"],
    }, indent=2))


if __name__ == "__main__":
    main()
