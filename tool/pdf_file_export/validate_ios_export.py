"""Fail closed on missing/skipped XCTest cases or incomplete real Files receipts."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


REVIEWED_SOURCES = (
    "ios/Runner/AppDelegate.swift",
    "ios/Runner/PdfExportStaging.swift",
    "ios/Runner/PdfFileExportCoordinator.swift",
    "ios/Runner/PdfFileExportPlugin.swift",
    "ios/PdfFileExportTests/PdfFileExportTests.swift",
    "ios/PdfFileExportUITests/PdfFileExportUITests.swift",
    "integration_test/pdf_file_export_ios_app.dart",
    "lib/utils/file/mobile_pdf_export_core.dart",
    "lib/utils/file/mobile_pdf_export_models.dart",
    "lib/utils/file/mobile_pdf_export_service.dart",
    "pubspec.yaml",
    "pubspec.lock",
)
TEST_SOURCES = {
    "PdfFileExportTests": "ios/PdfFileExportTests/PdfFileExportTests.swift",
    "PdfFileExportUITests": "ios/PdfFileExportUITests/PdfFileExportUITests.swift",
}
SHA256 = re.compile(r"[0-9a-f]{64}")
CASE = re.compile(
    r"Test Case '-\[(?:[^ ]+\.)?(PdfFileExportTests|PdfFileExportUITests) (test\w+)\]' (passed|failed|skipped)\b"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read(root: Path, name: str) -> dict:
    return json.loads((root / name).read_text())


def sha256(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def validate(root: Path, source: Path, commit: str) -> dict:
    provenance = read(root, "source.json")
    require(provenance.get("commit") == commit and bool(re.fullmatch(r"[0-9a-f]{40}", commit)), "source commit mismatch")
    require(bool(re.fullmatch(r"[0-9a-f]{40}", provenance.get("tree", ""))), "missing source tree")
    before, after = provenance.get("filesBefore", {}), provenance.get("filesAfter", {})
    require(set(before) == set(REVIEWED_SOURCES) and before == after, "reviewed source changed or was not recorded")
    require(all(before[name] == sha256(source / name) for name in REVIEWED_SOURCES), "source bytes do not match the checkout")
    flutter = read(root, "flutter.json")
    require(flutter.get("frameworkVersion") == "3.47.7", "Flutter version changed")
    require(flutter.get("frameworkRevision") == "abaf9c523780a608bd46686fd5e53740a07077f8", "Flutter source revision changed")
    for stage in ("build", "tests"):
        command = read(root, stage + ".command.json")
        require(command.get("exitCode") == 0 and command.get("timedOut") is False, f"{stage} did not finish successfully")
        require(command.get("arguments", [])[:2] == ["xcodebuild", "build-for-testing" if stage == "build" else "test-without-building"], f"{stage} did not use Xcode")
    simulator = read(root, "simulator.json")
    cleanup = read(root, "cleanup.json")
    require(bool(re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", simulator.get("udid", ""))), "missing Simulator identity")
    require(simulator.get("runtime", {}).get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-"), "not an iOS Simulator")
    require(cleanup.get("ownedSimulatorDeleted") is True and cleanup.get("udid") == simulator["udid"], "owned Simulator cleanup is unverified")

    expected = {
        (suite, name)
        for suite, path in TEST_SOURCES.items()
        for name in re.findall(r"\bfunc (test\w+)\s*\(", (source / path).read_text())
    }
    require(all(any(suite == name for suite, _ in expected) for name in TEST_SOURCES), "a native test suite is empty")
    observed = {}
    for suite, name, result in CASE.findall((root / "tests.log").read_text()):
        key = (suite, name)
        require(key not in observed, f"duplicate/retried XCTest result: {key}")
        observed[key] = result
    require(set(observed) == expected, f"XCTest cases missing or unexpected: {expected.symmetric_difference(observed)}")
    require(all(value == "passed" for value in observed.values()), "a native test failed or was skipped")

    operation_ids = set()
    receipts = {}
    for case_name, status in (("files-save", "saved"), ("files-cancel", "cancelled")):
        receipt = read(root / "probe", case_name + ".json")
        require(receipt.get("schemaVersion") == 1 and receipt.get("case") == case_name, "wrong Files receipt")
        require(receipt.get("backend") == "MobilePdfExportService.instance", "Files did not use the real service")
        require(receipt.get("picker") == "UIDocumentPickerViewController.forExporting.asCopy", "wrong picker mode")
        require(all(receipt.get(key) is True for key in ("passed", "destinationVerified", "stagingAbsent")), "Files output/staging is unverified")
        require(type(receipt.get("fixtureBytes")) is int and receipt["fixtureBytes"] > 100, "fixture PDF is missing")
        require(bool(SHA256.fullmatch(receipt.get("expectedSha256", ""))), "fixture hash is missing")
        outcome = receipt.get("outcome", {})
        require(outcome.get("version") == 1 and outcome.get("status") == status, "wrong terminal Files outcome")
        identifier = outcome.get("operationId", "")
        require(bool(re.fullmatch(r"[0-9a-f]{32}", identifier)) and identifier not in operation_ids, "operation identity was reused/missing")
        operation_ids.add(identifier)
        require(outcome.get("cleanupStatus") == "notNeeded" and outcome.get("cleanupError") is None and outcome.get("residualDocument") is None, "Files cleanup evidence is inconsistent")
        if status == "saved":
            require(receipt.get("actualSha256") == receipt["expectedSha256"], "saved bytes differ from source")
            url = urlsplit(outcome.get("documentUri", ""))
            require(url.scheme == "file" and bool(url.path), "saved URL was not verified")
            require(Path(unquote(url.path)).name == outcome.get("displayName"), "saved name was not verified from the destination")
        else:
            require(receipt.get("actualSha256") is None and outcome.get("documentUri") is None and outcome.get("displayName") is None, "cancel invented a saved destination")
        receipts[case_name] = receipt
    return {
        "schemaVersion": 1, "status": "passed", "source": provenance,
        "flutter": flutter, "simulator": simulator,
        "nativeContractTests": sum(suite == "PdfFileExportTests" for suite, _ in expected),
        "realFilesUITests": sum(suite == "PdfFileExportUITests" for suite, _ in expected),
        "testNames": {suite: sorted(name for observed_suite, name in expected if observed_suite == suite) for suite in TEST_SOURCES},
        "filesReceipts": receipts,
        "rawHashes": {name: sha256(root / name) for name in ("build.log", "tests.log", "source.json", "flutter.json", "simulator.json")},
        "scope": "Simulator UIKit lifecycle and local Files provider; not physical-device or third-party-provider QA",
    }
