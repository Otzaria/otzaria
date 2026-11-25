"""Build and verify the pinned public text pipeline as a Linux Dart AOT component."""

import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shlex
import struct
import subprocess
import sys
import traceback


PDFIUM_SHA256 = "1c251efce460d67437a4c76d4be9033ae2f17bf5603f5bff1af10209b94ca723"
CORPUS_SHA256 = "3f148e978f8bdb29f499a9dc229d05708bf0e7c895ee9f4469300f3f8ce8cfb4"
FONT_SHA256 = "054f3f97a338070c3558a9ce7e302565be85c7436b10bb0a01cf6a41f0782e61"
FRAMEWORK_REVISION = "abaf9c523780a608bd46686fd5e53740a07077f8"
ENGINE_REVISION = "deb287481e3ce9468f3434937ced4240a70539ca"
CORPUS_KINDS = ("hebrew", "niqqud", "columns", "mixed_direction", "rotate_90", "rotate_270", "visual_order", "legacy_map")
POINTED_TEXT_OBSERVATION = {
    "kind": "pdfium-inserted-spaces", "pages": [2, 10, 18, 26],
    "extractedLine": "שָׁ לוֹם עוֹלָ ם", "niqqudMarksPerPage": 60,
    "queryId": "niqqud_tolerant", "matchesPerPage": 0,
}
SOURCE_FILES = (
    "pubspec.yaml",
    "pubspec.lock",
    "fonts/Tinos-Regular.ttf",
    "lib/main.dart",
    "tool/perf_probe/pdf_text_fixture.dart",
    "tool/perf_probe/run_pdf_text_profile.dart",
    "tool/perf_probe/run_pdf_text_profile.py",
    "tool/perf_probe/test_pdf_text_native.py",
    "tool/perf_probe/src/pdf_image_budget.dart",
    "tool/perf_probe/src/pdf_text_profile.dart",
    "tool/perf_probe/src/pdf_text_profile_report.dart",
    "tool/perf_probe/src/report.dart",
    "test/tool/perf_probe/pdf_text_profile_native_test.dart",
    "test/tool/perf_probe/pdf_text_profile_test.dart",
    "test/tool/perf_probe/pdf_text_profile_report_test.dart",
    ".github/workflows/pdf_text_pipeline.yml",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run(arguments, repo, *, log=None, timeout=300):
    try:
        result = subprocess.run(
            [str(value) for value in arguments], cwd=repo, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        if log is not None:
            partial = error.stdout or b""
            try:
                log.write_bytes(partial if isinstance(partial, bytes) else partial.encode("utf-8"))
            except OSError as log_error:
                print(f"Could not save partial command log: {log_error}", file=sys.stderr)
        raise
    if log is not None:
        log.write_text(result.stdout, encoding="utf-8")
    require(result.returncode == 0, f"Command failed ({result.returncode}): {arguments}\n{result.stdout[-6000:]}")
    return result.stdout


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def source_receipt(repo):
    dirty = run(["git", "status", "--porcelain", "--untracked-files=all", "--", *SOURCE_FILES], repo)
    require(not dirty, f"Measured source is dirty: {dirty}")
    entries = run(["git", "ls-tree", "-r", "HEAD", "--", *SOURCE_FILES], repo).splitlines()
    blobs = {line.split("\t", 1)[1]: line.split("\t", 1)[0].split()[2] for line in entries}
    require(set(blobs) == set(SOURCE_FILES), "Measured source is missing from HEAD")
    hashes = {}
    for name in SOURCE_FILES:
        path = repo / name
        require(path.is_file() and not path.is_symlink(), f"Measured input is not a regular file: {name}")
        data = path.read_bytes()
        blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        require(blob == blobs[name], f"Measured input differs from its HEAD blob: {name}")
        hashes[name] = hashlib.sha256(data).hexdigest()
    # The raw header retains parent IDs even in a shallow checkout.
    commit_header = run(["git", "cat-file", "commit", "HEAD"], repo).split("\n\n", 1)[0]
    return {
        "commit": run(["git", "rev-parse", "HEAD"], repo).strip(),
        "tree": run(["git", "rev-parse", "HEAD^{tree}"], repo).strip(),
        "parents": [line[7:] for line in commit_header.splitlines() if line.startswith("parent ")],
        "files": hashes,
        "blobs": blobs,
    }


def sdk_receipt(dart_version, flutter_json=None):
    require(re.search(r"Dart SDK version: 3\.13\.5(?:\s|\b)", dart_version), "Unexpected Dart SDK")
    result = {"dartVersionOutput": dart_version.strip(), "flutter": None}
    if flutter_json is not None:
        sdk = json.loads(flutter_json.read_text(encoding="utf-8"))
        require(sdk.get("frameworkVersion") == "3.47.7" and sdk.get("dartSdkVersion", "").startswith("3.13.5"), "Unexpected Flutter/Dart SDK")
        require(sdk.get("frameworkRevision") == FRAMEWORK_REVISION and sdk.get("engineRevision") == ENGINE_REVISION, "Unexpected Flutter/engine revision")
        result["flutter"] = sdk
    return result


def package_resolution_receipt(repo, packages):
    directories = [repo / "tool/perf_probe", repo / "tool", repo]
    for directory in directories:
        config = directory / ".dart_tool/package_config.json"
        graph = directory / ".dart_tool/package_graph.json"
        if config.is_file() and graph.is_file():
            require(directory == repo, "Nested Dart package discovery differs from the repository root")
            require(not config.is_symlink() and not graph.is_symlink(), "Dart package resolution must use regular generated files")
            require(packages.resolve() == config.resolve(), "Use the repository package config generated by pinned pub get")
            return {"packageConfigSha256": digest(config), "packageGraphSha256": digest(graph)}
    raise ValueError("Missing package_config.json/package_graph.json pair at the repository root; run pinned pub get first. Refusing implicit dependency resolution.")


def compiler_dependencies(depfile, repo):
    repo = repo.resolve()
    text = depfile.read_text(encoding="utf-8").replace("\\\n", "")
    require(": " in text, "Missing compiler dependency output")
    paths = {Path(value).resolve() for value in shlex.split(text.split(": ", 1)[1])}
    require(paths, "Empty compiler dependency output")
    hashes = {}
    for path in sorted(paths):
        require(path.is_file(), f"Missing compiler dependency: {path}")
        if path.is_relative_to(repo):
            relative = path.relative_to(repo).as_posix()
            require(relative in SOURCE_FILES or relative == ".dart_tool/package_config.json", f"Unrecorded repository compiler input: {relative}")
        hashes[str(path)] = digest(path)
    require(str(repo / "tool/perf_probe/run_pdf_text_profile.dart") in hashes, "Compiler depfile lacks the measured entry point")
    return hashes


def validate_native_report(report, output, *, warmup, repetitions):
    require(report.get("protocolVersion") == 1 and report.get("status") == "passed", "Native report is incomplete")
    require(report.get("component") == "pdfrx-public-text-pipeline" and report.get("executionMode") == "dart-aot", "Not an AOT text component run")
    require(report.get("dartVersion", "").startswith("3.13.5 "), "Native runtime SDK changed")
    require(report.get("pdfiumSha256") == PDFIUM_SHA256, "Native library identity differs")
    require(report.get("uiLatencyCollected") is False and report.get("nativeTransferSeparated") is False and report.get("osCacheCleared") is False, "Unsupported measurement scope")
    corpus = report["corpus"]
    require(corpus["version"] == "otzaria-pdf-text-v2" and corpus["pageCount"] == 32 and corpus["sha256"] == CORPUS_SHA256, "Unexpected corpus identity")
    require(corpus["fontSha256"] == FONT_SHA256, "Unexpected embedded font")
    require(digest(output / "corpus.pdf") == CORPUS_SHA256 and (output / "corpus.pdf").stat().st_size == corpus["bytes"], "Corpus artifact differs from the measured input")
    validation = report["corpusValidation"]
    require(validation["status"] == "passed" and len(validation["pages"]) == 32, "Missing native corpus validation")
    require(validation.get("pointedTextObservation") == POINTED_TEXT_OBSERVATION, "Missing pointed-text extraction limitation")
    page_identity = {}
    for number, page in enumerate(validation["pages"], start=1):
        kind = CORPUS_KINDS[(number - 1) % len(CORPUS_KINDS)]
        rotation = 90 if kind == "rotate_90" else 270 if kind == "rotate_270" else 0
        require(page.get("pageNumber") == number and page.get("kind") == kind and page.get("rotationDegrees") == rotation, "Corpus page identity/rotation drift")
        require(re.fullmatch(r"[0-9a-f]{64}", page.get("textSha256", "")) is not None and isinstance(page.get("characters"), int), "Missing corpus text fingerprint")
        require(page.get("niqqudMarks") == (60 if kind == "niqqud" else 0), "Corpus niqqud inventory drift")
        page_identity[number] = page
        require(("raster" in page) == (number <= len(CORPUS_KINDS)), "Missing or misplaced corpus raster")
        if "raster" in page:
            raster = page["raster"]
            name = f"{number:02d}-{kind}.png"
            require(raster["darkBodyPixels"] > 100, "Missing visible Hebrew body evidence")
            require(raster["file"] == name and raster["width"] > 0 and raster["height"] > 0 and raster["bytes"] == raster["width"] * raster["height"] * 4, "Invalid corpus raster dimensions/name")
            path = output / "rasters" / name
            require(digest(path) == raster["pngSha256"], "Corpus PNG differs from its native receipt")
            png = path.read_bytes()
            require(png.startswith(b"\x89PNG\r\n\x1a\n") and len(png) >= 24 and struct.unpack(">II", png[16:24]) == (raster["width"], raster["height"]), "Invalid corpus PNG")
    profile = report["profile"]
    require(profile["status"] == "passed" and profile["protocolVersion"] == 1 and profile["timeUnit"] == "microseconds", "Text pipeline did not finish")
    require(profile["rawLoadScope"] == "native-normalization-scheduling-transfer" and profile["cacheState"] == "structured-cache-reset-per-iteration", "Text scope drift")
    configuration = profile["configuration"]
    require(configuration["warmup"] == warmup and configuration["repetitions"] == repetitions and configuration["pageNumbers"] == list(range(1, 33)), "Wrong measured workload")
    require(configuration["normalizeHebrewText"] is True and configuration["decodeLegacyHebrewText"] is True, "App Hebrew normalization policy changed")
    rows = profile["observations"]
    require(len(rows) == 32 * 3 * (warmup + repetitions), "Missing text observations")
    expected = {(i, phase, page) for i in range(warmup + repetitions) for phase in ("pipeline", "cacheFirst", "cacheRepeat") for page in range(1, 33)}
    seen = set()
    for row in rows:
        key = (row["iteration"], row["phase"], row["pageNumber"])
        require(key in expected and key not in seen and row["parity"] is True, "Missing, duplicate or failed parity observation")
        seen.add(key)
        page = page_identity[row["pageNumber"]]
        require(row.get("textSha256") == page["textSha256"] and row.get("textCharacters") == page["characters"], "Measured text differs from corpus validation")
        require(row["rawLoadCalls"] == 1 and row["formatRawCalls"] == (1 if row["phase"] == "pipeline" else 0), "Repeated extraction evidence is absent")
        require(row["warmup"] == (row["iteration"] < warmup), "Warmup entered measured samples")
    streamed = [json.loads(line) for line in (output / "observations.jsonl").read_text(encoding="utf-8").splitlines()]
    require(streamed == rows, "Raw observation stream differs from the final report")
    require(not (output / "failure.json").exists(), "Native run has a failure record")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dart", type=Path, required=True)
    parser.add_argument("--packages", type=Path)
    parser.add_argument("--pdfium", type=Path, required=True)
    parser.add_argument("--flutter-json", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--repetitions", type=int, default=5)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    require(not output.exists(), "Host output directory must be new")
    output.mkdir(parents=True)
    try:
        require(platform.system() == "Linux" and platform.machine() in ("x86_64", "AMD64"), "This receipt pins Linux x64 PDFium only")
        require(args.warmup >= 0 and args.repetitions >= 1, "Invalid repetitions/warmup")
        dart = args.dart.resolve(strict=True)
        pdfium = args.pdfium.resolve(strict=True)
        packages = (args.packages or repo / ".dart_tool/package_config.json").resolve(strict=True)
        require(digest(pdfium) == PDFIUM_SHA256, "PDFium binary differs from the pinned producer")
        before = source_receipt(repo)
        sdk = sdk_receipt(run([dart, "--version"], repo), args.flutter_json)
        toolchain = {"dartSha256": digest(dart), **package_resolution_receipt(repo, packages), "pdfiumSha256": digest(pdfium)}
        write_json(output / "source-before.json", before)
        write_json(output / "sdk.json", sdk)
        executable = output / "pdf-text-profile"
        depfile = output / "compile.d"
        command = [dart, "compile", "exe", f"--packages={packages}", "-DPDF_TEXT_PROFILE_MODE=dart-aot", f"--depfile={depfile}", "tool/perf_probe/run_pdf_text_profile.dart", "-o", executable]
        write_json(output / "compile-command.json", [str(value) for value in command])
        run(command, repo, log=output / "compile.log", timeout=600)
        require(source_receipt(repo) == before, "Repository inputs changed during compilation")
        dependencies = compiler_dependencies(depfile, repo)
        write_json(output / "compiler-inputs-after-build.json", dependencies)
        executable_hash = digest(executable)
        native = output / "native"
        run([executable, "--output", native, "--font", repo / "fonts/Tinos-Regular.ttf", "--pdfium", pdfium, "--pdfium-sha256", PDFIUM_SHA256, "--warmup", args.warmup, "--repetitions", args.repetitions], repo, log=output / "native.log", timeout=600)
        report = json.loads((native / "report.json").read_text(encoding="utf-8"))
        validate_native_report(report, native, warmup=args.warmup, repetitions=args.repetitions)
        after = source_receipt(repo)
        write_json(output / "source-after.json", after)
        require(after == before, "Repository inputs changed during the native run")
        require(compiler_dependencies(depfile, repo) == dependencies, "Compiler inputs changed during the native run")
        require(toolchain == {"dartSha256": digest(dart), **package_resolution_receipt(repo, packages), "pdfiumSha256": digest(pdfium)} and digest(executable) == executable_hash, "Compiled code, SDK or PDFium changed")
        write_json(output / "validated.json", {
            "protocolVersion": 1, "status": "passed", "executionMode": "dart-aot",
            "source": before, "sdk": sdk, "toolchain": toolchain,
            "executableSha256": executable_hash,
            "host": {"system": platform.platform(), "machine": platform.machine(), "processors": os.cpu_count()},
            "reportSha256": digest(native / "report.json"),
            "corpusSha256": CORPUS_SHA256, "summary": report["profile"]["summary"],
        })
        print(json.dumps({"status": "passed", "output": str(output), "commit": before["commit"]}))
        return 0
    except Exception as error:
        write_json(output / "failure.json", {"status": "failed", "error": str(error), "stack": traceback.format_exc()})
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
