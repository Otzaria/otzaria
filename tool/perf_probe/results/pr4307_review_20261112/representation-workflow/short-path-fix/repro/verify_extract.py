#!/usr/bin/env python3
"""Validate and preserve a downloaded workflow ZIP before isolated extraction."""

import argparse
import hashlib
import json
import re
import shutil
import stat
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


def sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--run-attempt", type=int, required=True)
    parser.add_argument("--job-id", type=int, required=True)
    parser.add_argument("--artifact-id", type=int, required=True)
    parser.add_argument("--expected-sha256")
    arguments = parser.parse_args()
    original = arguments.zip.resolve(strict=True)
    destination = arguments.destination.resolve()
    if destination.exists():
        raise RuntimeError("Extraction destination must not already exist")
    archive_sha = sha256(original)
    expected = arguments.expected_sha256
    if expected:
        expected = expected.removeprefix("sha256:").lower()
        if not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise RuntimeError("Invalid expected SHA256")
        if archive_sha != expected:
            raise RuntimeError("Archive SHA256 differs from the declared artifact digest; original ZIP retained")
    with zipfile.ZipFile(original) as archive:
        members = archive.infolist()
        paths = set()
        casefolded = set()
        for member in members:
            name = member.filename
            path = PurePosixPath(name)
            if name != member.orig_filename or "\0" in name or "\\" in name:
                raise RuntimeError(f"Ambiguous ZIP path: {name!r}")
            if not name or path.is_absolute() or any(part in {"", ".", ".."} for part in name.rstrip("/").split("/")):
                raise RuntimeError(f"Unsafe ZIP path: {name!r}")
            if ":" in name or name.startswith("/"):
                raise RuntimeError(f"Drive or alternate-stream ZIP path: {name!r}")
            normalized = path.as_posix().rstrip("/")
            if normalized in paths or normalized.casefold() in casefolded:
                raise RuntimeError(f"Duplicate/colliding ZIP path: {name!r}")
            paths.add(normalized)
            casefolded.add(normalized.casefold())
            file_type = stat.S_IFMT(member.external_attr >> 16)
            if file_type not in {0, stat.S_IFREG, stat.S_IFDIR}:
                raise RuntimeError(f"Unsupported special file in ZIP: {name!r}")
            if member.flag_bits & 1:
                raise RuntimeError(f"Encrypted ZIP member: {name!r}")
        files = {member.filename.rstrip("/") for member in members if not member.is_dir()}
        for path in paths:
            if any(parent.as_posix() in files for parent in PurePosixPath(path).parents):
                raise RuntimeError(f"ZIP parent path is a file: {path!r}")
        uncompressed_bytes = sum(member.file_size for member in members)
        free = shutil.disk_usage(original.parent).free
        if free <= uncompressed_bytes:
            raise RuntimeError("Insufficient free space for lossless extraction; original ZIP retained")
        bad = archive.testzip()
        if bad is not None:
            raise RuntimeError(f"ZIP CRC failure: {bad!r}; original ZIP retained")
        destination.mkdir(parents=True)
        rows = []
        for member in members:
            path = destination.joinpath(*PurePosixPath(member.filename).parts)
            if member.is_dir():
                path.mkdir(parents=True, exist_ok=True)
                rows.append({"path": member.filename, "directory": True, "bytes": 0})
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as source, path.open("xb") as output:
                shutil.copyfileobj(source, output)
            if path.stat().st_size != member.file_size:
                raise RuntimeError(f"Extracted size mismatch: {member.filename!r}")
            rows.append({
                "path": member.filename,
                "bytes": member.file_size,
                "compressed_bytes": member.compress_size,
                "zip_crc32": f"{member.CRC:08x}",
                "sha256": sha256(path),
            })
    if sha256(original) != archive_sha:
        raise RuntimeError("Original ZIP changed during extraction")
    receipt = {
        "verified_at_utc": datetime.now(timezone.utc).isoformat(),
        "run_id": arguments.run_id,
        "run_attempt": arguments.run_attempt,
        "job_id": arguments.job_id,
        "artifact_id": arguments.artifact_id,
        "original_zip": str(original),
        "zip_bytes": original.stat().st_size,
        "zip_sha256": archive_sha,
        "declared_artifact_sha256": expected,
        "declared_digest_matches": archive_sha == expected if expected else None,
        "all_zip_member_crcs_valid": True,
        "all_zip_paths_checked_before_extraction": True,
        "member_count": len(rows),
        "uncompressed_bytes": uncompressed_bytes,
        "extracted_root": str(destination),
        "all_members_preserved": True,
        "members": rows,
    }
    arguments.receipt.parent.mkdir(parents=True, exist_ok=True)
    with arguments.receipt.open("x", encoding="utf-8") as output:
        json.dump(receipt, output, ensure_ascii=False, indent=2)
        output.write("\n")
    print(json.dumps({key: value for key, value in receipt.items() if key != "members"}, indent=2))


if __name__ == "__main__":
    main()
