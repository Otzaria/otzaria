#!/usr/bin/env python3
"""Inventory a staged release bundle; never interpret it as device install size."""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import zipfile


def category(path: str) -> str:
    name = PurePosixPath(path).name.lower()
    parts = path.lower().split('/')
    if name.endswith(('.pdb', '.debug', '.dwp')) or any(
        part.endswith('.dsym') for part in parts
    ):
        return 'debug_symbols'
    if name.endswith(('.ttf', '.otf', '.ttc', '.woff', '.woff2')):
        return 'fonts'
    if name in ('app.so', 'libapp.so') or (name == 'app' and 'app.framework' in parts):
        return 'dart_aot'
    if any(part.endswith('.framework') and name == part[:-10] for part in parts):
        return 'native'
    if name.endswith(('.dll', '.dylib', '.exe', '.a', '.lib')) or re.search(
        r'\.so(?:\.\d+)*$', name
    ) or name in ('otzaria', 'wpewebprocess', 'wpenetworkprocess'):
        return 'native'
    if name.endswith(('.onnx', '.onnx_data')):
        return 'models'
    if 'flutter_assets' in parts:
        return 'assets'
    return 'other'


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def summarize(files: list[dict], links: list[dict], unique_bytes: int | None, allocated_bytes: int | None) -> dict:
    files.sort(key=lambda item: item['path'])
    totals = defaultdict(int)
    for item in files:
        totals[item['category']] += item['bytes']
    return {
        'schema_version': 1,
        'classification': 'path_heuristic',
        'bundle_file_bytes': sum(item['bytes'] for item in files),
        'unique_file_bytes': unique_bytes,
        'allocated_file_bytes_on_measurement_host': allocated_bytes,
        'installed_size_bytes': None,
        'file_count': len(files),
        'category_bytes': dict(sorted(totals.items())),
        'largest_files': sorted(files, key=lambda item: (-item['bytes'], item['path']))[:20],
        'symlinks': sorted(links, key=lambda item: item['path']),
        'files': files,
        'duplicate_content_groups': None,
    }


def zip_inventory(archive: Path) -> dict:
    files, links = [], []
    seen = set()
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            # orig_filename preserves separators and NULs before ZipInfo's
            # host-specific normalization/truncation. Never accept an alias.
            name = entry.orig_filename
            path = PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name or '\x00' in name:
                raise ValueError(f'ambiguous archive path: {name}')
            if entry.is_dir():
                continue
            normalized = path.as_posix()
            if normalized in seen:
                raise ValueError(f'duplicate archive path: {normalized}')
            seen.add(normalized)
            mode = entry.external_attr >> 16
            if entry.create_system == 3 and stat.S_ISLNK(mode):
                links.append({'path': normalized, 'target': None})
            elif stat.S_IFMT(mode) not in (0, stat.S_IFREG):
                raise ValueError(f'unsupported archive entry: {normalized}')
            else:
                files.append({'path': normalized, 'bytes': entry.file_size,
                              'category': category(normalized)})
    result = summarize(files, links, None, None)
    result['measurement'] = 'zip_metadata_not_extracted_or_crc_verified'
    return result


