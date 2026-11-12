#!/usr/bin/env python3
"""Validate the staged control before its first commit, retaining raw logs."""

import hashlib
import json
import os
import subprocess
import time
from pathlib import Path


ROOT = Path("/workspace/scratch/03d201536b5d")
REPO = ROOT / "pr4307-flat-control"
EVIDENCE = ROOT / "pr4307-flat-evidence"
OUTPUT = EVIDENCE / "validation"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-C", str(REPO), *args])


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    manifest = json.loads((EVIDENCE / "publication_manifest.json").read_text())
    plan = json.loads((EVIDENCE / "validation_plan.json").read_text(encoding="utf-8"))
    overlay = plan["validation_overlay"]
    analyze = json.loads((OUTPUT / "analyze_status.json").read_text())
    require(analyze["exit_code"] == 0, "Full analyze must pass first")
    require(git("write-tree").decode().strip() == manifest["expected_tree"], "Unexpected staged tree")
    require(not git("diff", "--name-only").strip(), "Unexpected unstaged source changes")
    status_before = git("status", "--porcelain=v1", "--untracked-files=all")
    expected_status = b"M  lib/text_book/bloc/text_book_bloc.dart\n"
    require(status_before == expected_status, "Only the intended staged product change is allowed")
    original = REPO / overlay["original_repo_path"]
    generated = REPO / overlay["generated_repo_path"]
    require(digest(original) == overlay["original_sha256"], "Original test hash mismatch")
    line = overlay["removed_unique_assertion_utf8"].encode("utf-8")
    source = original.read_bytes()
    require(source.count(line) == 1, "Representation assertion must be unique")
    generated_bytes = source.replace(line, b"", 1)
    require(hashlib.sha256(generated_bytes).hexdigest() == overlay["generated_sha256"], "Overlay hash mismatch")
    require(not generated.exists() and not generated.is_symlink(), "Overlay already exists")
    product = REPO / manifest["files"][0]["repo_path"]
    require(digest(product) == manifest["files"][0]["sha256"], "Product source hash mismatch")
    lock_before = digest(REPO / "pubspec.lock")
    with generated.open("xb") as output:
        output.write(generated_bytes)

    env = os.environ.copy()
    env.update(CI="true", BOT="true", FLUTTER_SUPPRESS_ANALYTICS="true", DART_SUPPRESS_ANALYTICS="true")
    env["PATH"] = str(ROOT / "toolchain4307/bin") + os.pathsep + str(ROOT / "flutter-sdk4307/bin") + os.pathsep + env["PATH"]
    command = [
        "flutter", "test", "--no-pub", "--reporter", "expanded",
        *plan["common_test_files"], overlay["generated_repo_path"],
    ]
    start = time.time()
    exit_code = None
    try:
        with (OUTPUT / "common_tests.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT)
        exit_code = result.returncode
    finally:
        require(generated.is_file() and not generated.is_symlink(), "Generated test missing or replaced")
        require(digest(generated) == overlay["generated_sha256"], "Generated test changed unexpectedly")
        generated.unlink()
        require(digest(original) == overlay["original_sha256"], "Original test changed")
        require(digest(product) == manifest["files"][0]["sha256"], "Product source changed")
        require(digest(REPO / "pubspec.lock") == lock_before, "Dependency lockfile changed")
        require(git("status", "--porcelain=v1", "--untracked-files=all") == status_before, "Unexpected source changes after validation")

    text = (OUTPUT / "common_tests.log").read_text(encoding="utf-8")
    report = {
        "exit_code": exit_code,
        "seconds": time.time() - start,
        "all_tests_passed": "All tests passed!" in text,
        "command": command,
        "candidate_parent_sha": manifest["parent_sha"],
        "tested_staged_control_tree": manifest["expected_tree"],
        "tested_product_sha256": manifest["files"][0]["sha256"],
        "original_test_sha256": overlay["original_sha256"],
        "generated_test_sha256": overlay["generated_sha256"],
        "only_representation_assertion_removed_from_temporary_sibling": True,
        "temporary_sibling_removed": True,
        "original_test_product_lockfile_and_other_source_unchanged": True,
        "original_test_was_not_modified_or_committed": True,
    }
    (OUTPUT / "common_tests_status.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "command"}, indent=2))
    print(text[-6000:])
    raise SystemExit(exit_code or (0 if report["all_tests_passed"] else 1))


if __name__ == "__main__":
    main()
