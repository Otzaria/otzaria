"""Shared fail-closed native PDF result and artifact checks for Apple runners."""

import hashlib
import math
from pathlib import Path, PurePosixPath
import re
import struct

try:
    from .installed_pdf_desktop import validate_desktop_steps
except ImportError:
    from installed_pdf_desktop import validate_desktop_steps

PDF_STEPS = ("view", "concurrentWork", "cancelAndRecover", "reopen", "loadedModules", "teardown")
PAGE_SIZES = ((240, 320), (320, 240), (200, 400), (400, 200))


def require(condition, detail):
    if not condition:
        raise ValueError(detail)


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def valid_hash(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def absolute(value):
    return (isinstance(value, str) and PurePosixPath(value).is_absolute()
            and str(PurePosixPath(value)) == value and ".." not in PurePosixPath(value).parts)


def pixel_proof(proof, page):
    require(isinstance(proof, dict) and type(proof.get("page")) is int and proof["page"] == page
            and (proof.get("width"), proof.get("height")) == PAGE_SIZES[page - 1]
            and proof.get("contentPixelsVerified") is True and valid_hash(proof.get("pixelSha256")),
            f"Missing native pixel proof for page {page}")


def verify_pdf_file(path, evidence):
    require(isinstance(evidence, dict) and type(evidence.get("bytes")) is int
            and evidence["bytes"] == path.stat().st_size and valid_hash(evidence.get("sha256"))
            and evidence["sha256"] == digest(path), "PDF artifact differs from the native result")
    with path.open("rb") as source:
        require(source.read(5) == b"%PDF-", "PDF artifact is not a PDF")


def verify_png(path, expected_size):
    with path.open("rb") as source:
        header = source.read(24)
    require(len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n"
            and header[12:16] == b"IHDR" and struct.unpack(">II", header[16:24]) == expected_size,
            "Missing PNG artifact or wrong raster dimensions")
    return {"path": str(path), "sha256": digest(path), "bytes": path.stat().st_size}


def validate_pdf_runtime(pdf, platform, output):
    require(isinstance(pdf, dict) and pdf.get("status") == "passed" and pdf.get("platform") == platform
            and pdf.get("physicalPrinter") == "notRun" and pdf.get("bundlePathsVerified") is True,
            "PDF runtime or loaded-image evidence did not pass")
    require(all(type(pdf.get(key)) is int and pdf[key] == 0
                for key in ("ownedDocumentsRemaining", "ownedTabsRemaining"))
            and pdf.get("indexingActiveAfter") is False, "PDF ownership remained after teardown")
    steps = pdf.get("steps")
    require(isinstance(steps, dict), "Missing PDF steps")
    desktop = platform in ("linux", "windows", "macos")
    required_steps = (*PDF_STEPS, "desktopLifecycle", "repeatedLifecycle") if desktop else PDF_STEPS
    for name in required_steps:
        step = steps.get(name)
        require(isinstance(step, dict) and step.get("status") == "passed"
                and type(step.get("durationMs")) in (int, float)
                and math.isfinite(step["durationMs"]) and step["durationMs"] >= 0,
                f"PDF step missing, skipped or failed: {name}")
    if desktop:
        validate_desktop_steps(steps)
    for name, page in (("view", 1), ("reopen", 2)):
        require(steps[name].get("visibleRenderState") == "ready"
                and steps[name].get("targetPage") == page
                and steps[name].get("targetCenterVisible") is True, "Reader target did not paint")
        pixel_proof(steps[name].get("raster"), page)
    work = steps["concurrentWork"]
    require(work.get("indexedPages") == [0, 1, 2, 3] and work.get("viewerTargetPage") == 4
            and work.get("targetCenterVisible") is True, "Indexing or concurrent navigation incomplete")
    pixel_proof(work.get("viewerRaster"), 4)
    rasters = work.get("printingRasters")
    require(isinstance(rasters, list) and len(rasters) == 4, "Printing did not rasterize every page")
    for page, raster in enumerate(rasters, 1):
        pixel_proof(raster, page)
    export = work.get("vectorExport", {})
    require(export.get("sourcePages") == [2, 3] and export.get("sheets") == 1
            and all(export.get(key) is True for key in ("textPreserved", "rightToLeft", "printingRasterVerified"))
            and type(export.get("printingInkPixels")) is int and export["printingInkPixels"] > 100,
            "Vector export or its printing raster is incomplete")
    cancel = steps["cancelAndRecover"]
    require(all(cancel.get(key) is True for key in (
        "preCanceledPdfrxRenderReturnedNull", "indexCancellationObserved", "originalIndexPreserved"))
        and cancel.get("printingSubscriptionCanceledAfterPages") == 1
        and cancel.get("printingRecoveryPage") == 4 and cancel.get("indexRecoveryPages") == 4,
        "Cancellation or recovery did not complete")
    pixel_proof(cancel.get("pdfrxRecovery"), 1)
    require(steps["reopen"].get("differentDocument") is True
            and steps["reopen"].get("previousNativeCloseCompleted") is True
            and steps["teardown"].get("viewerDetached") is True
            and steps["teardown"].get("viewerNativeCloseCompleted") is True
            and type(steps["teardown"].get("viewerLoadingCount")) is int
            and steps["teardown"].get("viewerLoadingCount") == 0, "Viewer native teardown incomplete")
    fixture = pdf.get("fixture", {})
    require(fixture.get("pages") == 4 and isinstance(fixture.get("path"), str)
            and Path(fixture["path"]).resolve(strict=True) == output / "bundle-runtime.pdf",
            "Fixture does not belong to the fresh device output")
    verify_pdf_file(output / "bundle-runtime.pdf", fixture)
    verify_pdf_file(output / "bundle-runtime-cancel.pdf", fixture)
    verify_pdf_file(output / "bundle-runtime-export.pdf", export)
    pngs = [verify_png(output / name, size) for name, size in (
        ("bundle-runtime-print.png", PAGE_SIZES[0]), ("bundle-runtime-export.png", (480, 320)),
    )]
    return pngs
