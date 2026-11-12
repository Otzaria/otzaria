#!/usr/bin/env python3
"""Independent analysis entrypoint for isolated run 43294899743/1 only.

No measurements, builds, network calls or Git writes. Pass the extracted
directory that actually contains provenance.json; its name may be r4307p.
The existing QA and descriptive summary programs are used without modification.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

RUN = "43294899743"
ATTEMPT = "1"
CANDIDATE = "6aa411d774f453331d6821dbb5a68f1c3b78bd78"
BASELINE = "764abeeec8a81a0e081d951261c37dc15dbadec3"
HARDWARE = f"github-hosted-{RUN}-{ATTEMPT}"
CONTROL_TREE = "10fca460ba42e1f0fd82bc5d09b0d7a02d9b1131"
SOURCE_HASHES = {
    "qa_windows_reader.py": "171e7a08ca0f16624f4abfa6b8efcc6066259787a59c539d766e1668a88ab6f9",
    "windows-qa-input-contract.json": "e6e6826fc41275ede223ad3e3cc505a1cfa302914cb07340441a0aa41e838c7e",
    "summarize_windows_reader.py": "4c4cced12735ecf104825b3f32df1836975dff053bffb8a680f99d1da4938794",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_new(path, value):
    with path.open("x", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=2, allow_nan=False)
        f.write("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("artifact_root", nargs="?", type=pathlib.Path)
    ap.add_argument("--repo", required=True, type=pathlib.Path)
    ap.add_argument("--output-directory", type=pathlib.Path)
    ap.add_argument("--prepare-only", action="store_true")
    args = ap.parse_args()
    here = pathlib.Path(__file__).resolve().parent
    for name, expected in SOURCE_HASHES.items():
        if sha(here / name) != expected:
            ap.error(f"Frozen analysis source changed: {name}; record a reviewed version explicitly")
    def git(*items):
        return subprocess.check_output(["git", "-C", str(args.repo), *items], text=True).strip()
    if git("show", "-s", "--format=%P", BASELINE) != CANDIDATE:
        ap.error("Control is not a direct single-parent child of candidate")
    if git("rev-parse", BASELINE + "^{tree}") != CONTROL_TREE:
        ap.error("Unexpected control tree")
    if git("diff", "--name-status", "--no-renames", CANDIDATE, BASELINE) != "M\tlib/text_book/bloc/text_book_bloc.dart":
        ap.error("Unexpected control changed-file inventory")
    prepared = {"runId": RUN, "attempt": ATTEMPT, "comparisonDesign": "representation-only",
                "candidate": CANDIDATE, "baselineFlatControl": BASELINE, "hardwareId": HARDWARE,
                "controlTree": CONTROL_TREE, "sourceHashes": SOURCE_HASHES,
                "preparedOnly": args.prepare_only}
    if args.prepare_only:
        print(json.dumps(prepared))
        return 0
    if args.artifact_root is None or args.output_directory is None:
        ap.error("artifact_root and --output-directory are required to analyze data")
    root, output = args.artifact_root.resolve(), args.output_directory.resolve()
    if not (root / "provenance.json").is_file():
        ap.error("artifact_root must contain provenance.json")
    if output == root or root in output.parents:
        ap.error("Outputs must be outside the raw artifact")
    files = {kind: output / f"windows-representation-only-{RUN}-{ATTEMPT}-{kind}.json"
             for kind in ("invocation", "qa", "diagnostics", "summary")}
    if any(path.exists() for path in files.values()):
        ap.error("Output exists; retain the first attempt and use a new directory for a reviewed rerun")
    output.mkdir(parents=True, exist_ok=True)
    qc = [sys.executable, str(here / "qa_windows_reader.py"), str(root),
          "--expected-candidate", CANDIDATE, "--expected-baseline", BASELINE,
          "--comparison-design", "representation-only", "--expected-hardware-id", HARDWARE,
          "--repo", str(args.repo.resolve()), "--output", str(files["qa"])]
    dc = [sys.executable, str(here / "summarize_windows_reader.py"), str(root),
          str(files["qa"]), "--output", str(files["diagnostics"])]
    write_new(files["invocation"], {**prepared,
        "startedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "artifactRoot": str(root), "qaCommand": qc, "diagnosticsCommand": dc,
        "entrypointSha256": sha(pathlib.Path(__file__))})
    completed = subprocess.run(qc, check=False)
    if completed.returncode:
        print(json.dumps({"status": "QA errors; no performance interpretation generated",
                          "retainedQa": str(files["qa"])}))
        return completed.returncode
    qa = read(files["qa"])
    if (qa["run_identity"]["github_run_id"], qa["run_identity"]["github_run_attempt"]) != (RUN, ATTEMPT):
        raise SystemExit("Unexpected run identity; do not combine artifacts")
    subprocess.run(dc, check=True)
    diagnostics = read(files["diagnostics"])
    assert len(diagnostics["scenarios"]) == 21 and diagnostics["counts"]["measuredActions"] == 672
    summary = {**prepared, **{k: qa[k] for k in
        ("run_identity", "source_comparison", "evidence_status", "metric_validity", "design", "errors", "warnings")},
        **{k: diagnostics[k] for k in ("machine", "counts", "scenarios", "timeline")},
        "allOutliersRetained": True,
        "sourceCaveats": [
            "Flat mutability and internal/state flag identity are representation-mediated differences; first ContentLineChanges may differ.",
            "Readiness scans and polling depend on representation; warmup_complete is not an isolated product-loading timer.",
            "FrameTiming arrays and pipeline trace availability are separate evidence categories.",
            "No cross-run or cross-machine pooling, even if CPU model strings match."],
        "automaticPerformanceThreshold": None,
        "stateRecommendation": "None generated automatically; review actual interaction/frame evidence against existing author/reviewer hold, including physical-GPU and behavioral requirements.",
        "limitations": qa["limitations"] + diagnostics["interpretationLimits"],
        "files": {k: {"name": v.name, "sha256": sha(v)} for k, v in files.items() if k != "summary"}}
    write_new(files["summary"], summary)
    print(json.dumps({"status": qa["evidence_status"], "outputs": {
        k: {"path": str(v), "bytes": v.stat().st_size, "sha256": sha(v)} for k, v in files.items()}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
