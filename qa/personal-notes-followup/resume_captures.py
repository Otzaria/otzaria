#!/usr/bin/env python3
"""Reuse verified gate/RED evidence and run only the repaired capture harness.

This helper never reruns or changes the recorded gate/RED results. The original
artifact is retained as a pinned TAR. Old captures are never imported into
the new output image or capture-source directories.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile

BUNDLE = Path(__file__).resolve().parent
CONFIG = json.loads((BUNDLE / 'config.json').read_text())
PRIOR_RUN = 42099805004
PRIOR_ARTIFACT = 13450021903
PRIOR_QA_COMMIT = '1b840186b8a5f331658befc17e41d19dbdaf15e8'
PRIOR_ZIP_SHA = '01c73c03072e1c38b2fef4cdf3276992a976c0eadb016b847b054847f1ca7943'
PRIOR_TAR_SHA = 'ea5585f0daed9fbe019262a5a4eb32d522ddfe2cf8f6a0c0e3fa4cac95d4a7ea'
PRIOR_SUMS_SHA = 'ec79cb3b02cf7f6a32a147c5286045692861f547fd721b3097cd1c1771a38204'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def checked_relative(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise ValueError('Unexpected artifact path: ' + name)
    return path


def verify_checksums(directory, filename, expected_manifest_sha=None):
    manifest = directory / filename
    if expected_manifest_sha is not None and sha(manifest) != expected_manifest_sha:
        raise ValueError('Checksum manifest is not the pinned artifact manifest')
    checked = set()
    for line in manifest.read_text().splitlines():
        digest, name = line.split('  ', 1)
        checked_relative(name)
        if not re.fullmatch('[0-9a-f]{64}', digest) or name in checked:
            raise ValueError('Invalid or duplicate checksum entry: ' + name)
        path = directory / name
        if not path.is_file() or path.is_symlink() or sha(path) != digest:
            raise ValueError('Checksum mismatch: ' + name)
        checked.add(name)
    actual = {str(p.relative_to(directory)) for p in directory.rglob('*') if p.is_file() and p != manifest}
    if actual != checked:
        raise ValueError('Artifact contains missing or unlisted files')
    return len(checked)


def assert_product(repo, product_sha, base_sha):
    if product_sha != CONFIG['frozen_product']['sha'] or base_sha != CONFIG['base_sha']:
        raise ValueError('Continuation requested a different product/base SHA')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=repo, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=all'], cwd=repo, text=True).strip()
    if head != product_sha or tree != CONFIG['frozen_product']['tree'] or dirty:
        raise ValueError('Continuation requires the same clean, exact product tree')


def prepare(args):
    if args.prior_tar is None or sha(args.prior_tar) != PRIOR_TAR_SHA:
        raise ValueError('Downloaded evidence TAR does not match the pinned SHA256')
    bundle_entries = verify_checksums(BUNDLE, 'BUNDLE_SHA256SUMS')
    destination = args.out / 'prior-run'
    destination.mkdir()
    with tarfile.open(args.prior_tar) as archive:
        for member in archive.getmembers():
            path = checked_relative(member.name)
            if path.parts[0] != 'personal-notes-qa-results' or not (member.isdir() or member.isfile()):
                raise ValueError('Unexpected artifact member: ' + member.name)
            target = destination.joinpath(*path.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source:
                    target.write_bytes(source.read())
    prior = destination / 'personal-notes-qa-results'
    entries = verify_checksums(prior, 'SHA256SUMS', PRIOR_SUMS_SHA)
    if entries != 44:
        raise ValueError('Unexpected prior artifact file count')
    gate = json.loads((prior / 'gate-result.json').read_text())
    red = json.loads((prior / 'red-result.json').read_text())
    snapshot = json.loads((prior / 'snapshot.json').read_text())
    report = json.loads((prior / 'qa-report.json').read_text())
    for record in [gate, red, snapshot, report]:
        if record['product_sha'] != args.product_sha or record['base_sha'] != args.base_sha:
            raise ValueError('Prior evidence refers to a different product/base SHA')
    if snapshot['product_tree'] != CONFIG['frozen_product']['tree']:
        raise ValueError('Prior evidence refers to a different product tree')
    if gate['status'] != 'PASS' or not gate['snapshot_unchanged'] or gate['format_analyze_tests_exit_codes'] != [0, 0, 0]:
        raise ValueError('The prior format/analyze/test gate did not pass')
    if gate['counts'] != {'passed': 1300, 'failed': 0, 'skipped': 1}:
        raise ValueError('Unexpected prior gate test counts')
    required_red = ['exactly_two_failed_assertions', 'no_loading_or_runtime_errors', 'machine_report_confirms_failed_run', 'snapshot_unchanged_after_restore']
    if red['status'] != 'PASS' or not all(red[name] is True for name in required_red):
        raise ValueError('The prior RED demonstration/restoration did not pass')
    if len(red['verified_tests']) != 2 or not all(test['expected_assertion_confirmed'] is True for test in red['verified_tests']):
        raise ValueError('The prior RED assertions were not both confirmed')
    if report['phases']['gate'] != gate or report['phases']['red'] != red:
        raise ValueError('Prior combined report disagrees with phase evidence')
    imported = {'gate-result.json', 'red-result.json', 'snapshot.json', 'gate-tests.events.jsonl', 'red-tests.events.jsonl'}
    for phase in [gate, red]:
        for stage in phase['stages']:
            if sha(prior / stage['log']) != stage['log_sha256']:
                raise ValueError('A prior stage log hash does not match')
            imported.update([stage['log'], stage['name'] + '.json'])
    for name in sorted(imported):
        shutil.copyfile(prior / name, args.out / name)
    provenance = {
        'product_sha': args.product_sha,
        'product_tree': snapshot['product_tree'],
        'base_sha': args.base_sha,
        'reused_phases': ['gate', 'red'],
        'phases_executed_this_run': ['capture-dependencies', 'captures'],
        'prior_run_id': PRIOR_RUN,
        'prior_run_url': f'https://github.com/Otzaria/otzaria/actions/runs/{PRIOR_RUN}',
        'prior_artifact_id': PRIOR_ARTIFACT,
        'prior_qa_commit': PRIOR_QA_COMMIT,
        'prior_artifact_zip_sha256': PRIOR_ZIP_SHA,
        'prior_artifact_download_digest_check': 'actions/download-artifact pinned v8.0.2; digest-mismatch=error',
        'prior_artifact_tar_sha256': PRIOR_TAR_SHA,
        'prior_checksums_sha256': PRIOR_SUMS_SHA,
        'prior_checksum_entries_verified': entries,
        'prior_gate_result_sha256': sha(prior / 'gate-result.json'),
        'prior_red_result_sha256': sha(prior / 'red-result.json'),
        'prior_snapshot_sha256': sha(prior / 'snapshot.json'),
        'capture_bundle_checksums_sha256': sha(BUNDLE / 'BUNDLE_SHA256SUMS'),
        'capture_bundle_checksum_entries_verified': bundle_entries,
        'current_run_id': os.environ.get('GITHUB_RUN_ID'),
        'current_qa_commit': os.environ.get('GITHUB_SHA'),
        'note': 'Gate and RED ran only in the prior run. Their original bytes and timestamps are preserved. The original artifact is retained as a pinned TAR. Old capture outputs were not imported; only newly generated images are current capture evidence.',
    }
    shutil.copyfile(args.prior_tar, args.out / f'prior-run-{PRIOR_RUN}.tar')
    shutil.rmtree(destination)
    save(args.out / 'continuation-provenance.json', provenance)
    print(json.dumps(provenance, ensure_ascii=False, indent=2))
    return 0


def summarize(args):
    command = [sys.executable, str(BUNDLE / 'run_qa.py'), '--repo', str(args.repo), '--product-sha', args.product_sha, '--base-sha', args.base_sha, '--out', str(args.out), '--phase', 'summarize']
    result = subprocess.run(command, check=False)
    original = args.out / f'prior-run-{PRIOR_RUN}.tar'
    if sha(original) != PRIOR_TAR_SHA:
        raise ValueError('Original evidence archive was changed')
    with tarfile.open(original) as archive:
        for name in ['gate-result.json', 'red-result.json', 'snapshot.json']:
            with archive.extractfile('personal-notes-qa-results/' + name) as source:
                if (args.out / name).read_bytes() != source.read():
                    raise ValueError('Inherited evidence was changed: ' + name)
    report_path = args.out / 'qa-report.json'
    report = json.loads(report_path.read_text())
    report['provenance'] = json.loads((args.out / 'continuation-provenance.json').read_text())
    save(report_path, report)
    manifest = args.out / 'SHA256SUMS'
    lines = [f'{sha(p)}  {p.relative_to(args.out)}' for p in sorted(args.out.rglob('*')) if p.is_file() and p != manifest]
    manifest.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=['prepare', 'summarize'], required=True)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--product-sha', required=True)
    parser.add_argument('--base-sha', required=True)
    parser.add_argument('--prior-tar', type=Path)
    args = parser.parse_args()
    args.repo = args.repo.resolve()
    args.out = args.out.resolve()
    if BUNDLE.is_relative_to(args.repo) or args.out.is_relative_to(args.repo):
        raise ValueError('Bundle and evidence must remain outside the product checkout')
    args.out.mkdir(parents=True, exist_ok=True)
    assert_product(args.repo, args.product_sha, args.base_sha)
    return {'prepare': prepare, 'summarize': summarize}[args.phase](args)


if __name__ == '__main__':
    sys.exit(main())
