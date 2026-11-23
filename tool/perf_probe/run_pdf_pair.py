"""Run two immutable PDF source snapshots in one Windows host session."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid


HARNESS_PATHS = (
    "tool/perf_probe",
    "integration_test",
    "test_driver",
    "lib/core/diagnostics",
    "lib/pdf_book/models/pdf_book_render_observation.dart",
)
DEPENDENCY_PATHS = ("pubspec.yaml", "pubspec.lock")
PDF_TESTS = (
    "test/pdf_book/book_view_layout_memo_test.dart",
    "test/pdf_book/pdf_book_view_current_page_test.dart",
    "test/tool/perf_probe/pdf_reader_probe_test.dart",
    "test/tool/perf_probe/pdf_book_reader_probe_test.dart",
    "test/tool/perf_probe/report_test.dart",
)


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def full_sha(value: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError("Both revisions must be full lowercase 40-character commit SHAs.")
    return value


def capture(command: list[str], cwd: Path) -> str:
    return subprocess.check_output(command, cwd=cwd, text=True, encoding="utf-8").strip()


def git(repo: Path, *arguments: str) -> str:
    return capture(["git", "-C", str(repo), *arguments], repo)


def source_identity(repo: Path, commit: str) -> dict:
    full_sha(commit)
    if git(repo, "rev-parse", "--verify", f"{commit}^{{commit}}") != commit:
        raise ValueError("A source revision did not resolve to the requested commit.")
    return {
        "commit": commit,
        "tree": git(repo, "rev-parse", f"{commit}^{{tree}}"),
        "harnessObjects": {p: git(repo, "rev-parse", f"{commit}:{p}") for p in HARNESS_PATHS},
        "dependencyObjects": {p: git(repo, "rev-parse", f"{commit}:{p}") for p in DEPENDENCY_PATHS},
    }


def verify_sources(repo: Path, commits: dict, expected_paths: list[str] | None = None) -> dict:
    sources = {role: source_identity(repo, sha) for role, sha in commits.items()}
    before, after = sources["baseline"], sources["candidate"]
    if before["commit"] == after["commit"] or before["tree"] == after["tree"]:
        raise ValueError("A paired experiment requires two distinct source snapshots.")
    for field in ("harnessObjects", "dependencyObjects"):
        if before[field] != after[field]:
            raise ValueError(f"The snapshots have different {field}; they are not comparable.")
    paths = git(repo, "diff", "--name-only", "--no-renames", before["commit"], after["commit"]).splitlines()
    if expected_paths is not None and sorted(paths) != sorted(expected_paths):
        raise ValueError("The fixed experiment no longer has its declared source delta.")
    return {"sources": sources, "changedPaths": paths}


def verify_checkout(path: Path, commit: str) -> None:
    if git(path, "rev-parse", "HEAD") != commit:
        raise ValueError(f"The measured checkout changed revision: {path}")
    if git(path, "status", "--porcelain=v1", "--untracked-files=all"):
        raise ValueError(f"The measured checkout is dirty: {path}")


def sdk_identity(flutter: str, cwd: Path) -> dict:
    sdk = json.loads(capture([flutter, "--version", "--machine"], cwd))
    identity = {k: sdk[k] for k in (
        "frameworkVersion", "frameworkRevision", "engineRevision", "dartSdkVersion"
    )}
    if identity["frameworkVersion"] != "3.47.7":
        raise ValueError("This experiment requires the pinned Flutter 3.47.7 SDK.")
    return identity


def run_logged(command: list[str], cwd: Path, log: Path) -> float:
    print(f"Running {log.stem} (log: {log})", flush=True)
    started = time.monotonic()
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text(encoding="utf-8", errors="replace").splitlines()[-60:]), file=sys.stderr)
        raise RuntimeError(f"{log.stem} failed ({result.returncode}); inspect {log}.")
    return time.monotonic() - started


def verify_iterations(row: dict, launches: int, repetitions: int, warmup: bool) -> None:
    expected = [(launch, False, iteration) for launch in range(launches) for iteration in range(repetitions)]
    if warmup:
        expected += [(launch, True, 0) for launch in range(launches)]
    actual = []
    for sample in row.get("samples", []):
        if (type(sample.get("launchIndex")) is not int or type(sample.get("iteration")) is not int
                or type(sample.get("warmup")) is not bool or sample.get("status") != "passed"):
            raise ValueError(f"Invalid iteration evidence for {row['name']}.")
        actual.append((sample["launchIndex"], sample["warmup"], sample["iteration"]))
    if sorted(actual) != sorted(expected) or row.get("warmupExcluded") != (launches if warmup else 0):
        raise ValueError(f"Missing, duplicate or unexpected iterations for {row['name']}.")


def validate_reports(reports: dict, commits: dict, settings: dict, hardware_id: str, sdk: dict) -> dict:
    expected = {
        "buildMode": settings["mode"], "cacheState": settings["cacheState"],
        "launchCount": settings["launches"], "repetitions": settings["repetitions"],
        "warmup": 1, "bindingMode": "framework", "hardwareId": hardware_id,
        "flutterVersion": sdk["frameworkRevision"],
    }
    prefix = "pdf.book_view" if settings["scenario"] == "pdf-book-view" else "pdf.reader"
    actions = {"open", "jump_forward", "jump_backward", "close", "idle_after_close"}
    actions |= {"thumbnails_first_image", "prepare_reversals", "rapid_reversals"} if prefix == "pdf.book_view" else {"zoom"}
    required = {"startup.first_content", "startup.window_useful"} | {f"{prefix}.{p}" for p in actions}
    uninstrumented = {"windows.native_open_close", "queues.depth", f"{prefix}.first_preview_image"}
    names, skipped = {}, {}
    for role, report in reports.items():
        if (report.get("sourceSchemaVersion") != 2 or report.get("complete") is not True
                or report.get("successful") is not True or report.get("comparisonEligibility") != []):
            raise ValueError(f"{role} is incomplete, unsuccessful, or ineligible for comparison.")
        metadata = report.get("metadata", {})
        if metadata.get("dirty") is not False or metadata.get("commit") != commits[role]:
            raise ValueError(f"{role} did not measure the requested clean commit.")
        if any(type(metadata.get(k)) is not type(value) or metadata[k] != value for k, value in expected.items()):
            raise ValueError(f"{role} measured different settings, hardware or Flutter SDK.")
        if metadata.get("settings", {}).get("scenarioSet") != settings["scenario"]:
            raise ValueError(f"{role} measured the wrong PDF scenario.")
        rows = report.get("scenarios", [])
        names[role] = [row.get("name") for row in rows]
        if any(not isinstance(n, str) for n in names[role]) or len(set(names[role])) != len(rows):
            raise ValueError(f"{role} has invalid or duplicate scenario identities.")
        if not required <= set(names[role]):
            raise ValueError(f"{role} lacks required PDF or startup observations.")
        skipped[role] = {}
        for row in rows:
            name = row["name"]
            if row.get("status") == "skipped" and name in uninstrumented:
                samples = row.get("samples", [])
                if (row.get("measured") != 0 or row.get("latencyMs") is not None or row.get("failures") != 0
                        or len(samples) != settings["launches"] or any(
                            sample.get("status") != "skipped" or not isinstance(sample.get("reason"), str)
                            or not sample["reason"].strip() for sample in samples)):
                    raise ValueError(f"{role} lacks explicit unavailable evidence for {name}.")
                skipped[role][name] = [sample["reason"] for sample in samples]
            elif row.get("status") != "passed":
                raise ValueError(f"{role} has a failed, partial or unexpectedly skipped scenario: {name}.")
            elif name in required:
                startup = name.startswith("startup.")
                repetitions = 1 if startup else settings["repetitions"]
                count = settings["launches"] * repetitions
                if type(row.get("measured")) is not int or row["measured"] != count:
                    raise ValueError(f"{role} has the wrong number of measured repetitions for {name}.")
                verify_iterations(row, settings["launches"], repetitions, not startup)
    if skipped["baseline"] != skipped["candidate"]:
        raise ValueError("Unavailable observations differ between the two snapshots.")
    for field in ("machine", "engineIdentity"):
        before = reports["baseline"]["metadata"].get(field)
        if not before or before != reports["candidate"]["metadata"].get(field):
            raise ValueError(f"The measured {field} changed between snapshots.")
    comparison = reports["candidate"].get("comparison", {})
    if comparison.get("comparable") is not True or comparison.get("reasons") != []:
        raise ValueError(f"The existing comparator rejected this pair: {comparison.get('reasons')}")
    if any(comparison.get(f"{role}Commit") != sha for role, sha in commits.items()):
        raise ValueError("The comparison refers to different source commits.")
    rows = comparison.get("scenarios", [])
    compared = [row.get("name") for row in rows]
    if (set(names["baseline"]) != set(names["candidate"]) or set(compared) != set(names["baseline"])
            or len(compared) != len(set(compared)) or any(
                row.get("status") != ("unavailable" if row.get("name") in skipped["baseline"] else "compared")
                or (row.get("name") in skipped["baseline"] and "metrics" in row) for row in rows)):
        raise ValueError("Some intended scenarios were missing or were not actually compared.")
    return comparison


def run_pair(args: argparse.Namespace) -> None:
    source, output = args.source.resolve(), args.output.resolve()
    if output == source or output.is_relative_to(source):
        raise ValueError("Results and temporary worktrees must be outside the source checkout.")
    experiment = read_json(args.experiment) if not args.baseline and not args.candidate else None
    commits = {role: full_sha(getattr(args, role) or experiment[role]) for role in ("baseline", "candidate")}
    if args.mode == "release" and not re.fullmatch(r"[0-9a-f]{64}", args.expected_engine_sha256):
        raise ValueError("Release pairs require the verified patched Windows engine SHA-256.")
    identities = verify_sources(source, commits, experiment.get("changedPaths") if experiment else None)
    if platform.system() != "Windows":
        raise ValueError("Native paired measurements require Windows; contract tests are portable.")
    flutter, dart, pwsh = (shutil.which(name) for name in ("flutter", "dart", "pwsh"))
    if not all((flutter, dart, pwsh)):
        raise ValueError("Flutter, Dart and PowerShell must be available on PATH.")
    output.mkdir(parents=True, exist_ok=False)
    logs = output / "logs"
    logs.mkdir()
    (output / "results").mkdir()
    (output / "worktrees").mkdir()
    case = output / "pdf-case.json"
    write_json(case, {"schemaVersion": 1, "source": {
        "kind": "generated", "pageCount": args.pages, "mixedPageSizes": True,
    }})
    settings = {"mode": args.mode, "cacheState": args.cache_state, "scenario": args.scenario,
                "pages": args.pages, "launches": args.launches, "repetitions": args.repetitions}
    order = ["baseline", "candidate"] if args.order == "baseline-first" else ["candidate", "baseline"]
    hardware_id = f"paired-{platform.node()}-{uuid.uuid4().hex}"
    receipt = {
        "schemaVersion": 1, "status": "running", **identities, "settings": settings,
        "experiment": experiment or {"kind": "operator-selected immutable source pair"},
        "order": order, "hardwareId": hardware_id, "host": platform.node(),
        "startedAtEpochMs": time.time_ns() // 1_000_000,
        "orchestratorCommit": git(source, "rev-parse", "HEAD"),
        "orchestratorSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "pdfCaseSha256": hashlib.sha256(case.read_bytes()).hexdigest(),
        "workflow": {key: os.environ.get(key) for key in (
            "GITHUB_REPOSITORY", "GITHUB_WORKFLOW_REF", "GITHUB_WORKFLOW_SHA", "GITHUB_SHA",
            "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB"
        )},
        "coldDefinition": "fresh application data; OS file cache is not flushed",
        "stages": {},
    }
    created = []
    try:
        receipt["sdk"] = sdk_identity(flutter, source)
        write_json(output / "pair.json", receipt)
        for role in order:
            checkout = output / "worktrees" / role
            git(source, "worktree", "add", "--detach", str(checkout), commits[role])
            created.append(checkout)
            verify_checkout(checkout, commits[role])
            if sdk_identity(flutter, checkout) != receipt["sdk"]:
                raise ValueError("The Flutter/Dart/engine SDK changed during the pair.")
            stages = receipt["stages"][role] = {}
            for stage, arguments in (
                ("resolve", ["pub", "get", "--enforce-lockfile"]),
                ("analyze", ["analyze", "--no-pub"]),
                ("tests", ["test", "--no-pub", "--reporter", "expanded", *PDF_TESTS]),
            ):
                stages[stage] = run_logged([flutter, *arguments], checkout, logs / f"{role}-{stage}.log")
                verify_checkout(checkout, commits[role])
                write_json(output / "pair.json", receipt)
            arguments = [
                pwsh, "-NoProfile", "-File", str(checkout / "tool/perf_probe/run_perf_probe.ps1"),
                "-Mode", args.mode, "-CacheState", args.cache_state,
                "-ScenarioSet", args.scenario, "-BindingMode", "framework",
                "-Launches", str(args.launches), "-Repetitions", str(args.repetitions), "-Warmup", "1",
                "-PdfCase", str(case), "-OutputDirectory", str(output / "results" / role),
                "-HardwareId", hardware_id,
            ]
            if args.expected_engine_sha256:
                arguments.extend(["-ExpectedEngineSha256", args.expected_engine_sha256])
            stages["nativeBuildAndRuns"] = run_logged(arguments, checkout, logs / f"{role}-native.log")
            verify_checkout(checkout, commits[role])
            if sdk_identity(flutter, checkout) != receipt["sdk"]:
                raise ValueError("The Flutter/Dart/engine SDK changed after measurement.")
            write_json(output / "pair.json", receipt)
        candidate = output / "worktrees/candidate"
        run_logged([dart, "tool/perf_probe/analyze.dart", str(output / "results/candidate"),
                    "--baseline", str(output / "results/baseline")], candidate, logs / "comparison.log")
        reports = {role: read_json(output / "results" / role / "report.json") for role in commits}
        receipt["comparison"] = validate_reports(reports, commits, settings, hardware_id, receipt["sdk"])
        for role in commits:
            verify_checkout(output / "worktrees" / role, commits[role])
        receipt["status"] = "passed"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["error"] = str(error)
        raise
    finally:
        cleanup_errors = []
        for checkout in reversed(created):
            try:
                git(source, "worktree", "remove", "--force", str(checkout))
            except (OSError, subprocess.CalledProcessError) as error:
                cleanup_errors.append(str(error))
        receipt["endedAtEpochMs"] = time.time_ns() // 1_000_000
        if cleanup_errors:
            receipt["status"] = "failed"
            receipt["cleanupErrors"] = cleanup_errors
        write_json(output / "pair.json", receipt)
        if cleanup_errors:
            raise RuntimeError("Could not remove the experiment's temporary worktrees.")
    print(f"Comparable native measurements saved in {output}; no performance threshold was applied.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--experiment", type=Path, default=Path(__file__).with_name("pdf_layout_pair.json"))
    parser.add_argument("--baseline")
    parser.add_argument("--candidate")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=("profile", "release"), default="profile")
    parser.add_argument("--cache-state", choices=("cold", "warm"), default="cold")
    parser.add_argument("--scenario", choices=("pdf-reader", "pdf-book-view"), default="pdf-book-view")
    parser.add_argument("--pages", type=int, choices=(10, 100, 600, 1000, 10000), default=1000)
    parser.add_argument("--launches", type=int, choices=range(1, 31), default=3)
    parser.add_argument("--repetitions", type=int, choices=range(1, 101), default=5)
    parser.add_argument("--order", choices=("baseline-first", "candidate-first"), default="baseline-first")
    parser.add_argument("--expected-engine-sha256", default="")
    args = parser.parse_args()
    if bool(args.baseline) != bool(args.candidate):
        parser.error("Provide both --baseline and --candidate, or neither for the fixed experiment.")
    try:
        run_pair(args)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
