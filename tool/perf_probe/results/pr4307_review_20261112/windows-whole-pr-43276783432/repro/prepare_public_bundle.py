#!/usr/bin/env python3
"""Preserve all non-trace artifact bytes plus explicitly selected diagnostic traces."""
import argparse
import gzip
import hashlib
import io
import json
import os
import re
import subprocess
import tempfile
import zlib
from collections import Counter
from pathlib import Path

BASE = "f05cbf270cba7c7815b965b4a67f2d07cdf12be3"
BASE_TREE = "b0b26987dc7d111d9149f85f9f0c8c71cb114d3c"
PREFIX = "tool/perf_probe/results/pr4307_review_20261112/windows-whole-pr-43276783432"
RUN = 43276783432
JOB = 131387187813
ARTIFACT = 13978305619
ZIP_SHA = "39ba138234ff546e9556fa9826aa51ac47e212f1f327b5227d28ee870a494d01"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def compress(data):
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode="wb", filename="", mtime=0, compresslevel=9) as stream:
        stream.write(data)
    result = out.getvalue()
    assert gzip.decompress(result) == data
    return result


def git(repo, *args, input=None, env=None):
    return subprocess.check_output(["git", "-C", str(repo), *args], input=input, env=env)


def entries(repo, tree):
    result = {}
    for row in git(repo, "ls-tree", "-rz", tree).split(b"\0"):
        if row:
            value, path = row.split(b"\t", 1)
            result[path.decode()] = value.decode()
    return result


