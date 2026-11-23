#!/usr/bin/env python3
"""Run the dedicated Android PDF export APK and validate its native evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time


APP = "org.otzaria.otzaria.pdfexportprobe"
TEST_APP = APP + ".test"
RUNNER = "org.otzaria.otzaria.PdfExportInstrumentation"
FRAMEWORK_REVISION = "abaf9c523780a608bd46686fd5e53740a07077f8"
ENGINE_REVISION = "deb287481e3ce9468f3434937ced4240a70539ca"
SOURCE_PATHS = (
    "android/app/src/main", "android/app/src/pdfExportProbe", "android/app/src/pdfExportAndroidTest",
    "android/app/src/test", "android/app/build.gradle", "lib/utils/file/mobile_pdf_export*",
    "integration_test/pdf_android_file_export_probe.dart", "tool/pdf_export_android",
    ".github/workflows/pdf_mobile_export_android.yml", "pubspec.yaml", "pubspec.lock",
)
EXPECTED_CASES = {
    "documents_ui_new_copy",
    "pipe_bytes_and_pdf_parity",
    "create_failure",
    "invalid_created_document",
    "output_open_failure",
    "pipe_write_failure",
    "cancel_blocked_create",
    "cancel_blocked_write_deleted",
    "cancel_blocked_write_unsupported_cleanup",
    "cancel_blocked_write_failed_cleanup",
    "provider_name_unavailable",
    "stale_request_and_duplicate_result",
    "cancel_during_native_prepare",
    "detach_before_native_acquire",
    "detach_while_picker_open",
    "saved_before_late_cancel_delivery",
    "staging_leaf_replacement",
    "staging_child_replacement",
    "staging_root_replacement",
    "invalid_source_no_provider_document",
    "activity_detach_during_write",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_report(report):
    require(report.get("schema") == 1 and report.get("passed") is True, "Native run did not pass")
    require(report.get("applicationId") == APP, "Unexpected application ID")
    require(report.get("sdk") == 34, "This picker contract requires the declared API 34 emulator")
    rows = report.get("cases")
    require(isinstance(rows, list), "Missing native cases")
    names = [row.get("name") for row in rows]
    require(len(names) == len(set(names)) and set(names) == EXPECTED_CASES, "Missing, duplicate or unexpected native case")
    require(all(row.get("passed") is True and isinstance(row.get("evidence"), dict) for row in rows), "Native case failed or omitted evidence")
    cases = {row["name"]: row["evidence"] for row in rows}
    for name in ("documents_ui_new_copy", "pipe_bytes_and_pdf_parity"):
        evidence = cases[name]
        result, source = evidence["result"], evidence["source"]
        copies = [doc for doc in evidence["provider"]["documents"] if doc["id"] != "existing"]
        require(len(copies) == 1, "Expected one newly owned document")
        copied = copies[0]
        require(result["status"] == "saved" and result["displayName"] == "existing (2).pdf", "New copy/name contract failed")
        require(bool(re.fullmatch(r"[0-9a-f]{64}", source["sha256"])), "Missing source SHA-256")
        require(source["sha256"] == copied["sha256"] and source["length"] == copied["bytes"] > 16 * 1024 * 1024, "Stream parity/size mismatch")
        require(source["exists"] is False and source["directoryExists"] is False and copied["closed"] is True, "Source/target lifetime incomplete")
        require(evidence["bluePixels"] > 100, "Saved PDF was not visibly rendered")
    picker = cases["documents_ui_new_copy"]
    require(picker["realDocumentsUi"] is True and picker["pickerPackage"].endswith(".documentsui"), "Actual DocumentsUI was not observed")
    require("test-grant" not in picker["provider"]["events"], "Real picker case used a fixture URI grant")
    invalid = cases["invalid_created_document"]
    result = invalid["result"]
    require(result["status"] == "failed" and result["errorCode"] == "invalid_document" and
            result["cleanupStatus"] == "notNeeded" and result["residualDocument"] is None, "Unowned document was accepted")
    events = invalid["provider"]["events"]
    require("create-enter" in events and not any(event.startswith(("open-request:", "delete-request:")) for event in events),
            "Unowned document was opened or deleted")
    for name, cleanup in (
        ("cancel_blocked_write_deleted", "deleted"),
        ("cancel_blocked_write_unsupported_cleanup", "unsupported"),
        ("cancel_blocked_write_failed_cleanup", "failed"),
    ):
        evidence = cases[name]
        result = evidence["result"]
        require(result["status"] == "cancelled" and result["cleanupStatus"] == cleanup, "Cancellation/cleanup mismatch")
        require(0 < evidence["partialBytes"] < evidence["sourceBytes"], "Cancellation did not interrupt a real partial write")
        require(evidence["ack"]["accepted"] is True and evidence["sourceHeldAfterAck"] is True and evidence["terminalAtAck"] is False, "Cancel ACK released the source early")
        if cleanup != "deleted":
            require(isinstance(result["residualDocument"], str) and result["residualDisplayName"] == "עותק.pdf", "Owned residual was not reported")
    late = cases["saved_before_late_cancel_delivery"]
    require(late["ack"]["accepted"] is False and late["result"]["status"] == "saved", "Late cancel overrode committed save")
    for name in ("detach_before_native_acquire", "detach_while_picker_open"):
        require(cases[name]["dartFinallyUsed"] is False and cases[name]["result"]["status"] == "cancelled", "Native detach cleanup was not independent of Dart")
    detached = cases["activity_detach_during_write"]
    require(detached["dartEngineDestroyed"] is True and detached["stagingRemoved"] is True, "Actual Activity detach cleanup missing")
    require(detached["engineDestroyCallback"] is True and detached["engineStillRegistered"] is False and detached["engineId"] > 0,
            "Flutter engine destruction was not independently observed")
    for kind in ("leaf", "child", "root"):
        evidence = cases[f"staging_{kind}_replacement"]
        require(evidence["replacementPreserved"] is True and "staging_cleanup_failed:" in evidence["result"]["cleanupError"], "Replaced staging was not preserved")
    return len(rows)


def run(command, *, timeout=60, check=True, binary=False, cwd=None):
    completed = subprocess.run(command, cwd=cwd, timeout=timeout, capture_output=True, text=not binary)
    if check and completed.returncode:
        detail = completed.stderr if not binary else completed.stderr.decode("utf-8", errors="replace")
        raise RuntimeError(f"Command failed ({completed.returncode}): {command}\n{detail[-6000:]}")
    return completed


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def provider_blocks(xmltree):
    blocks = []
    lines = xmltree.splitlines()
    for index, line in enumerate(lines):
        if line.lstrip().startswith("E: provider "):
            indent = len(line) - len(line.lstrip())
            end = index + 1
            while end < len(lines) and (not lines[end].strip() or len(lines[end]) - len(lines[end].lstrip()) > indent):
                end += 1
            blocks.append("\n".join(lines[index:end]))
    return blocks


def inspect_apks(app, tests, aapt2, output):
    for path, expected, label in ((app, APP, "app"), (tests, TEST_APP, "tests")):
        badging = run([str(aapt2), "dump", "badging", str(path)]).stdout
        (output / f"{label}-badging.txt").write_text(badging)
        require(re.search(r"^package: name='([^']+)'", badging, re.M).group(1) == expected, "Refusing to install a non-probe APK")
        require("uses-permission: name='android.permission.MANAGE_DOCUMENTS'" not in badging, "Probe must not acquire MANAGE_DOCUMENTS")
        require("uses-permission: name='android.permission.MANAGE_EXTERNAL_STORAGE'" not in badging, "Probe must not use broad storage access")
        tree = run([str(aapt2), "dump", "xmltree", "--file", "AndroidManifest.xml", str(path)]).stdout
        (output / f"{label}-manifest.txt").write_text(tree)
        if label == "tests":
            blocks = provider_blocks(tree)
            document = [block for block in blocks if '"org.otzaria.otzaria.PdfExportDocumentsProvider"' in block]
            require(len(document) == 1 and '"android.permission.MANAGE_DOCUMENTS"' in document[0], "DocumentsProvider permission was weakened")
            control = [block for block in blocks if '"org.otzaria.otzaria.PdfExportControlProvider"' in block]
            require(len(control) == 1 and f'"{APP}.CONTROL"' in control[0], "Fixture control is not signature protected")


def source_receipt(repo, flutter_json):
    sdk = json.loads(flutter_json.read_text())
    require(sdk["frameworkVersion"] == "3.47.7" and sdk["dartSdkVersion"].startswith("3.13.5"), "Unexpected Flutter/Dart SDK")
    require(sdk["frameworkRevision"] == FRAMEWORK_REVISION and sdk["engineRevision"] == ENGINE_REVISION, "Unexpected Flutter framework/engine revision")
    dirty = run(["git", "status", "--porcelain", "--untracked-files=all", "--", *SOURCE_PATHS], cwd=repo).stdout
    require(not dirty, f"Measured source is dirty: {dirty}")
    files = run(["git", "ls-files", "--", *SOURCE_PATHS], cwd=repo).stdout.splitlines()
    require(any(name.endswith("mobile_pdf_export_service.dart") for name in files), "Real Dart service is absent")
    entries = run(["git", "ls-tree", "-r", "--full-tree", "HEAD", "--", *files], cwd=repo).stdout.splitlines()
    blobs = {line.split("\t", 1)[1]: line.split("\t", 1)[0].split()[2] for line in entries}
    require(set(files) == set(blobs), "Measured file set differs from HEAD")
    hashes = {}
    for name in files:
        data = (repo / name).read_bytes()
        blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        require(blob == blobs[name], f"Measured file does not match its HEAD blob: {name}")
        hashes[name] = hashlib.sha256(data).hexdigest()
    return {
        "schema": 1,
        "commit": run(["git", "rev-parse", "HEAD"], cwd=repo).stdout.strip(),
        "tree": run(["git", "rev-parse", "HEAD^{tree}"], cwd=repo).stdout.strip(),
        "parents": run(["git", "show", "-s", "--format=%P", "HEAD"], cwd=repo).stdout.split(),
        "sdk": sdk,
        "files": hashes,
        "blobs": blobs,
    }


def finalize_run(actions, primary=None):
    failures = []
    for name, action in actions:
        try:
            action()
        except Exception as error:
            failures.append(f"{name}: {error}")
    if failures:
        message = "Finalization failures:\n" + "\n".join(failures)
        print(message, file=sys.stderr)
        if primary is None:
            raise RuntimeError(message)
    return failures


def instrumentation_report(completed, raw):
    transcript = completed.stdout + completed.stderr
    require(completed.returncode == 0 and "INSTRUMENTATION_CODE: -1" in completed.stdout,
            "Instrumentation did not complete normally:\n" + transcript + "\nNative output:\n" + raw)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError("Instrumentation completed without a JSON native report:\n" + raw) from error


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="emulator-5554")
    parser.add_argument("--app-apk", type=Path)
    parser.add_argument("--test-apk", type=Path)
    parser.add_argument("--aapt2", type=Path)
    parser.add_argument("--record-source", action="store_true")
    parser.add_argument("--flutter-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt = source_receipt(repo, args.flutter_json)
    if args.record_source:
        (output / "source-before-build.json").write_text(json.dumps(receipt, indent=2))
        return
    require(args.app_apk is not None and args.test_apk is not None and args.aapt2 is not None, "APK paths and aapt2 are required")
    before = json.loads((output / "source-before-build.json").read_text())
    require(receipt == before, "Source or SDK changed during the APK build")
    (output / "source-after-build.json").write_text(json.dumps(receipt, indent=2))
    inspect_apks(args.app_apk, args.test_apk, args.aapt2, output)
    apks = {"app": sha256(args.app_apk), "tests": sha256(args.test_apk)}
    (output / "source.json").write_text(json.dumps({**receipt, "apks": apks}, indent=2))
    adb = ["adb", "-s", args.device]
    started = time.monotonic()
    primary = None

    def verify_source_after():
        sdk_after = output / "flutter-after.json"
        sdk_after.write_text(run(["flutter", "--version", "--machine"]).stdout)
        after = source_receipt(repo, sdk_after)
        (output / "source-after-run.json").write_text(json.dumps(after, indent=2))
        require(after == before, "Source or SDK changed during native execution")
        require({"app": sha256(args.app_apk), "tests": sha256(args.test_apk)} == apks, "APK bytes changed during native execution")

    try:
        require(run(adb + ["get-state"]).stdout.strip() == "device", "Emulator is not available")
        for package in (APP, TEST_APP):
            run(adb + ["uninstall", package], check=False)
        run(adb + ["install", "-t", str(args.app_apk)], timeout=120)
        run(adb + ["install", "-t", str(args.test_apk)], timeout=120)
        denied = run(adb + ["shell", "content", "call", "--uri", f"content://{TEST_APP}.control", "--method", "snapshot"], check=False)
        denial = denied.stdout + denied.stderr
        (output / "control-permission-denied.txt").write_text(denial)
        require("SecurityException" in denial and (APP + ".CONTROL") in denial, "Fixture control did not reject the unprivileged shell caller")
        run(adb + ["logcat", "-c"])
        completed = run(adb + ["shell", "am", "instrument", "-w", "-r", f"{TEST_APP}/{RUNNER}"], timeout=600, check=False)
        (output / "instrumentation.txt").write_text(completed.stdout + completed.stderr)
        raw = run(adb + ["exec-out", "run-as", APP, "cat", "files/pdf-export-native-report.json"], check=False).stdout
        (output / "native-report.json").write_text(raw)
        count = validate_report(instrumentation_report(completed, raw))
        screenshot = run(adb + ["exec-out", "run-as", APP, "cat", "files/pdf-export-picker.png"], binary=True).stdout
        require(screenshot.startswith(b"\x89PNG\r\n\x1a\n"), "Missing actual picker screenshot")
        (output / "documents-ui.png").write_bytes(screenshot)
    except BaseException as error:
        primary = error
        raise
    finally:
        finalize_run([
            ("logcat", lambda: (output / "logcat.txt").write_text(run(adb + ["logcat", "-d", "-v", "threadtime"]).stdout)),
            ("source after run", verify_source_after),
            ("stop probe", lambda: run(adb + ["shell", "am", "force-stop", APP])),
            ("stop fixture", lambda: run(adb + ["shell", "am", "force-stop", TEST_APP])),
        ], primary)
    (output / "validated.json").write_text(json.dumps({"passed": True, "cases": count, "controlAccessDenied": True, "elapsedSeconds": time.monotonic() - started}, indent=2))
    print(f"Validated {count} native cases against {receipt['commit']} / {receipt['tree']}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
