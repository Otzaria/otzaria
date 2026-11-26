#!/usr/bin/env python3
"""Require real macOS profile PDF results and rehash the loaded app images."""

import argparse
import json
from pathlib import Path
import plistlib
import re
import sys

if __package__:
    from .installed_pdf_evidence import PDF_STEPS, PAGE_SIZES, absolute, digest, require, valid_hash, validate_pdf_runtime
else:
    from installed_pdf_evidence import PDF_STEPS, PAGE_SIZES, absolute, digest, require, valid_hash, validate_pdf_runtime

PHASES = (
    "startup", "firstOpen", "visibleIdle", "stateAndScroll", "multipleOpen",
    "hiddenIdle", "memoryPressure", "restore", "protectedControls", "countPolicy",
    "agePolicy", "storeRestore", "backgroundOpen", "backgroundIdle",
    "backgroundClose", "close", "closedIdle", "minimize", "hide",
)
SYMBOLS = {
    "pdfium": ("FPDF_LoadDocument", "FPDF_RenderPageBitmap"),
    "printing": ("CGPDFDocumentCreateWithProvider", "CGContextDrawPDFPage"),
}
SOURCE = "dyld image list + dladdr of process symbols"
PRINTING = "CoreGraphics (CGPDFDocument/CGContext)"


def profile_bundle(products):
    products = Path(products).resolve(strict=True)
    bundles = list(products.glob("*.app"))
    require(len(bundles) == 1, "Expected exactly one built profile app bundle")
    bundle = bundles[0].resolve(strict=True)
    require(bundle.parent == products and bundle.is_dir(), "App bundle points outside the profile products")
    return bundle


def verify_images(record, bundle, pid):
    require(isinstance(record, dict) and record.get("source") == SOURCE
            and type(record.get("pid")) is int and record["pid"] == pid,
            "Missing dyld evidence from the scenario process")
    require(record.get("bundle") == str(bundle), "Loaded images belong to another app bundle")
    with (bundle / "Contents/Info.plist").open("rb") as source:
        name = plistlib.load(source).get("CFBundleExecutable")
    require(isinstance(name, str) and name not in ("", ".", "..") and "/" not in name,
            "Missing bundle executable identity")
    executable = (bundle / "Contents/MacOS" / name).resolve(strict=True)
    require(executable.parent == bundle / "Contents/MacOS"
            and record.get("executable") == str(executable), "Wrong loaded executable")
    require("configuredPdfrxModule" in record and record["configuredPdfrxModule"] is None
            and record.get("printingBackend") == PRINTING,
            "PDFium must use the process loader and printing must use CoreGraphics")
    images, symbols = record.get("images"), record.get("symbols")
    require(isinstance(images, list) and images and all(absolute(x) for x in images)
            and isinstance(symbols, dict), "Missing dyld image list or symbol owners")
    pdfium = set()
    for role, names in SYMBOLS.items():
        for name in names:
            owner = symbols.get(name)
            require(isinstance(owner, dict) and absolute(owner.get("image"))
                    and owner["image"] in images and absolute(owner.get("canonicalImage")),
                    f"Missing loaded owner for {name}")
            for key in ("address", "imageBase"):
                require(isinstance(owner.get(key), str)
                        and re.fullmatch(r"0x[0-9a-f]*[1-9a-f][0-9a-f]*", owner[key]) is not None,
                        f"Missing native address for {name}")
            image = Path(owner["canonicalImage"])
            if role == "pdfium":
                require(Path(owner["image"]).resolve(strict=True) == image
                        and image.resolve(strict=True) == image
                        and (image == executable or image.is_relative_to(bundle / "Contents/Frameworks")),
                        f"{name} came from outside the actual app bundle")
                pdfium.add(image)
            else:
                require(owner["image"] == owner["canonicalImage"]
                        and re.fullmatch(r"/System/Library/Frameworks/CoreGraphics\.framework/"
                                         r"(?:Versions/[^/]+/)?CoreGraphics", owner["image"]) is not None,
                        f"{name} did not come from the loaded Apple CoreGraphics framework")
    require(len(pdfium) == 1, "PDFium entry points came from different loaded images")
    expected, observed = {executable, *pdfium}, set()
    files = record.get("bundledFiles")
    require(isinstance(files, list), "Missing binary hashes")
    for entry in files:
        require(isinstance(entry, dict) and absolute(entry.get("path")), "Invalid hashed file")
        path = Path(entry["path"])
        require(path in expected and path not in observed, "Foreign or duplicate hashed image")
        observed.add(path)
        require(type(entry.get("bytes")) is int and entry["bytes"] > 0
                and entry["bytes"] == path.stat().st_size and valid_hash(entry.get("sha256"))
                and entry["sha256"] == digest(path), "Loaded binary differs from the built app")
    require(observed == expected, "Executable or PDFium hash is missing")
    return files