def main():
    parser = argparse.ArgumentParser()
    for name in ["run-dir", "repo", "output"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--qa-file", action="append", type=Path, default=[])
    parser.add_argument("--trace-list", type=Path)
    parser.add_argument("--qa-final", action="store_true")
    args = parser.parse_args()
    root = args.run_dir.resolve()
    artifact_root = root / f"artifact{ARTIFACT}"
    output = args.output.resolve()
    payload = output / "payload"
    payload.mkdir(parents=True, exist_ok=True)
    receipt = read(root / f"metadata/artifact{ARTIFACT}-verification.json")
    assert receipt["run_id"] == RUN and receipt["run_attempt"] == 1
    assert receipt["artifact_id"] == ARTIFACT and receipt["zip_sha256"] == ZIP_SHA
    assert receipt["member_count"] == 1012 and receipt["all_zip_member_crcs_valid"]
    assert receipt["all_members_preserved"] and receipt["declared_digest_matches"]
    run = read(root / "metadata/run-final.json")
    jobs = read(root / "metadata/jobs-final.json")["jobs"]
    artifact = next(a for a in read(root / "metadata/artifacts-final.json")["artifacts"] if a["id"] == ARTIFACT)
    assert run["status"] == "completed" and run["conclusion"] == "success" and run["run_attempt"] == 1
    assert next(j for j in jobs if j["id"] == JOB)["conclusion"] == "success"
    assert artifact["digest"] == "sha256:" + ZIP_SHA
    selected_list = read(args.trace_list) if args.trace_list else []
    assert isinstance(selected_list, list) and len(selected_list) == len(set(selected_list))
    selected = set(selected_list)
    originals = {row["path"]: row for row in receipt["members"]}
    assert selected <= set(originals)
    assert all(Path(path).name.startswith("reader_trace") for path in selected)
    files, dispositions, signed = [], [], []

    def add(data, path, kind, original=None, gz=False):
        for url in re.findall(r"https?://[^\s<>\"']+", data.decode("utf-8")):
            if re.search(r"[?&](?:sig|signature|token|access_token|auth|se|sp|sv|X-Amz-Signature|X-Goog-Signature)=", url, re.I):
                signed.append(path)
        saved = compress(data) if gz else data
        relative = path + ".gz" if gz else path
        target = payload / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(saved)
        row = {
            "repo_path": PREFIX + "/" + relative, "relative_path": relative,
            "local_path": str(target), "mode": "100644", "type": "blob",
            "encoding": "base64" if gz else "utf-8", "bytes": len(saved), "sha256": sha(saved),
            "source_kind": kind, "source_path": original,
            "source_bytes": len(data), "source_sha256": sha(data),
            "transformation": "lossless gzip, mtime=0, filename empty, level=9" if gz else "byte-for-byte copy",
        }
        files.append(row)
        return row

    for member in receipt["members"]:
        path = member["path"]
        trace = Path(path).name.startswith("reader_trace")
        item = dict(member)
        if trace and path not in selected:
            item.update(public_bundle="omitted_trace", reason="Preserved in the complete verified ZIP; only explicit diagnostic traces are duplicated in Git.")
        else:
            data = (artifact_root / path).read_bytes()
            assert len(data) == member["bytes"] and sha(data) == member["sha256"]
            gz = trace or path.endswith(".jsonl") or (path.endswith(".json") and len(data) > 65536)
            saved = add(data, "artifact/" + path, "diagnostic_trace" if trace else "artifact_member", path, gz)
            item.update(public_bundle="included", bundle_path=saved["relative_path"], stored_sha256=saved["sha256"])
        dispositions.append(item)
    for path in ["run-final.json", "jobs-final.json", "artifacts-final.json", "download_receipt.json", "job-log-receipt.json", f"artifact{ARTIFACT}-verification.json", f"job{JOB}.log"]:
        data = (root / "metadata" / path).read_bytes()
        add(data, "metadata/" + path, "connector_or_extraction_metadata", "metadata/" + path, path.endswith(".log") or len(data) > 65536)
    qa_names, qa_statuses = set(), []
    for path in args.qa_file:
        assert path.name not in qa_names
        qa_names.add(path.name)
        data = path.read_bytes()
        add(data, "qa/" + path.name, "independent_qa", str(path), len(data) > 65536)
        if path.suffix == ".json":
            report = json.loads(data)
            if isinstance(report, dict) and "evidence_status" in report:
                qa_statuses.append({
                    "file": path.name, "evidence_status": report["evidence_status"],
                    "error_count": len(report.get("errors", [])),
                    "warnings_by_code": dict(Counter(warning.get("code", "unspecified") for warning in report.get("warnings", []))),
                })
    if args.qa_final:
        assert args.qa_file, "Completed QA outputs are required before publication freeze"
    assert not signed, "Signed/credential query URL found in: " + ", ".join(sorted(set(signed)))
    counts = Counter(row["public_bundle"] for row in dispositions)
    index = {
        "run_id": RUN, "run_attempt": 1, "artifact_id": ARTIFACT, "original_zip_sha256": ZIP_SHA,
        "all_original_members_indexed": len(dispositions), "disposition_counts": dict(counts),
        "omitted_logs": [], "omitted_non_trace_artifact_members": [],
        "samples_warmups_outliers_errors_filtered": False, "duplicate_phase_and_csv_copies_preserved": True,
        "members": dispositions,
    }
    add(encoded(index), "artifact-member-index.json", "complete_member_disposition_index", gz=True)
    missing = [f"reader-profile/{side}-{suffix}" for side in ["baseline", "candidate"] for suffix in ["status.txt", "diff.patch"]]
    bundle = {
        "purpose": "Whole PR against its frozen dev baseline; separate from the representation-only experiment.",
        "run_id": RUN, "run_attempt": 1, "job_id": JOB, "run_conclusion": run["conclusion"],
        "run_url": f"https://github.com/Otzaria/otzaria/actions/runs/{RUN}",
        "artifact": {
            "id": ARTIFACT, "name": artifact["name"],
            "url": f"https://github.com/Otzaria/otzaria/actions/runs/{RUN}/artifacts/{ARTIFACT}",
            "api_metadata_url": f"https://api.github.com/repos/Otzaria/otzaria/actions/artifacts/{ARTIFACT}",
            "zip_bytes": receipt["zip_bytes"], "zip_sha256": ZIP_SHA,
            "member_count": receipt["member_count"], "uncompressed_bytes": receipt["uncompressed_bytes"],
            "created_at": artifact.get("created_at"), "expires_at": artifact["expires_at"], "retention_days": 14,
            "full_zip": "Original verified ZIP retained separately by the owner; not duplicated as a Git blob.",
        },
        "source": read(artifact_root / "reader-profile/provenance.json"),
        "preservation": {
            "all_non_trace_artifact_members_included": True, "all_phase_files_included": True,
            "all_csv_files_included": True, "all_artifact_logs_included": True,
            "phase_file_count": sum(Path(row["path"]).name == "phases.jsonl" for row in receipt["members"]),
            "csv_file_count": sum(row["path"].endswith(".csv") for row in receipt["members"]),
            "error_jsonl_file_count": sum(row["path"].endswith(".errors.jsonl") for row in receipt["members"]),
            "artifact_log_file_count": sum(row["path"].endswith(".log") for row in receipt["members"]),
            "empty_member_count": sum(row["bytes"] == 0 for row in receipt["members"]),
            "all_samples_warmups_outliers_and_errors_retained": True,
            "all_duplicate_aggregate_step_and_launch_phase_and_csv_files_retained": True,
            "existing_empty_artifact_files_retained": True,
            "source_outputs_absent_from_original_archive": [path for path in missing if path not in originals],
            "missing_outputs_not_synthesized": True,
            "source_guard_proof": "Consult the independent QA, full job log and unchanged harness guards. Missing raw status/diff output is explicitly a transport-evidence limitation.",
            "selected_trace_count": len(selected), "selected_trace_paths": sorted(selected),
            "omitted_trace_count": counts["omitted_trace"],
            "all_1012_hashes_and_exact_omission_list": "artifact-member-index.json.gz",
            "trace_replay_limitation": "Re-running the audit of all 848 traces requires the full original ZIP. This reduced public bundle preserves every phase/resource observation and selected diagnostic traces, not every trace payload.",
            "interim_poll_snapshots": "Retained locally; public bundle includes final provider metadata only. No measurements are stored only in polling snapshots.",
            "private_owner_storage_receipt": "Not included in the public Git bundle.",
        },
        "compression": {
            "format": "gzip", "level": 9, "mtime": 0, "header_filename": "",
            "zlib_version": zlib.ZLIB_VERSION, "zlib_runtime_version": zlib.ZLIB_RUNTIME_VERSION,
            "verification": "Each compressed output was decompressed and compared byte-for-byte with its complete input; source/stored hashes are in content-manifest.json.gz.",
            "replay": "Decompress each .gz file and remove its final .gz suffix, retaining its directory. Do not filter rows or reclassify unavailable metrics as zero.",
        },
        "qa": {
            "final_review_received": args.qa_final, "files": sorted(qa_names), "report_statuses": qa_statuses,
            "history": "The first report, original QA source and contract are retained unchanged. The reviewed report is the current validation: it distinguishes declared nonreader skips, missing transport metadata and unavailable timeline metrics from invalid samples. No artifact observations were changed.",
            "scope": "Descriptive integrity/statistics audit; no physical-GPU proof and no representation-only app claim.",
        },
        "excluded_experiment": "No isolated flat/chunked Windows run data is included.",
    }
    add(encoded(bundle), "bundle.json", "bundle_contract")
    add(Path(__file__).read_bytes(), "repro/prepare_public_bundle.py", "packaging_source")
    public_inventory = {
        "scope": "Every public payload file except this content-manifest itself; its Git object identifies the manifest bytes.",
        "run_id": RUN, "run_attempt": 1, "artifact_id": ARTIFACT,
        "files": [{key: row[key] for key in [
            "relative_path", "bytes", "sha256", "source_kind", "source_bytes", "source_sha256", "transformation"
        ]} for row in sorted(files, key=lambda item: item["relative_path"])],
    }
    add(encoded(public_inventory), "content-manifest.json", "public_content_index", gz=True)
    files.sort(key=lambda row: row["repo_path"])
    assert len({row["repo_path"] for row in files}) == len(files)
    stage = {
        "prefix": PREFIX, "base_commit": BASE, "base_tree": BASE_TREE,
        "files": files, "file_count": len(files), "total_bytes": sum(row["bytes"] for row in files),
        "qa_final": args.qa_final, "artifact_disposition_counts": dict(counts),
        "no_samples_filtered": True, "signed_or_credential_query_urls_count": len(signed),
    }
    (output / "staged_content_manifest.json").write_bytes(encoded(stage))
    if not args.qa_final:
        print(json.dumps({key: value for key, value in stage.items() if key != "files"}, indent=2))
        return
    assert git(args.repo, "rev-parse", BASE + "^{tree}").decode().strip() == BASE_TREE
    before = entries(args.repo, BASE_TREE)
    assert not any(path.startswith(PREFIX + "/") for path in before)
    for row in files:
        data = Path(row["local_path"]).read_bytes()
        assert sha(data) == row["sha256"]
        row["git_blob_sha"] = git(args.repo, "hash-object", "-w", "--stdin", input=data).decode().strip()
    with tempfile.TemporaryDirectory(prefix="main-evidence-index-", dir=output) as temporary:
        env = os.environ.copy(); env["GIT_INDEX_FILE"] = str(Path(temporary) / "index")
        git(args.repo, "read-tree", BASE_TREE, env=env)
        updates = b"".join(f"{row['mode']} {row['git_blob_sha']}\t{row['repo_path']}\0".encode() for row in files)
        git(args.repo, "update-index", "-z", "--index-info", input=updates, env=env)
        tree = git(args.repo, "write-tree", env=env).decode().strip()
    after = entries(args.repo, tree)
    assert all(after.get(path) == value for path, value in before.items())
    assert set(after) - set(before) == {row["repo_path"] for row in files}
    publication = {**stage, "parent_sha": BASE, "expected_tree": tree, "files": files,
        "commit_message": "test(perf): preserve complete PR 4307 Windows observations and QA",
        "unchanged_existing_entries": len(before), "only_additions_under_prefix": True,
        "all_existing_entries_preserved": True, "no_commit_or_ref_created": True}
    (output / "git_publication_manifest.json").write_bytes(encoded(publication))
    print(json.dumps({key: value for key, value in publication.items() if key != "files"}, indent=2))


if __name__ == "__main__":
    main()
