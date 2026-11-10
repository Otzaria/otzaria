#!/usr/bin/env python3
"""Keep vendored Pub packages byte-identical to their archives, except reviewed patches."""

import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import urllib.request

# The cargokit Gradle script is patched for compileSdk "android-37.0" and Gradle 9.
CARGOKIT_GRADLE = "cargokit/gradle/plugin.gradle"

PACKAGES = {
    "super_native_extensions": {
        "url": "https://pub.dev/api/archives/super_native_extensions-0.9.1.tar.gz",
        "sha256": "b9611dcb68f1047d6f3ef11af25e4e68a21b1a705bbcc3eb8cb4e9f5c3148569",
        "files": 247,
        "patched": {
            "rust/src/win32/reader.rs",
            "rust/src/win32/image_conversion.rs",
            CARGOKIT_GRADLE,
        },
        "added": {"rust/src/win32/bitmap_reader_tests.rs", "UPSTREAM.md"},
    },
    "irondash_engine_context": {
        "url": "https://pub.dev/api/archives/irondash_engine_context-0.5.5.tar.gz",
        "sha256": "2bb0bc13dfda9f5aaef8dde06ecc5feb1379f5bb387d59716d799554f3f305d7",
        "files": 68,
        "patched": {CARGOKIT_GRADLE},
        "added": {"UPSTREAM.md"},
    },
}


def archive_sources(data, package):
    if hashlib.sha256(data).hexdigest() != package["sha256"]:
        raise ValueError("The Pub archive does not match the pinned SHA-256")
    sources = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            if member.isdir():
                continue
            path = PurePosixPath(member.name)
            if not member.isfile() or path.is_absolute() or ".." in path.parts:
                raise ValueError(f"Unexpected archive entry: {member.name}")
            name = str(path)
            if name in sources:
                raise ValueError(f"Duplicate archive entry: {name}")
            with archive.extractfile(member) as source:
                sources[name] = ("100755" if member.mode & 0o111 else "100644", source.read())
    if len(sources) != package["files"]:
        raise ValueError("Unexpected upstream file count")
    return sources


def verify_sources(upstream, local, package):
    added = package["added"]
    missing = set(upstream) - set(local)
    extra = set(local) - set(upstream) - added
    if missing or extra or not added.issubset(local):
        raise ValueError(f"Vendor paths differ: missing={sorted(missing)}, extra={sorted(extra)}")
    for name, (mode, content) in upstream.items():
        local_mode, local_content = local[name]
        if mode != local_mode:
            raise ValueError(f"Upstream file mode changed: {name}")
        if name not in package["patched"] and content != local_content:
            raise ValueError(f"Unapproved upstream source change: {name}")
    for name in added:
        if local[name][0] != "100644":
            raise ValueError(f"Unexpected added file mode: {name}")


def tracked_sources(root, prefix):
    result = subprocess.run(
        ["git", "ls-files", "--stage", "-z", "--", prefix],
        cwd=root, check=True, stdout=subprocess.PIPE,
    )
    sources = {}
    for record in result.stdout.decode("utf-8").split("\0"):
        if not record:
            continue
        metadata, path = record.split("\t", 1)
        mode, _, stage = metadata.split()
        if stage != "0" or mode not in {"100644", "100755"}:
            raise ValueError(f"Unexpected tracked entry: {path}")
        sources[path.removeprefix(prefix)] = (mode, (root / path).read_bytes())
    return sources


def read_archive(package, path):
    if path:
        return path.read_bytes()
    with urllib.request.urlopen(package["url"], timeout=30) as response:
        data = response.read(5 * 1024 * 1024 + 1)
    if len(data) > 5 * 1024 * 1024:
        raise ValueError("Unexpected archive size")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", choices=sorted(PACKAGES), action="append")
    parser.add_argument("--archive", type=Path, help="local archive; requires a single --package")
    args = parser.parse_args()
    names = args.package or sorted(PACKAGES)
    if args.archive and len(names) != 1:
        parser.error("--archive requires exactly one --package")
    root = Path(__file__).resolve().parent.parent
    for name in names:
        package = PACKAGES[name]
        upstream = archive_sources(read_archive(package, args.archive), package)
        verify_sources(upstream, tracked_sources(root, f"packages/{name}/"), package)
        print(f"{name}: verified {len(upstream)} upstream files and modes; "
              f"only {len(package['patched'])} reviewed sources may differ.")


if __name__ == "__main__":
    main()
