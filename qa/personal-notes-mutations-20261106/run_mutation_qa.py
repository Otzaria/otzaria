#!/usr/bin/env python3
"""Run exact-commit notes QA and prove the regression against its real base."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


bundle = Path(__file__).resolve().parent
manifest = json.loads((bundle / 'manifest.json').read_text())
repo = Path(os.environ['GITHUB_WORKSPACE']).resolve()
out = Path(os.environ['QA_OUT_DIR']).resolve()
out.mkdir(parents=True, exist_ok=True)
target = os.environ['TARGET_SHA']
base = manifest['base_sha']
report = {'status': 'FAIL', 'target_sha': target, 'base_sha': base, 'checks': {}}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()


def run(label, args):
    log = out / (label + '.log')
    print('RUN ' + label + ': ' + ' '.join(args), flush=True)
    with log.open('w') as stream:
        result = subprocess.run(args, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
    report['checks'][label] = {'exit_code': result.returncode}
    if result.returncode:
        print(log.read_text(errors='replace')[-18000:], flush=True)
    return result.returncode


def events(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def summarize(path):
    data = events(path)
    tests = {row['test']['id']: row['test'] for row in data if row['type'] == 'testStart'}
    results = [row for row in data if row['type'] == 'testDone' and not row.get('hidden', False)]
    return {
        'passed': sum(row['result'] == 'success' and not row.get('skipped', False) for row in results),
        'skipped': sum(row.get('skipped', False) for row in results),
        'failed': [tests.get(row['testID'], {}).get('name', str(row['testID'])) for row in results if row['result'] != 'success'],
        'completed': any(row['type'] == 'done' for row in data),
    }


red_fixtures = {
    repo / 'test/personal_notes/qa_mutation_ack_red_test.dart': bundle / 'mutation_ack_red_test.dart',
    repo / 'test/personal_notes/qa_manager_confirmation_red_test.dart': bundle / 'manager_confirmation_red_test.dart',
    repo / 'test/personal_notes/widgets/qa_sidebar_confirmation_red_test.dart': bundle / 'sidebar_confirmation_red_test.dart',
}


def copy_red_fixtures():
    for destination, source in red_fixtures.items():
        shutil.copyfile(source, destination)


def remove_red_fixtures():
    for destination in red_fixtures:
        if destination.exists():
            destination.unlink()


try:
    for sha in [target, base]:
        if not re.fullmatch('[0-9a-f]{40}', sha):
            raise RuntimeError('Expected a frozen commit SHA')
    expected_red = set(manifest['red_test_names'])
    if expected_red != {
        'reposition refuses an already deleted note instead of reporting success',
        'reposition refuses an id belonging to a different book',
        'manager acknowledges delete without a post-write list read',
        'manager acknowledges reposition without a post-write list read',
        'sidebar does not announce a failed reposition as successful',
    }:
        raise RuntimeError('RED manifest does not name the five regression assertions')
    red_selection = '^(?:' + '|'.join(re.escape(name) for name in sorted(expected_red)) + ')$'
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('QA must start on the exact clean product commit')
    if git('rev-parse', target + '^') != base:
        raise RuntimeError('Product commit is not based on the reviewed upstream commit')
    changed = git('diff', '--name-only', base, target).splitlines()
    if sorted(changed) != sorted(manifest['changed_files']):
        raise RuntimeError('Unexpected product file inventory: ' + repr(changed))
    report['source_hashes'] = {}
    for name, expected in manifest['source_sha256'].items():
        actual = hashlib.sha256((repo / name).read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError('Source hash mismatch: ' + name)
        report['source_hashes'][name] = actual

    if run('pub-get', ['flutter', 'pub', 'get', '--enforce-lockfile']):
        raise RuntimeError('Locked dependency resolution failed')
    for label, command in [
        ('settings-index', ['dart', 'run', 'tool/generate_search_index.dart']),
        ('settings-catalog', ['dart', 'run', 'tool/generate_settings_l10n.dart']),
    ]:
        if run(label, command):
            raise RuntimeError(label + ' failed')
    if git('diff', '--name-only'):
        raise RuntimeError('Dependency setup or generators changed tracked files')

    dart_files = [name for name in changed if name.endswith('.dart')]
    format_code = run('format', ['dart', 'format', '--output=none', '--set-exit-if-changed', *dart_files])
    if format_code:
        # Export suggestions without modifying the exact product being tested.
        for name in dart_files:
            destination = out / 'formatted' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open('w') as stream:
                subprocess.run(['dart', 'format', '--output=show', '--summary=none', name], cwd=repo, stdout=stream, check=True)
    analyze_code = run('analyze', ['flutter', 'analyze'])
    test_report = out / 'focused-tests.json'
    test_code = run('focused-tests', [
        'flutter', 'test', '-j', '4', '--file-reporter', 'json:' + str(test_report),
        *manifest['test_targets'],
    ])
    if test_report.exists():
        report['focused_tests'] = summarize(test_report)
        if not report['focused_tests']['completed']:
            raise RuntimeError('Focused test stream did not complete')

    if any(path.exists() for path in red_fixtures):
        raise RuntimeError('Temporary RED test would overwrite a repository file')
    subprocess.run(['git', 'checkout', '--detach', base], cwd=repo, check=True)
    copy_red_fixtures()
    red_report = out / 'red-tests.json'
    red_code = run('red-tests', [
        'flutter', 'test', '--file-reporter', 'json:' + str(red_report),
        '--name', red_selection, *map(str, red_fixtures),
    ])
    if not red_report.exists():
        raise RuntimeError('RED run produced no test report')
    red_data = events(red_report)
    red_tests = {row['test']['id']: row['test']['name'] for row in red_data if row['type'] == 'testStart'}
    red_done = {red_tests[row['testID']]: row for row in red_data if row['type'] == 'testDone' and row['testID'] in red_tests}
    failed_assertions = {red_tests.get(row['testID']) for row in red_data if row['type'] == 'error' and row.get('isFailure') is True}
    if red_code == 0 or any(name not in failed_assertions or red_done.get(name, {}).get('result') not in ['failure', 'error'] for name in expected_red):
        raise RuntimeError('RED did not fail with all expected assertions; compilation failure is not a RED proof')
    report['red_proof'] = {'expected_assertion_failures': sorted(expected_red), **summarize(red_report)}
    if not report['red_proof']['completed']:
        raise RuntimeError('RED test stream did not complete')

    remove_red_fixtures()
    subprocess.run(['git', 'checkout', '--detach', target], cwd=repo, check=True)
    copy_red_fixtures()
    green_report = out / 'green-tests.json'
    green_code = run('green-tests', [
        'flutter', 'test', '--file-reporter', 'json:' + str(green_report),
        '--name', red_selection, *map(str, red_fixtures),
    ])
    if green_report.exists():
        report['green_proof'] = summarize(green_report)
    green = report.get('green_proof', {})
    if not green.get('completed') or green.get('passed') != len(expected_red) or green.get('skipped') or green.get('failed'):
        raise RuntimeError('The five regression assertions must pass on the product commit')
    remove_red_fixtures()
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('Product checkout changed during verification')
    if any([format_code, analyze_code, test_code, green_code]):
        raise RuntimeError('One or more product checks failed')
    report['status'] = 'PASS'
except Exception as error:
    report['error'] = str(error)
    print('QA ERROR: ' + str(error), flush=True)
finally:
    remove_red_fixtures()
    subprocess.run(['git', 'checkout', '--detach', target], cwd=repo, check=False)
    (out / 'qa-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    sums = [hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + str(path.relative_to(out)) for path in sorted(out.rglob('*')) if path.is_file() and path.name != 'SHA256SUMS']
    (out / 'SHA256SUMS').write_text('\n'.join(sums) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
sys.exit(0 if report['status'] == 'PASS' else 1)
