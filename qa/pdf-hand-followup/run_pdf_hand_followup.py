#!/usr/bin/env python3
"""Run only the two PDF test files changed after an unchanged product passed QA."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import traceback

BASE_PRODUCT_SHA = 'fe27937a7e368bfc3d7d51203fe9497b186fbcb4'
BASE_PRODUCT_TREE = '30e8224cb46e5788242d6bcfcfaf030f7f328809'
PRIOR_REVIEW_SHA256 = 'e12c4337d56a3147b459e12a96da2d141404e027aef065020e81439e1a865323'
ALLOWED_TESTS = (
    'test/pdf_book/pdf_hand_mode_test.dart',
    'test/pdf_book/pdf_personal_note_viewer_test.dart',
)
FLUTTER_VERSION = '3.47.7'
BUNDLE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def now():
    return datetime.now(timezone.utc).isoformat()


def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()


def assert_clean_target(repo, target):
    if not re.fullmatch('[0-9a-f]{40}', target):
        raise ValueError('TARGET_SHA must be an exact lowercase 40-character commit SHA')
    if git(repo, 'rev-parse', 'HEAD') != target:
        raise ValueError('Checkout HEAD differs from TARGET_SHA')
    if git(repo, 'status', '--porcelain', '--untracked-files=all'):
        raise ValueError('Target checkout is not clean')


def verify_delta(repo, target):
    assert_clean_target(repo, target)
    if git(repo, 'rev-parse', BASE_PRODUCT_SHA + '^{tree}') != BASE_PRODUCT_TREE:
        raise ValueError('Baseline product tree does not match the approved QA snapshot')
    subprocess.run(['git', 'merge-base', '--is-ancestor', BASE_PRODUCT_SHA, target], cwd=repo, check=True)
    raw = subprocess.check_output(['git', 'diff', '--raw', '--no-abbrev', '--no-renames', '-z', BASE_PRODUCT_SHA, target], cwd=repo, text=True)
    tokens = raw.rstrip('\0').split('\0') if raw else []
    if len(tokens) != 4:
        raise ValueError('Expected exactly two modified test paths')
    records = []
    for index in range(0, len(tokens), 2):
        metadata, path = tokens[index:index + 2]
        fields = metadata.split()
        if len(fields) != 5 or fields[0] != ':100644' or fields[1] != '100644' or fields[4] != 'M':
            raise ValueError('Only regular-file test modifications are permitted: ' + metadata)
        records.append({'path': path, 'old_blob': fields[2], 'new_blob': fields[3], 'status': fields[4]})
    if {item['path'] for item in records} != set(ALLOWED_TESTS):
        raise ValueError('A path outside the two allowed test files changed')
    return records


def verify_bundle():
    manifest = BUNDLE / 'BUNDLE_SHA256SUMS'
    listed = set()
    for line in manifest.read_text().splitlines():
        digest, name = line.split('  ', 1)
        if Path(name).is_absolute() or '..' in Path(name).parts or name in listed:
            raise ValueError('Invalid bundle checksum path')
        path = BUNDLE / name
        if not path.is_file() or path.is_symlink() or sha(path) != digest:
            raise ValueError('Bundle checksum mismatch: ' + name)
        listed.add(name)
    actual = {str(p.relative_to(BUNDLE)) for p in BUNDLE.rglob('*') if p.is_file() and p != manifest}
    if actual != listed:
        raise ValueError('Bundle contains unlisted or missing files')
    prior_file = BUNDLE / 'prior-independent-review.json'
    if sha(prior_file) != PRIOR_REVIEW_SHA256:
        raise ValueError('The approved prior review changed')
    prior = json.loads(prior_file.read_text())
    if prior['status'] != 'PASS' or prior['product_sha'] != BASE_PRODUCT_SHA or prior['product_tree'] != BASE_PRODUCT_TREE:
        raise ValueError('Prior evidence does not describe the approved product')
    return prior


def source_snapshot(repo, target):
    assert_clean_target(repo, target)
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=repo, text=True).rstrip('\0').split('\0')
    source_suffixes = ('.dart', '.cpp', '.c', '.h', '.hpp', '.swift', '.kt', '.java', '.yaml', '.yml', '.lock', '.toml')
    names = sorted(name for name in tracked if name.endswith(source_suffixes))
    if (repo / '.dart_tool/package_config.json').is_file():
        names.append('.dart_tool/package_config.json')
    return {
        'target_sha': target,
        'target_tree': git(repo, 'rev-parse', 'HEAD^{tree}'),
        'files': [{'path': name, 'sha256': sha(repo / name)} for name in names],
    }


def run(repo, out, stages, label, command):
    record = {'name': label, 'command': command, 'started_utc': now()}
    log_path = out / (label + '.log')
    print('QA_STAGE=' + label, flush=True)
    with log_path.open('w') as log:
        process = subprocess.Popen(command, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        try:
            for line in process.stdout:
                log.write(line)
                log.flush()
                sys.stdout.write(line)
                sys.stdout.flush()
            code = process.wait()
        except BaseException:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise
    record.update({'exit_code': code, 'completed_utc': now(), 'log': log_path.name, 'log_sha256': sha(log_path)})
    stages.append(record)
    save(out / (label + '.json'), record)
    return code


def summarize_tests(path, repo):
    events = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    suites = {event['suite']['id']: event['suite']['path'] for event in events if event.get('type') == 'suite'}
    if {str(Path(path).resolve()) for path in suites.values()} != {str(repo / name) for name in ALLOWED_TESTS}:
        raise ValueError('Machine report does not cover exactly the two selected test files')
    tests = {event['test']['id']: event['test'] for event in events if event.get('type') == 'testStart'}
    terminal = [event for event in events if event.get('type') == 'done']
    errors = [event for event in events if event.get('type') == 'error']
    completed = [event for event in events if event.get('type') == 'testDone']
    failures = [event for event in completed if event.get('result') != 'success' and not event.get('skipped', False)]
    visible = [event for event in completed if not event.get('hidden', False) and not tests.get(event['testID'], {}).get('name', '').endswith(('(setUpAll)', '(tearDownAll)')) and not tests.get(event['testID'], {}).get('name', '').startswith('loading ')]
    counts = {'passed': 0, 'failed': 0, 'skipped': 0}
    per_suite = {suite_id: 0 for suite_id in suites}
    for event in visible:
        if event.get('skipped', False):
            counts['skipped'] += 1
        elif event.get('result') == 'success':
            counts['passed'] += 1
            per_suite[tests[event['testID']]['suiteID']] += 1
        else:
            counts['failed'] += 1
    valid = len(terminal) == 1 and terminal[0].get('success') is True and not errors and not failures and counts['skipped'] == 0 and all(count > 0 for count in per_suite.values())
    return valid, {'counts': counts, 'error_events': len(errors), 'failed_events_including_loaders': len(failures), 'terminal_done_success': len(terminal) == 1 and terminal[0].get('success') is True, 'passed_per_file': {suites[key]: count for key, count in per_suite.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--target-sha', required=True)
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    if BUNDLE.is_relative_to(repo) or out.is_relative_to(repo):
        raise ValueError('QA bundle and output must be outside the product checkout')
    out.mkdir(parents=True, exist_ok=True)
    os.environ.update({'TZ': 'Asia/Jerusalem', 'OTZARIA_REQUIRE_SEARCH_ENGINE': '1', 'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true'})
    stages = []
    result = {'status': 'FAIL', 'target_sha': args.target_sha, 'approved_product_sha': BASE_PRODUCT_SHA, 'started_utc': now(), 'stages': stages, 'selected_test_files': list(ALLOWED_TESTS), 'retry': False}
    before = None
    try:
        prior = verify_bundle()
        result['delta'] = verify_delta(repo, args.target_sha)
        result['clean_before'] = True
        result['all_product_paths_including_lib_windows_and_dependencies_identical_to_approved_product'] = True
        result['provenance'] = {'prior_review_sha256': PRIOR_REVIEW_SHA256, 'prior_review': prior, 'inherited_checks': ['1300-test gate', '#4292 RED', 'six UI captures'], 'rerun_in_this_job': False, 'basis': 'The exact Git diff from the approved product contains only the two test-file modifications listed in this report; every other tracked path is identical.', 'current_run_id': os.environ.get('GITHUB_RUN_ID'), 'current_qa_commit': os.environ.get('GITHUB_SHA')}
        shutil.copyfile(BUNDLE / 'prior-independent-review.json', out / 'prior-independent-review.json')
        if run(repo, out, stages, 'dependencies', ['flutter', 'pub', 'get', '--enforce-lockfile']) != 0:
            raise RuntimeError('Enforced dependency resolution failed')
        assert_clean_target(repo, args.target_sha)
        if run(repo, out, stages, 'flutter-version', ['flutter', '--version', '--machine']) != 0:
            raise RuntimeError('Could not read Flutter version')
        version = json.loads((out / 'flutter-version.log').read_text())
        if version.get('frameworkVersion') != FLUTTER_VERSION:
            raise RuntimeError('Unexpected Flutter version')
        result['flutter_version'] = version
        before = source_snapshot(repo, args.target_sha)
        save(out / 'source-before.json', before)
        codes = [run(repo, out, stages, 'format', ['dart', 'format', '--output=none', '--set-exit-if-changed', *ALLOWED_TESTS])]
        codes.append(run(repo, out, stages, 'analyze', ['flutter', 'analyze', '--no-pub', '--fatal-infos']))
        events_path = out / 'targeted-tests.events.jsonl'
        codes.append(run(repo, out, stages, 'targeted-tests', ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded', '--file-reporter', f'json:{events_path}', *ALLOWED_TESTS]))
        valid, details = summarize_tests(events_path, repo)
        result.update(details)
        result['format_analyze_tests_exit_codes'] = codes
        result['status'] = 'PASS' if valid and all(code == 0 for code in codes) else 'FAIL'
    except Exception as error:
        result.update({'error': str(error), 'traceback': traceback.format_exc()})
        print(result['traceback'], file=sys.stderr, flush=True)
    finally:
        try:
            assert_clean_target(repo, args.target_sha)
            result['clean_after'] = True
            result['target_tree'] = git(repo, 'rev-parse', 'HEAD^{tree}')
            if before is not None:
                after = source_snapshot(repo, args.target_sha)
                save(out / 'source-after.json', after)
                result['source_and_test_file_count'] = len(before['files'])
                result['source_snapshot_unchanged'] = before == after
                if before != after:
                    raise RuntimeError('Source or dependency snapshot changed during QA')
        except Exception as error:
            result.update({'status': 'FAIL', 'clean_after': False, 'source_verification_error': str(error)})
        result['completed_utc'] = now()
        save(out / 'qa-report.json', result)
        manifest = out / 'SHA256SUMS'
        manifest.write_text(''.join(f'{sha(path)}  {path.relative_to(out)}\n' for path in sorted(out.rglob('*')) if path.is_file() and path != manifest), encoding='utf-8')
    print('QA_RESULT=' + json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