def validate(wrapper, bundle, output, commit):
    report = wrapper.get("installedPluginProbe")
    require(isinstance(report, dict), "Missing installed app report")
    for key, expected in {"schemaVersion": 1, "status": "passed", "platform": "macos",
                          "buildMode": "profile", "flutterVersion": "3.47.7", "commit": commit,
                          "errors": [], "contractErrors": [], "testFailures": []}.items():
        require(type(report.get(key)) is type(expected) and report[key] == expected,
                f"Incomplete macOS profile result: {key}")
    require(report.get("frameworkPassed") is True and report.get("policyRestored") is True
            and report.get("physicalDeviceAcceptance") is False, "Missing framework completion or scope")
    pid, run_id = report.get("pid"), report.get("runId")
    require(type(pid) is int and pid > 0 and isinstance(run_id, str)
            and re.fullmatch(rf"{pid}-[0-9]+", run_id) is not None, "Missing process run identity")
    require(isinstance(report.get("osVersion"), str) and report["osVersion"].strip(), "Missing OS provenance")
    matrix = report.get("platformMatrix", {})
    require(matrix.get("macos", {}).get("status") == "passed"
            and all(matrix.get(name, {}).get("status") == "notRun"
                    for name in ("windows", "linux", "android", "ios")), "Unexecuted platform marked passed")
    phases = report.get("phases")
    require(isinstance(phases, list) and all(isinstance(x, dict) for x in phases), "Missing app phases")
    by_name = {x.get("name"): x for x in phases}
    require(len(by_name) == len(phases)
            and all(by_name.get(name, {}).get("status") == "passed" for name in PHASES),
            "Missing, duplicate or failed installed-app phase")
    pdf = report.get("pdfRuntime")
    pngs = validate_pdf_runtime(pdf, "macos", output)
    steps = pdf["steps"]
    binaries = verify_images(steps["loadedModules"], bundle, pid)
    image_artifact = json.loads((output / "bundle-runtime-macos-images.json").read_text(encoding="utf-8"))
    require(image_artifact == {k: v for k, v in steps["loadedModules"].items()
                               if k not in ("status", "durationMs")}, "Loaded-image artifact differs from report")
    return {"status": "passed", "platform": "macos", "buildMode": "profile", "commit": commit,
            "runId": run_id, "pdfSteps": [*PDF_STEPS, "desktopLifecycle", "repeatedLifecycle"],
            "bundledFiles": binaries, "pngArtifacts": pngs,
            "physicalPrinter": "notRun", "physicalDeviceAcceptance": False}


def validate_directory(root, products, output, commit):
    matches = list(Path(root).glob("run-*/report.json"))
    require(len(matches) == 1, "Expected one fresh driver report")
    return validate(json.loads(matches[0].read_text(encoding="utf-8")), profile_bundle(products),
                    Path(output).resolve(strict=True), commit)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--products", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    try:
        result = validate_directory(args.root, args.products, args.output, args.commit)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"MACOS PDF RUNTIME INVALID: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(json.dumps(result, ensure_ascii=False, indent=2))
