#!/usr/bin/env python3
"""Fetch the exact store sources read by the real installed-plugin probe."""

import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import urllib.request

COMMIT = "4517d39c4ecab632aff98e1c0e414881695961aa"
HASHES = {
    "manifest.json": "a40e4225682f948d657e94086217f8400b4d708ec1eaa958e37621113bd12feb",
    "index.html": "c6495a41ffc31a8e4b23828b3537c40478d0aa7d45a3cf680534e4e0cd0fed2f",
    "restore-state.js": "f0324b025009e9594135b17b911366388959ab5398c0485ac11b0316cd59332f",
    "i18n/en.js": "54f9ec3b69a2858d2a1bb0f6d80f641397c3ff1fd286a83cdb5e751af3366ef2",
    "background.html": "0110c549b0350222c63c098843c9b6debdcd61cebd57d91b11874f07426fc975",
}


def prepare(output: Path) -> None:
    if not output.is_absolute():
        raise ValueError("Use an absolute fresh output directory")
    for parent in (output, *output.parents):
        if parent.is_symlink():
            raise ValueError(f"Source path traverses a symlink: {parent}")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Source output directory must be empty")
    output.mkdir(parents=True, exist_ok=True)
    for name, expected in HASHES.items():
        url = f"https://raw.githubusercontent.com/Otzaria/otzaria-plugins-store/{COMMIT}/{name}"
        with urllib.request.urlopen(url, timeout=45) as response:
            data = response.read(2 * 1024 * 1024 + 1)
        if len(data) > 2 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"Pinned source hash mismatch: {name}")
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    (output / "source-provenance.json").write_text(
        json.dumps({"repository": "Otzaria/otzaria-plugins-store", "commit": COMMIT, "sha256": HASHES}, indent=2) + "\n",
        encoding="utf-8",
    )


def write_defines(source: Path, destination: Path) -> None:
    if not destination.is_absolute() or destination.exists():
        raise ValueError("Use a fresh absolute defines output path")
    for parent in (destination, *destination.parents):
        if parent.is_symlink():
            raise ValueError(f"Defines output traverses a symlink: {parent}")
    contents = {}
    for name, expected in HASHES.items():
        data = (source / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"Source changed before transport: {name}")
        contents[name] = data.decode("utf-8")
    raw = json.dumps(contents, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    compressed = gzip.compress(raw, compresslevel=9, mtime=0)
    if len(raw) > 512 * 1024 or len(compressed) > 128 * 1024:
        raise ValueError("Store transport exceeds runner limits")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({
        "INSTALLED_PROBE_STORE_PAYLOAD": base64.b64encode(compressed).decode("ascii"),
    }) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--defines-output", type=Path,
                        help="Optional dart-define-from-file input for physical devices")
    args = parser.parse_args()
    prepare(args.output)
    if args.defines_output:
        write_defines(args.output, args.defines_output)
    print(json.dumps({"source": str(args.output), "commit": COMMIT, "files": len(HASHES)}))