def inventory(root: Path, *, duplicates: bool = False) -> dict:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError('bundle must be a directory')
    files = []
    links = []
    seen_inodes = set()
    unique_bytes = 0
    allocated_bytes = 0
    allocation_available = True
    pending = [root]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                relative = path.relative_to(root).as_posix()
                metadata = entry.stat(follow_symlinks=False)
                if stat.S_ISLNK(metadata.st_mode):
                    links.append({'path': relative, 'target': os.readlink(path)})
                elif stat.S_ISDIR(metadata.st_mode):
                    pending.append(path)
                elif stat.S_ISREG(metadata.st_mode):
                    # Windows DirEntry.stat reports zero st_ino/st_dev; a fresh
                    # lstat is needed to recognize hard links on that host.
                    if not metadata.st_ino:
                        metadata = path.stat(follow_symlinks=False)
                        if not stat.S_ISREG(metadata.st_mode):
                            raise ValueError(f'bundle changed during audit: {relative}')
                    # A zero inode is not a usable hard-link identity on all hosts.
                    identity = (metadata.st_dev, metadata.st_ino) if metadata.st_ino else relative
                    if identity not in seen_inodes:
                        seen_inodes.add(identity)
                        unique_bytes += metadata.st_size
                        blocks = getattr(metadata, 'st_blocks', None)
                        if blocks is None:
                            allocation_available = False
                        else:
                            allocated_bytes += blocks * 512
                    files.append({'path': relative, 'bytes': metadata.st_size,
                                  'category': category(relative)})
                else:
                    raise ValueError(f'unsupported special file: {relative}')
    result = summarize(files, links, unique_bytes, allocated_bytes if allocation_available else None)
    result['measurement'] = 'directory_file_metadata'
    if duplicates:
        by_size = defaultdict(list)
        for item in files:
            if item['bytes']:
                by_size[item['bytes']].append(item['path'])
        groups = []
        for size, paths in sorted(by_size.items()):
            if len(paths) < 2:
                continue
            by_hash = defaultdict(list)
            for relative in paths:
                path = root / relative
                before = path.stat(follow_symlinks=False)
                if not stat.S_ISREG(before.st_mode) or before.st_size != size:
                    raise ValueError(f'bundle changed during audit: {relative}')
                digest = sha256(path)
                after = path.stat(follow_symlinks=False)
                if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
                    after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns
                ):
                    raise ValueError(f'bundle changed during audit: {relative}')
                by_hash[digest].append(relative)
            for digest, matches in sorted(by_hash.items()):
                if len(matches) > 1:
                    groups.append({'bytes_per_file': size, 'sha256': digest, 'paths': matches})
        result['duplicate_content_groups'] = groups
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path, help='staged directory or ZIP/APK/MSIX archive')
    parser.add_argument('--target', required=True, help='for example windows-x64 or android-arm64')
    parser.add_argument('--source-commit', required=True, help='caller-provided build commit label')
    parser.add_argument('--download', type=Path, help='the actual distributable, not a recompressed estimate')
    parser.add_argument('--lockfile', type=Path, action='append', default=[])
    parser.add_argument('--duplicates', action='store_true', help='hash same-sized files using bounded buffers')
    parser.add_argument('--output', type=Path, required=True, help='must be outside the bundle')
    args = parser.parse_args(argv)
    try:
        root = args.bundle.resolve(strict=True)
        output = args.output.resolve()
        if output == root or root in output.parents:
            raise ValueError('output must be outside the measured bundle')
        inputs = [*args.lockfile, *([args.download] if args.download else [])]
        if any(output == path.resolve() for path in inputs):
            raise ValueError('output must not overwrite a download or lockfile')
        if root.is_dir():
            report = inventory(root, duplicates=args.duplicates)
        else:
            if args.duplicates:
                raise ValueError('--duplicates requires a staged directory')
            report = zip_inventory(root)
        report.update(target=args.target, source_commit=args.source_commit,
                      download_bytes=None, download_sha256=None)
        download = args.download or (root if root.is_file() else None)
        if download:
            if not download.is_file():
                raise ValueError('download must be a regular file')
            report['download_bytes'] = download.stat().st_size
            report['download_sha256'] = sha256(download)
        report['lockfiles'] = [{'path': str(path), 'sha256': sha256(path)} for path in args.lockfile]
        output.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(dir=output.parent, prefix='.size-audit-', suffix='.tmp')
        try:
            with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
                json.dump(report, stream, ensure_ascii=False, indent=2)
                stream.write('\n')
            os.replace(temporary, output)
        finally:
            Path(temporary).unlink(missing_ok=True)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f'error: {error}\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
