#!/usr/bin/env python3
"""Stage complete isolated-run observations, then freeze after the final QA handoff.

Reads local artifacts and immutable Git objects. It never downloads Actions
artifacts, changes refs, creates a commit, uploads files, or rewrites observations.
"""
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


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def read(path):
    return json.loads(path.read_bytes())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unwrap(value):
    if isinstance(value, str):
        return json.loads(value)
    if "structuredContent" in value:
        return unwrap(value["structuredContent"])
    if isinstance(value.get("content"), str):
        return json.loads(value["content"])
    return value


def git(repo, *args, input=None, env=None):
    return subprocess.check_output(["git", "-C", str(repo), *args], input=input, env=env)


def tree_entries(repo, tree):
    result = {}
    for row in git(repo, "ls-tree", "-rz", tree).split(b"\0"):
        if row:
            value, path = row.split(b"\t", 1)
            result[path.decode()] = value.decode()
    return result


def source_proof(config, repo):
    control, candidate = config["expected_baseline"], config["expected_candidate"]
    path = config["expected_changed_path"]
    assert git(repo, "rev-list", "--parents", "-n", "1", control).decode().split() == [control, candidate]
    assert git(repo, "merge-base", control, candidate).decode().strip() == candidate
    assert git(repo, "diff-tree", "--no-commit-id", "--name-status", "-r", candidate, control).decode().strip() == "M\t" + path
    assert git(repo, "rev-parse", control + "^{tree}").decode().strip() == config["expected_control_tree"]
    sources = {}
    for role, commit in [("flat_control", control), ("chunked_candidate", candidate)]:
        data = git(repo, "show", commit + ":" + path)
        sources[role] = {
            "commit": commit, "tree": git(repo, "rev-parse", commit + "^{tree}").decode().strip(),
            "path": path, "blob": git(repo, "rev-parse", commit + ":" + path).decode().strip(),
            "bytes": len(data), "sha256": sha(data),
        }
    assert sources["flat_control"]["sha256"] == config["expected_control_source_sha256"]
    patch = git(repo, "diff", "--no-ext-diff", "--full-index", candidate, control, "--", path)
    return {
        "comparison_design": "representation-only", "control_is_single_direct_child": True,
        "only_changed_product_path": path, "sources": sources,
        "patch_direction": "chunked candidate to flat control", "patch_sha256": sha(patch),
        "interpretation": "Integrated representation and update implementations, including immutable snapshot sharing and its effect on flag identity/contentChanges. All common guards, notes changes and harness source are shared.",
    }, patch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check-setup", action="store_true")
    parser.add_argument("--qa-file", action="append", type=Path, default=[])
    parser.add_argument("--reviewed-qa", type=Path)
    parser.add_argument("--trace-list", type=Path)
    parser.add_argument("--handoff-final", action="store_true")
    parser.add_argument("--freeze", action="store_true")
    parser.add_argument("--failure-evidence", action="store_true", help="Preserve an incomplete/invalid attempt without accepting it as a measured comparison")
    args = parser.parse_args()
    config = read(args.config)
    root = (args.run_dir or Path(config["run_dir"])).resolve()
    repo = (args.repo or Path(config["repo"])).resolve()
    output = (args.output or Path(config["output"])).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if not args.check_setup and (output / "git_publication_manifest.json").exists():
        raise RuntimeError("Frozen output exists; use an explicit new output directory/version")
    assert git(repo, "rev-parse", config["evidence_parent"] + "^{tree}").decode().strip() == config["evidence_base_tree"]
    proof, patch = source_proof(config, repo)
    if args.check_setup:
        result = {
            "setup_ready": True, "artifact_accessed": False, "measurements_run": False,
            "source_graph_verified": proof, "evidence_parent": config["evidence_parent"],
            "evidence_base_tree": config["evidence_base_tree"], "run_dir": str(root),
            "configuration_sha256": sha(args.config.read_bytes()), "script_sha256": sha(Path(__file__).read_bytes()),
        }
        (output / "setup-readiness.json").write_bytes(encoded(result))
        print(json.dumps({key: value for key, value in result.items() if key != "source_graph_verified"}, indent=2))
        return
    status = read(root / config["final_status"])
    run = unwrap(status["run"])
    jobs = status["jobs"]
    jobs = unwrap(jobs) if isinstance(jobs, dict) else jobs
    jobs = jobs["jobs"] if isinstance(jobs, dict) else jobs
    job = next(row for row in jobs if int(row["id"]) == config["job_id"])
    assert int(run["id"]) == config["run_id"] and int(run["run_attempt"]) == config["run_attempt"]
    assert run["head_sha"] == config["workflow_head"]
    receipt = read(root / config["artifact_receipt"])
    for key in ["run_id", "run_attempt", "job_id"]:
        assert int(receipt[key]) == config[key]
    assert receipt["all_zip_member_crcs_valid"] and receipt["all_zip_paths_checked_before_extraction"]
    assert receipt["all_members_preserved"] and receipt["declared_digest_matches"]
    artifact_metadata = unwrap(read(root / config["artifact_metadata"]))
    if "artifacts" in artifact_metadata:
        artifact = next(row for row in artifact_metadata["artifacts"] if row["id"] == receipt["artifact_id"])
    else:
        artifact = artifact_metadata.get("artifact", artifact_metadata)
    assert artifact["id"] == receipt["artifact_id"]
    assert artifact["digest"] == "sha256:" + receipt["zip_sha256"]
    assert artifact["size_in_bytes"] == receipt["zip_bytes"]
    if artifact.get("workflow_run"):
        assert int(artifact["workflow_run"]["id"]) == config["run_id"]
    extracted = Path(receipt["extracted_root"]).resolve()
    assert extracted.is_relative_to(root) and extracted.is_dir()
    members = {row["path"]: row for row in receipt["members"]}
    assert len(members) == receipt["member_count"]
    selected_list = read(args.trace_list) if args.trace_list else []
    assert isinstance(selected_list, list) and len(set(selected_list)) == len(selected_list)
    selected = set(selected_list)
    assert selected <= set(members) and all(Path(path).name.startswith("reader_trace") for path in selected)
    qa_paths = list(args.qa_file)
    if args.reviewed_qa and args.reviewed_qa not in qa_paths:
        qa_paths.append(args.reviewed_qa)
    qa = read(args.reviewed_qa) if args.reviewed_qa else None
    if args.freeze:
        assert args.handoff_final, "A final handoff is required before freezing"
        assert run["status"] == "completed" and job["status"] == "completed"
        if not args.failure_evidence:
            assert qa is not None and not qa.get("errors")
            assert qa["comparison_design"] == "representation-only"
            assert qa["expected_baseline"] == config["expected_baseline"] and qa["expected_candidate"] == config["expected_candidate"]
            assert qa["passed_structural_and_statistical_checks"]
            assert str(qa["run_identity"]["github_run_id"]) == str(config["run_id"])
            assert str(qa["run_identity"]["github_run_attempt"]) == str(config["run_attempt"])
    payload = output / "payload"
    payload.mkdir(exist_ok=True)
    cache_path = output / "staged_content_manifest.json"
    cache = {row["relative_path"]: row for row in read(cache_path)["files"]} if cache_path.exists() else {}
    files, dispositions, sensitive_paths = [], [], []

    def add(data, path, kind, original=None, compress=False):
        try:
            text = data.decode("utf-8")
            utf8 = True
            for url in re.findall(r"https?://[^\s<>\"']+", text.replace("\\/", "/")):
                if re.search(r"[?&](?:sig|signature|token|access_token|auth|se|sp|sv|X-Amz-Signature|X-Goog-Signature)=", url, re.I):
                    sensitive_paths.append(path)
        except UnicodeDecodeError:
            utf8 = False
        original_sha = sha(data)
        relative = path + ".gz" if compress else path
        destination = payload / relative
        previous = cache.get(relative)
        if previous and previous["source_sha256"] == original_sha and destination.exists() and sha(destination.read_bytes()) == previous["sha256"]:
            saved = destination.read_bytes()
        else:
            if compress:
                buffer = io.BytesIO()
                with gzip.GzipFile(fileobj=buffer, mode="wb", filename="", mtime=0, compresslevel=9) as stream:
                    stream.write(data)
                saved = buffer.getvalue()
                assert gzip.decompress(saved) == data
            else:
                saved = data
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(saved)
        row = {
            "repo_path": config["prefix"] + "/" + relative, "relative_path": relative,
            "local_path": str(destination), "mode": "100644", "type": "blob",
            "encoding": "utf-8" if utf8 and not compress else "base64",
            "bytes": len(saved), "sha256": sha(saved), "source_kind": kind, "source_path": original,
            "source_bytes": len(data), "source_sha256": original_sha,
            "transformation": "lossless gzip, mtime=0, filename empty, level=9" if compress else "byte-for-byte copy",
        }
        files.append(row)
        return row

    provenance_paths = []
    for path, member in members.items():
        if member.get("directory"):
            dispositions.append({**member, "public_bundle": "directory_metadata_only",
                                 "reason": "Directory preserved in index and ZIP; Git has no empty-directory objects"})
            continue
        is_trace = Path(path).name.startswith("reader_trace")
        disposition = dict(member)
        if is_trace and path not in selected:
            disposition.update(public_bundle="omitted_trace", reason="Retained in the full verified ZIP; diagnostic trace subset only in Git")
        else:
            data = (extracted / path).read_bytes()
            assert len(data) == member["bytes"] and sha(data) == member["sha256"]
            zipped = is_trace or path.endswith((".jsonl", ".ndjson")) or (path.endswith((".json", ".log")) and len(data) > 65536)
            saved = add(data, "artifact/" + path, "diagnostic_trace" if is_trace else "artifact_member", path, zipped)
            disposition.update(public_bundle="included", bundle_path=saved["relative_path"], stored_sha256=saved["sha256"])
            if Path(path).name == "provenance.json":
                value = json.loads(data)
                if "baselineSourceCommit" in value:
                    provenance_paths.append((path, value))
        dispositions.append(disposition)
    if not args.failure_evidence:
        assert len(provenance_paths) == 1, "One measured comparison provenance is required"
        provenance = provenance_paths[0][1]
        assert provenance["baselineSourceCommit"] == config["expected_baseline"]
        assert provenance["candidateSourceCommit"] == config["expected_candidate"]
        assert provenance["harnessSourceCommit"] == config["expected_candidate"]
        if args.freeze:
            assert provenance["status"] == "passed"
    for relative in config["required_public_metadata"] + config["optional_public_metadata"]:
        path = root / relative
        if not path.exists() and relative in config["optional_public_metadata"]:
            continue
        data = path.read_bytes()
        add(data, "metadata/" + relative, "public_provider_or_extraction_metadata", relative, len(data) > 65536 or relative.endswith(".log"))
    qa_names = set()
    for path in qa_paths:
        assert path.name not in qa_names
        qa_names.add(path.name)
        data = path.read_bytes()
        compress_qa = path.suffix.lower() in {".json", ".jsonl", ".ndjson", ".log"} and len(data) > 65536
        add(data, "qa/" + path.name, "qa_source_or_result", str(path), compress_qa)
    if args.trace_list:
        add(args.trace_list.read_bytes(), "qa/diagnostic-trace-paths.json", "explicit_trace_selection", str(args.trace_list))
    add(encoded(proof), "source/representation-source-proof.json", "independent_git_source_graph")
    add(patch, "source/representation-only.patch", "immutable_source_diff")
    counts = Counter(row["public_bundle"] for row in dispositions)
    missing_source_outputs = []
    for provenance_path, _ in provenance_paths:
        directory = Path(provenance_path).parent
        for side in ["baseline", "candidate"]:
            for suffix in ["status.txt", "diff.patch"]:
                expected = (directory / f"{side}-{suffix}").as_posix()
                if expected not in members:
                    missing_source_outputs.append(expected)
    index = {
        "run_id": config["run_id"], "run_attempt": config["run_attempt"], "artifact_id": receipt["artifact_id"],
        "original_zip_sha256": receipt["zip_sha256"], "all_original_members_indexed": len(dispositions),
        "disposition_counts": dict(counts), "omitted_non_trace_files": [], "omitted_logs": [],
        "samples_warmups_outliers_errors_filtered": False, "duplicate_and_empty_files_preserved": True,
        "members": dispositions,
    }
    add(encoded(index), "artifact-member-index.json", "complete_member_index", compress=True)
    bundle = {
        "comparison_design": "representation-only", "run_id": config["run_id"], "run_attempt": config["run_attempt"],
        "job_id": config["job_id"], "workflow_head": config["workflow_head"], "run_conclusion": run.get("conclusion"),
        "observation_integrity_qa_completed": bool(args.freeze and not args.failure_evidence),
        "performance_decision": "Not made by the packager", "failure_evidence_only": args.failure_evidence,
        "source_proof": "source/representation-source-proof.json",
        "artifact": {
            "id": artifact["id"], "name": artifact["name"], "sha256": receipt["zip_sha256"], "zip_bytes": receipt["zip_bytes"],
            "url": f"https://github.com/{config['repository']}/actions/runs/{config['run_id']}/artifacts/{artifact['id']}",
            "created_at": artifact.get("created_at"), "expires_at": artifact["expires_at"],
            "member_count": receipt["member_count"], "uncompressed_bytes": receipt["uncompressed_bytes"],
            "original_zip": "Preserved separately by owner; not embedded in Git",
        },
        "preservation": {
            "all_non_trace_file_bytes": True, "all_raw_statistical_observations": True,
            "all_duplicates_and_empty_files_present_in_zip": True, "no_sample_or_outlier_filtering": True,
            "selected_trace_count": len(selected), "omitted_trace_count": counts["omitted_trace"],
            "all_hashes_and_exact_omissions": "artifact-member-index.json.gz",
            "trace_replay_limitation": "Auditing every original trace requires the full ZIP. This bundle preserves all phase/resource observations and the explicit diagnostic trace subset.",
            "source_cleanliness_outputs_absent_from_zip": missing_source_outputs,
            "missing_original_outputs": "Missing files are not synthesized; source cleanliness limitations remain in final QA and full job log.",
            "private_owner_storage_receipt": "Not included",
        },
        "qa": {
            "final_handoff": args.handoff_final, "reviewed_report": args.reviewed_qa.name if args.reviewed_qa else None,
            "evidence_status": qa.get("evidence_status") if qa else None, "files": sorted(qa_names),
            "errors": len(qa.get("errors", [])) if qa else None,
            "warnings_by_code": dict(Counter(w.get("code", "unspecified") for w in qa.get("warnings", []))) if qa else {},
            "history": "All supplied original and reviewed QA outputs and source versions are preserved; artifact bytes are unchanged.",
        },
        "compression": {"format": "gzip", "mtime": 0, "filename": "", "level": 9,
            "zlib_version": zlib.ZLIB_VERSION, "zlib_runtime_version": zlib.ZLIB_RUNTIME_VERSION,
            "proof": "New gzip outputs are decompressed and compared byte-for-byte; staged objects are reused only after source/stored hash checks.",
            "replay": "Decompress .gz files, remove only final .gz suffix, keep paths. Hashes are in content-manifest.json.gz."},
        "scope": "Hosted Windows representation/list-update comparison with shared common logic. Physical GPU remains unverified. Whole-PR data is excluded.",
    }
    add(encoded(bundle), "bundle.json", "bundle_contract")
    add(args.config.read_bytes(), "repro/packaging-config.json", "packaging_configuration")
    add(Path(__file__).read_bytes(), "repro/package_isolated.py", "packaging_source")
    content_index = {"scope": "All payload files except this index itself", "files": [
        {key: row[key] for key in ["relative_path", "bytes", "sha256", "source_kind", "source_bytes", "source_sha256", "transformation"]}
        for row in sorted(files, key=lambda row: row["relative_path"])]}
    add(encoded(content_index), "content-manifest.json", "public_content_index", compress=True)
    assert not sensitive_paths, "Signed/credential query URL in: " + ", ".join(sorted(set(sensitive_paths)))
    files.sort(key=lambda row: row["repo_path"])
    assert len(files) == len({row["repo_path"] for row in files})
    stage = {
        "parent_sha": config["evidence_parent"], "base_tree": config["evidence_base_tree"], "prefix": config["prefix"],
        "run_id": config["run_id"], "run_attempt": config["run_attempt"], "artifact_id": artifact["id"],
        "comparison_design": "representation-only", "files": files, "file_count": len(files),
        "total_bytes": sum(row["bytes"] for row in files), "artifact_disposition_counts": dict(counts),
        "qa_final": args.handoff_final, "failure_evidence_only": args.failure_evidence,
        "signed_or_credential_query_urls_count": len(sensitive_paths),
    }
    cache_path.write_bytes(encoded(stage))
    if not args.freeze:
        print(json.dumps({key: value for key, value in stage.items() if key != "files"}, indent=2))
        return
    before = tree_entries(repo, config["evidence_base_tree"])
    assert not any(row["repo_path"] in before for row in files)
    for row in files:
        data = Path(row["local_path"]).read_bytes()
        assert len(data) == row["bytes"] and sha(data) == row["sha256"]
        row["git_blob_sha"] = git(repo, "hash-object", "-w", "--stdin", input=data).decode().strip()
    with tempfile.TemporaryDirectory(prefix="isolated-evidence-index-", dir=output) as temporary:
        env = os.environ.copy(); env["GIT_INDEX_FILE"] = str(Path(temporary) / "index")
        git(repo, "read-tree", config["evidence_base_tree"], env=env)
        index_data = b"".join(f"{row['mode']} {row['git_blob_sha']}\t{row['repo_path']}\0".encode() for row in files)
        git(repo, "update-index", "-z", "--index-info", input=index_data, env=env)
        tree = git(repo, "write-tree", env=env).decode().strip()
    after = tree_entries(repo, tree)
    assert all(after.get(path) == value for path, value in before.items())
    assert set(after) - set(before) == {row["repo_path"] for row in files}
    encodings = Counter(row["encoding"] for row in files)
    largest = max(files, key=lambda row: row["bytes"])
    manifest = {**stage, "files": files, "expected_tree": tree,
        "commit_message": "test(perf): preserve isolated PR 4307 representation observations and QA",
        "encoding_counts": dict(encodings), "distinct_blob_count": len({row["git_blob_sha"] for row in files}),
        "maximum_file": {key: largest[key] for key in ["repo_path", "bytes", "encoding"]},
        "unchanged_existing_entries": len(before), "all_existing_entries_preserved": True,
        "no_commit_or_ref_created": True}
    target = output / "git_publication_manifest.json"
    assert not target.exists(), "Frozen manifest exists; use an explicit new output directory/version"
    target.write_bytes(encoded(manifest))
    (output / "git_tree_entries.json").write_bytes(encoded({"base_tree": config["evidence_base_tree"],
        "tree": [{"path": row["repo_path"], "mode": row["mode"], "type": row["type"], "sha": row["git_blob_sha"]} for row in files]}))
    print(json.dumps({**{key: value for key, value in manifest.items() if key != "files"}, "manifest_sha256": sha(target.read_bytes())}, indent=2))


if __name__ == "__main__":
    main()
