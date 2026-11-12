#!/usr/bin/env python3
"""Create/remove one verified temporary test sibling for the flat control."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


ORIGINAL = "test/text_book/bloc/long_book_snapshot_regression_test.dart"
GENERATED = (
    "test/text_book/bloc/"
    "long_book_snapshot_regression_flat_control_validation_test.dart"
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def git(repo, *arguments):
    return subprocess.check_output(["git", "-C", str(repo), *arguments])


def assert_clean(repo):
    status = git(repo, "status", "--porcelain=v1", "--untracked-files=all")
    if status.strip():
        raise RuntimeError("Control source is not clean: " + status.decode())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("create", "remove"))
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--proof", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    metadata = json.loads(
        Path(__file__).with_name("validation_overlay_provenance.json").read_text(encoding="utf-8")
    )
    require(metadata["original_repo_path"] == ORIGINAL, "Unexpected original test path")
    require(metadata["generated_repo_path"] == GENERATED, "Unexpected generated test path")
    original = repo / ORIGINAL
    generated = repo / GENERATED
    source = original.read_bytes()
    require(digest(source) == metadata["original_sha256"], "Original source hash mismatch")
    require(digest(git(repo, "show", "HEAD:" + ORIGINAL)) == metadata["original_sha256"], "Committed original source hash mismatch")
    assertion = metadata["removed_unique_assertion_utf8"].encode("utf-8")
    require(source.count(assertion) == 1, "Expected exactly one representation assertion")
    overlay = source.replace(assertion, b"", 1)
    require(digest(overlay) == metadata["generated_sha256"], "Generated source hash mismatch")

    if args.action == "create":
        assert_clean(repo)
        if generated.exists() or generated.is_symlink():
            raise RuntimeError("Refusing to overwrite an existing validation sibling")
        if args.proof and args.proof.resolve().is_relative_to(repo):
            raise RuntimeError("Write validation proof outside the source checkout")
        with generated.open("xb") as output:
            output.write(overlay)
        proof = {
            **metadata,
            "measured_control_source_commit": git(repo, "rev-parse", "HEAD").decode().strip(),
            "original_verified_unchanged": digest(original.read_bytes()) == metadata["original_sha256"],
            "generated_verified": digest(generated.read_bytes()) == metadata["generated_sha256"],
            "overlay_is_uncommitted_validation_only": True,
        }
        if args.proof:
            args.proof.parent.mkdir(parents=True, exist_ok=True)
            args.proof.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Created verified flat-control validation sibling")
    else:
        if generated.is_symlink() or not generated.is_file():
            raise RuntimeError("Expected the generated regular validation file")
        if git(repo, "ls-files", "--", GENERATED).strip():
            raise RuntimeError("Refusing to remove a tracked validation file")
        require(digest(generated.read_bytes()) == metadata["generated_sha256"], "Generated file changed before cleanup")
        generated.unlink()
        require(digest(original.read_bytes()) == metadata["original_sha256"], "Original test changed during validation")
        assert_clean(repo)
        print("Removed only the generated sibling; original and clean source verified")


if __name__ == "__main__":
    main()
