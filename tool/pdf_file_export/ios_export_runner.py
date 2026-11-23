#!/usr/bin/env python3
"""Build the actual Runner and run native contracts plus the real Files UI.

Only the Simulator created by this process is shut down/deleted. No PDF or app
container is uploaded: only the two synthetic probe receipts and XCTest output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

from validate_ios_export import REVIEWED_SOURCES as SOURCE_FILES, validate


UUID = re.compile(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")


def output(arguments: list[str], *, timeout: int = 120) -> str:
    return subprocess.check_output(arguments, text=True, timeout=timeout).strip()


def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def digest(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def run_logged(arguments: list[str], destination: Path, *, timeout: int) -> int:
    print(f"Running {destination.stem}", flush=True)
    start = time.monotonic()
    timed_out = threading.Event()
    with destination.open("w") as log:
        with subprocess.Popen(
            arguments, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, start_new_session=True,
        ) as process:
            def stop() -> None:
                timed_out.set()
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

            watchdog = threading.Timer(timeout, stop)
            watchdog.start()
            try:
                assert process.stdout is not None
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    sys.stdout.write(line)
                    sys.stdout.flush()
                code = process.wait()
            finally:
                watchdog.cancel()
    save(destination.with_suffix(".command.json"), {
        "arguments": arguments, "exitCode": code,
        "timedOut": timed_out.is_set(), "durationSeconds": time.monotonic() - start,
    })
    if code != 0 or timed_out.is_set():
        raise RuntimeError(f"{destination.stem} failed: exit={code}, timeout={timed_out.is_set()}")
    return code


def create_simulator(root: Path) -> dict:
    runtimes = json.loads(output(["xcrun", "simctl", "list", "-j", "runtimes"]))["runtimes"]
    devices = json.loads(output(["xcrun", "simctl", "list", "-j", "devices"]))["devices"]
    choices = []
    for runtime in runtimes:
        if not runtime.get("isAvailable") or not runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        for device in devices.get(runtime["identifier"], []):
            if device.get("isAvailable") and device.get("deviceTypeIdentifier", "").startswith("com.apple.CoreSimulator.SimDeviceType.iPhone-"):
                choices.append((runtime, device))
    if not choices:
        raise RuntimeError("No installed iOS runtime with a compatible iPhone; tests were NOT_RUN")
    runtime, prototype = max(choices, key=lambda pair: tuple(int(n) for n in pair[0]["version"].split(".")))
    name = f"otzaria-pdf-export-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
    identifier = output(["xcrun", "simctl", "create", name, prototype["deviceTypeIdentifier"], runtime["identifier"]])
    if not UUID.fullmatch(identifier):
        raise RuntimeError("simctl returned an invalid owned Simulator identifier")
    receipt = {"udid": identifier, "name": name, "runtime": runtime, "deviceType": prototype["deviceTypeIdentifier"]}
    try:
        save(root / "simulator.json", receipt)
    except Exception:
        # A failed evidence write must not orphan the Simulator just created.
        try:
            cleanup_simulator(receipt)
        except Exception as error:
            print(f"Simulator cleanup after receipt failure: {error}", file=sys.stderr)
        raise
    return receipt


def check_owned_simulator(receipt: dict) -> dict | None:
    identifier = receipt["udid"]
    expected_name = f"otzaria-pdf-export-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
    if not UUID.fullmatch(identifier) or receipt.get("name") != expected_name:
        raise RuntimeError("Refusing an invalid Simulator receipt")
    devices = json.loads(output(["xcrun", "simctl", "list", "-j", "devices"]))["devices"]
    for runtime, entries in devices.items():
        for entry in entries:
            if entry["udid"] == identifier:
                if runtime != receipt["runtime"]["identifier"] or entry["name"] != receipt["name"] or entry.get("deviceTypeIdentifier") != receipt["deviceType"]:
                    raise RuntimeError("Owned Simulator identity changed; refusing cleanup")
                return entry
    return None


def cleanup_simulator(receipt: dict) -> None:
    entry = check_owned_simulator(receipt)
    if entry is None:
        return
    if entry["state"] == "Booted":
        output(["xcrun", "simctl", "shutdown", receipt["udid"]])
    output(["xcrun", "simctl", "delete", receipt["udid"]])
    if check_owned_simulator(receipt) is not None:
        raise RuntimeError("Owned Simulator was not deleted")


def collect_probe_receipts(root: Path, receipt: dict) -> None:
    container = Path(output([
        "xcrun", "simctl", "get_app_container", receipt["udid"], "com.mendelg.otzaria", "data",
    ])).resolve(strict=True)
    source = container / "Documents" / "PdfExportEvidence"
    destination = root / "probe"
    destination.mkdir(exist_ok=True)
    for name in ("files-save.json", "files-cancel.json"):
        path = source / name
        if path.is_file() and not path.is_symlink():
            shutil.copyfile(path, destination / name)


def run(root: Path, source: Path, commit: str) -> None:
    root.mkdir(parents=True, exist_ok=False)
    os.chdir(source)
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or output(["git", "rev-parse", "HEAD"]) != commit:
        raise RuntimeError("Checkout does not match the requested source commit")
    status = output(["git", "status", "--porcelain"])
    if status:
        raise RuntimeError("The source checkout was dirty before the build")
    before = {name: digest(source / name) for name in SOURCE_FILES}
    save(root / "source.json", {"commit": commit, "tree": output(["git", "rev-parse", "HEAD^{tree}"]), "filesBefore": before})
    save(root / "flutter.json", json.loads(output(["flutter", "--version", "--machine"])))
    (root / "host.txt").write_text(output(["sw_vers"]) + "\n" + output(["uname", "-a"]) + "\n")
    (root / "xcode.txt").write_text(output(["xcodebuild", "-version"]) + "\n")
    receipt = create_simulator(root)
    primary: BaseException | None = None
    try:
        output(["xcrun", "simctl", "boot", receipt["udid"]])
        output(["xcrun", "simctl", "bootstatus", receipt["udid"], "-b"], timeout=300)
        output(["xcrun", "simctl", "spawn", receipt["udid"], "defaults", "write", "NSGlobalDomain", "AppleLanguages", "-array", "en"])
        run_logged(["flutter", "pub", "get", "--enforce-lockfile"], root / "dependencies.log", timeout=900)
        run_logged([
            "flutter", "build", "ios", "--simulator", "--debug", "--config-only", "--no-codesign", "--no-pub",
            "--target=integration_test/pdf_file_export_ios_app.dart", "--dart-define=PDF_FILE_EXPORT_IOS_PROBE=true",
        ], root / "configure.log", timeout=900)
        common = [
            "-workspace", "ios/Runner.xcworkspace", "-scheme", "PdfFileExport", "-configuration", "Debug",
            "-sdk", "iphonesimulator", "-destination", f"id={receipt['udid']}",
            "-derivedDataPath", str(root / "derived-data"),
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "COMPILER_INDEX_STORE_ENABLE=NO",
        ]
        run_logged(["xcodebuild", "build-for-testing", *common], root / "build.log", timeout=2700)
        run_logged([
            "xcodebuild", "test-without-building", *common,
            "-parallel-testing-enabled", "NO",
            "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "180",
            "-resultBundlePath", str(root / "native.xcresult"),
            "-only-testing:PdfFileExportTests", "-only-testing:PdfFileExportUITests",
        ], root / "tests.log", timeout=1800)
    except BaseException as error:
        primary = error
    finally:
        try:
            after = {name: digest(source / name) for name in SOURCE_FILES}
            source_receipt = json.loads((root / "source.json").read_text())
            source_receipt["filesAfter"] = after
            save(root / "source.json", source_receipt)
            (root / "source-status-after.txt").write_text(output(["git", "status", "--porcelain"]) + "\n")
            (root / "generated-project.diff").write_text(output(["git", "diff", "--", "ios"]) + "\n")
            if before != after:
                raise RuntimeError("Reviewed application/test source or pinned dependencies changed during build")
        except Exception as error:
            print(f"Source evidence collection failed: {error}", file=sys.stderr)
            if primary is None:
                primary = error
        try:
            collect_probe_receipts(root, receipt)
        except Exception as error:
            print(f"Files evidence collection failed: {error}", file=sys.stderr)
            if primary is None:
                primary = error
        try:
            cleanup_simulator(receipt)
            save(root / "cleanup.json", {"ownedSimulatorDeleted": True, "udid": receipt["udid"]})
        except Exception as error:
            print(f"Simulator cleanup/evidence failed: {error}", file=sys.stderr)
            if primary is None:
                primary = error
    if primary is not None:
        raise primary
    summary = validate(root, source, commit)
    save(root / "summary.json", summary)
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=Path.cwd())
    parser.add_argument("--commit")
    parser.add_argument("--cleanup-only", action="store_true")
    arguments = parser.parse_args()
    if arguments.cleanup_only:
        receipt_path = arguments.root.resolve() / "simulator.json"
        if receipt_path.is_file():
            cleanup_simulator(json.loads(receipt_path.read_text()))
    else:
        if arguments.commit is None:
            parser.error("--commit is required for a test run")
        run(arguments.root.resolve(), arguments.source.resolve(), arguments.commit)
