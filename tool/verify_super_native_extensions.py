#!/usr/bin/env python3
"""Keep the Dart/build/platform baseline exact while patching the Windows reader and Gradle 9 build."""

import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import urllib.request


ARCHIVE_URL = "https://pub.dev/api/archives/super_native_extensions-0.9.1.tar.gz"
ARCHIVE_SHA256 = "b9611dcb68f1047d6f3ef11af25e4e68a21b1a705bbcc3eb8cb4e9f5c3148569"
PREFIX = "packages/super_native_extensions/"
PATCHED = {
    "rust/src/win32/reader.rs",
    "rust/src/win32/image_conversion.rs",
    # compileSdk "android-37.0" and Gradle 9 (no Project.exec); see UPSTREAM.md.
    "cargokit/gradle/plugin.gradle",
}
ADDED = {"rust/src/win32/bitmap_reader_tests.rs", "UPSTREAM.md"}


def archive_sources(data):
    if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
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
    if len(sources) != 247:
        raise ValueError("Unexpected upstream file count")
    return sources


def verify_sources(upstream, local):
    missing = set(upstream) - set(local)
    extra = set(local) - set(upstream) - ADDED
    if missing or extra or not ADDED.issubset(local):
        raise ValueError(f"Vendor paths differ: missing={sorted(missing)}, extra={sorted(extra)}")
    for name, (mode, content) in upstream.items():
        local_mode, local_content = local[name]
        if mode != local_mode:
            raise ValueError(f"Upstream file mode changed: {name}")
        if name not in PATCHED and content != local_content:
            raise ValueError(f"Unapproved upstream source change: {name}")
    for name in ADDED:
        if local[name][0] != "100644":
            raise ValueError(f"Unexpected added file mode: {name}")


def tracked_sources(root):
    result = subprocess.run(
        ["git", "ls-files", "--stage", "-z", "--", PREFIX],
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
        sources[path.removeprefix(PREFIX)] = (mode, (root / path).read_bytes())
    return sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    if args.archive:
        data = args.archive.read_bytes()
    else:
        with urllib.request.urlopen(ARCHIVE_URL, timeout=30) as response:
            data = response.read(5 * 1024 * 1024 + 1)
        if len(data) > 5 * 1024 * 1024:
            raise ValueError("Unexpected archive size")
    upstream = archive_sources(data)
    root = Path(__file__).resolve().parent.parent
    verify_sources(upstream, tracked_sources(root))
    print(f"Verified {len(upstream)} upstream files and modes; only the reviewed Windows reader and Cargokit Gradle sources may differ.")


if __name__ == "__main__":
    main()
