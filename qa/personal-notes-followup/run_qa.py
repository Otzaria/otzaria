#!/usr/bin/env python3
"""Independent personal-note QA on one clean, exact product commit.

The bundle and output directory must remain outside the product checkout.
Only the RED phase temporarily replaces one product file, restoring its exact
bytes in finally. No package overrides, native-cache symlinks or SDK edits.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import traceback

BUNDLE = Path(__file__).resolve().parent
CONFIG = json.loads((BUNDLE / 'config.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', required=True, type=Path)
parser.add_argument('--product-sha', required=True)
parser.add_argument('--base-sha', default=CONFIG['base_sha'])
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--phase', choices=['gate', 'red', 'captures', 'summarize'], required=True)
ARGS = parser.parse_args()
REPO = ARGS.repo.resolve()
OUT = ARGS.out.resolve()
OUT.mkdir(parents=True, exist_ok=True)
ENV = os.environ.copy()
ENV.update(CONFIG['environment'])
STAGES = []


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def git(*args):
    return subprocess.check_output(['git', '-c', 'core.quotepath=false', *args], cwd=REPO, text=True).strip()


def file_record(name):
    path = REPO / name
    data = path.read_bytes() if path.is_file() else None
    return {'path': name, 'exists': data is not None, 'bytes': len(data) if data is not None else None, 'sha256': sha(data) if data is not None else None}


def assert_product():
    if not re.fullmatch('[0-9a-f]{40}', ARGS.product_sha):
        raise ValueError('PRODUCT_SHA must be an exact lowercase 40-character commit SHA')
    if not re.fullmatch('[0-9a-f]{40}', ARGS.base_sha):
        raise ValueError('BASE_SHA must be an exact lowercase 40-character commit SHA')
    if git('rev-parse', 'HEAD') != ARGS.product_sha:
        raise RuntimeError('Checkout HEAD does not equal PRODUCT_SHA')
    if OUT.is_relative_to(REPO) or BUNDLE.is_relative_to(REPO):
        raise ValueError('QA bundle and output must be copied outside the product checkout')
    dirty = git('status', '--porcelain', '--untracked-files=all')
    if dirty:
        raise RuntimeError('Product checkout is not clean:\n' + dirty)


def run(label, command, extra_env=None):
    stage = {'name': label, 'command': command, 'started_utc': now()}
    log_path = OUT / f'{label}.log'
    env = dict(ENV)
    if extra_env:
        env.update(extra_env)
    print(f'QA_STAGE={label}', flush=True)
    with log_path.open('w') as log:
        process = subprocess.Popen(command, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
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
    stage.update({'exit_code': code, 'completed_utc': now(), 'log': str(log_path.relative_to(OUT)), 'log_sha256': sha(log_path.read_bytes())})
    STAGES.append(stage)
    save(OUT / f'{label}.json', stage)
    return code


def selected_tests():
    result = set()
    for suite in CONFIG['suite_selection']:
        path = REPO / suite['path']
        if not path.exists():
            raise FileNotFoundError(path)
        if path.is_dir():
            result.update(str(p.relative_to(REPO)) for p in path.rglob('*_test.dart'))
        else:
            result.add(suite['path'])
    return sorted(result)


def source_names():
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=REPO, text=True).split('\0')
    prefixes = ('lib/', 'test/', 'packages/', 'hook/', 'windows/runner/')
    return sorted(name for name in tracked if name.startswith(prefixes) and name.endswith(('.dart', '.cpp', '.h')))


def make_snapshot():
    changed = git('diff', '--name-only', ARGS.base_sha, ARGS.product_sha).splitlines()
    selected = selected_tests()
    sources = source_names()
    support = [name for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.dart_tool/package_config.json'] if (REPO / name).exists()]
    data = {
        'created_utc': now(), 'product_sha': ARGS.product_sha, 'product_tree': git('rev-parse', 'HEAD^{tree}'), 'base_sha': ARGS.base_sha,
        'suite_selection': CONFIG['suite_selection'],
        'changed_files': [file_record(name) for name in changed],
        'selected_test_files': [file_record(name) for name in selected],
        'source_and_test_files': [file_record(name) for name in sources],
        'configuration': [file_record(name) for name in support],
        'counts': {'changed_files': len(changed), 'selected_test_files': len(selected), 'source_and_test_files': len(sources)},
        'environment': CONFIG['environment'], 'quill_scope': CONFIG['quill_scope'],
        'expected_platform_skip': CONFIG['expected_platform_skip'],
        'bundle_sha256': sha((BUNDLE / 'BUNDLE_SHA256SUMS').read_bytes()) if (BUNDLE / 'BUNDLE_SHA256SUMS').exists() else None,
    }
    save(OUT / 'snapshot.json', data)
    print('QA_SNAPSHOT=' + json.dumps(data['counts']), flush=True)
    return data


def verify_snapshot(snapshot):
    failures = []
    records = {}
    for key in ['changed_files', 'selected_test_files', 'source_and_test_files', 'configuration']:
        for record in snapshot[key]:
            records[record['path']] = record['sha256']
    for name, expected in records.items():
        if file_record(name)['sha256'] != expected:
            failures.append(name)
    if source_names() != [r['path'] for r in snapshot['source_and_test_files']]:
        failures.append('<source/test file set>')
    if selected_tests() != [r['path'] for r in snapshot['selected_test_files']]:
        failures.append('<selected test file set>')
    assert_product()
    if failures:
        raise RuntimeError('Source or test snapshot changed: ' + ', '.join(failures))
    return True


def read_events(path):
    if not path.exists():
        raise RuntimeError(f'Machine-readable test report is missing: {path.name}')
    result = []
    for line in path.read_text().splitlines():
        if line.strip():
            result.append(json.loads(line))
    return result


def summarize_events(events):
    names = {e['test']['id']: e['test']['name'] for e in events if e.get('type') == 'testStart'}
    completed = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden', False)]
    tests = [e for e in completed if not names.get(e.get('testID'), '').endswith(('(setUpAll)', '(tearDownAll)')) and not names.get(e.get('testID'), '').startswith('loading ')]
    counts = {'passed': 0, 'failed': 0, 'skipped': 0}
    skipped = []
    for event in tests:
        if event.get('skipped', False):
            counts['skipped'] += 1
            skipped.append(names.get(event.get('testID')))
        elif event.get('result') == 'success':
            counts['passed'] += 1
        else:
            counts['failed'] += 1
    return {'counts': counts, 'skipped_tests': skipped}


def gate():
    assert_product()
    if run('dependencies', ['flutter', 'pub', 'get', '--enforce-lockfile']) != 0:
        raise RuntimeError('Dependency resolution failed with the enforced lockfile')
    assert_product()
    if run('flutter-version', ['flutter', '--version', '--machine']) != 0:
        raise RuntimeError('Flutter version metadata could not be recorded')
    actual_flutter = json.loads((OUT / 'flutter-version.log').read_text())
    if actual_flutter.get('frameworkVersion') != CONFIG['flutter_version']:
        raise RuntimeError('Unexpected Flutter version: ' + str(actual_flutter.get('frameworkVersion')))
    run('dart-version', ['dart', '--version'])
    for tool, flag in [('rustc', '-Vv'), ('clang', '--version')]:
        if shutil.which(tool):
            run(f'{tool}-version', [tool, flag])
    snapshot = make_snapshot()
    dart_paths = [record['path'] for record in snapshot['changed_files'] if record['exists'] and record['path'].endswith('.dart')]
    results = []
    if dart_paths:
        results.append(run('format', ['dart', 'format', '--output=none', '--set-exit-if-changed', *dart_paths]))
    results.append(run('analyze', ['flutter', 'analyze', '--no-pub', '--fatal-infos']))
    events_path = OUT / 'gate-tests.events.jsonl'
    command = ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded', '--file-reporter', f'json:{events_path}', *[item['path'] for item in CONFIG['suite_selection']]]
    results.append(run('gate-tests', command))
    events = read_events(events_path)
    details = summarize_events(events)
    details['snapshot_unchanged'] = verify_snapshot(snapshot)
    details['format_analyze_tests_exit_codes'] = results
    return all(code == 0 for code in results), details


def verify_red_events(events, spec, exit_code):
    names = {e['test']['id']: e['test']['name'] for e in events if e.get('type') == 'testStart'}
    failures = [e for e in events if e.get('type') == 'testDone' and e.get('result') in ('failure', 'error')]
    errors = [e for e in events if e.get('type') == 'error']
    done = [e for e in events if e.get('type') == 'done']
    verified = []
    expected_ids = set()
    normalize = lambda text: re.sub(r'\s+', ' ', text).strip()
    for expected in spec['expected_failures']:
        matches = [e for e in failures if names.get(e.get('testID'), '').endswith(expected['name'])]
        valid = False
        if len(matches) == 1 and not matches[0].get('skipped', False):
            test_id = matches[0]['testID']
            expected_ids.add(test_id)
            diagnostics = normalize('\n'.join(str(e.get('message', '')) for e in events if e.get('type') == 'print' and e.get('testID') == test_id))
            exceptions = re.findall(r'The following (\w+) was thrown', diagnostics)
            # Flutter prints the TestFailure details, then registers a STRING
            # wrapper, so JSON error.isFailure is false for widget assertions.
            test_errors = [e for e in errors if e.get('testID') == test_id]
            wrapper = 'Test failed. See exception logs above.\nThe test description was: ' + expected['name']
            wrapper_matches = len(test_errors) == 1 and str(test_errors[0].get('error', '')).strip() == wrapper
            valid = (
                exceptions == ['TestFailure']
                and 'Expected:' in diagnostics
                and normalize(expected['error_contains']) in diagnostics
                and 'multiple exceptions' not in diagnostics.lower()
                and wrapper_matches
            )
        verified.append({'test': expected['name'], 'expected_assertion_confirmed': valid})
    no_extra_errors = len(errors) == len(spec['expected_failures']) and all(e.get('testID') in expected_ids for e in errors)
    unsuccessful_done = len(done) == 1 and done[0].get('success') is False
    success = exit_code != 0 and len(failures) == 2 and all(item['expected_assertion_confirmed'] for item in verified) and no_extra_errors and unsuccessful_done
    return success, {
        'expected_red_exit_code': exit_code,
        'exactly_two_failed_assertions': len(failures) == 2,
        'verified_tests': verified,
        'no_loading_or_runtime_errors': no_extra_errors and all(item['expected_assertion_confirmed'] for item in verified),
        'machine_report_confirms_failed_run': unsuccessful_done,
    }


def red():
    assert_product()
    gate_result = json.loads((OUT / 'gate-result.json').read_text())
    if gate_result['status'] != 'PASS':
        raise RuntimeError('A passing product gate is required before the RED demonstration')
    snapshot = json.loads((OUT / 'snapshot.json').read_text())
    verify_snapshot(snapshot)
    spec = CONFIG['red']
    target = REPO / spec['product_component']
    baseline = (BUNDLE / spec['baseline_component']).read_bytes()
    if sha(baseline) != spec['baseline_sha256']:
        raise RuntimeError('The frozen RED baseline checksum does not match')
    original = target.read_bytes()
    original_sha = sha(original)
    events_path = OUT / 'red-tests.events.jsonl'
    restored = False
    try:
        target.write_bytes(baseline)
        code = run('red-tests', ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded', '--file-reporter', f'json:{events_path}', spec['test_file']])
    finally:
        target.write_bytes(original)
        restored = sha(target.read_bytes()) == original_sha
        if not restored:
            raise RuntimeError('Product component restoration failed')
        verify_snapshot(snapshot)
    events = read_events(events_path)
    success, details = verify_red_events(events, spec, code)
    details.update({'restored_component_sha256': original_sha, 'snapshot_unchanged_after_restore': True})
    return success and restored, details


def captures():
    assert_product()
    snapshot = json.loads((OUT / 'snapshot.json').read_text())
    verify_snapshot(snapshot)
    source_dir = OUT / 'capture_sources'
    source_dir.mkdir(exist_ok=True)
    baseline = BUNDLE / CONFIG['red']['baseline_component']
    if sha(baseline.read_bytes()) != CONFIG['red']['baseline_sha256']:
        raise RuntimeError('Capture baseline checksum mismatch')
    replacements = {'__REPO_URI__': REPO.as_uri(), '__BASELINE_URI__': baseline.as_uri()}
    for template in (BUNDLE / 'capture_templates').glob('*.dart'):
        text = template.read_text()
        for placeholder, value in replacements.items():
            text = text.replace(placeholder, value)
        (source_dir / template.name).write_text(text)
    # This config explicitly imports the product's testExecutable. Captures live
    # outside test/, so relying on upward discovery would omit native init/profile isolation.
    if not (source_dir / 'flutter_test_config.dart').is_file():
        raise RuntimeError('External capture bootstrap is missing')
    flutter = shutil.which('flutter')
    if flutter is None:
        raise RuntimeError('Flutter is not on PATH')
    flutter_root = Path(ENV.get('FLUTTER_ROOT', str(Path(flutter).resolve().parent.parent)))
    image_dir = OUT / 'images'
    image_dir.mkdir(exist_ok=True)
    extra_env = {'QA_CAPTURE_OUTPUT': str(image_dir), 'QA_FLUTTER_ROOT': str(flutter_root)}
    format_code = run('capture-format', ['dart', 'format', str(source_dir)])
    events_path = OUT / 'capture-tests.events.jsonl'
    code = run('capture-tests', ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded', '--file-reporter', f'json:{events_path}', '--name', 'QA capture', *[str(source_dir / name) for name in CONFIG['capture_files']]], extra_env)
    images = []
    for name in CONFIG['expected_pngs']:
        path = image_dir / name
        if not path.exists():
            images.append({'path': f'images/{name}', 'exists': False})
            continue
        data = path.read_bytes()
        valid = len(data) >= 24 and data[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', data[16:24]) if valid else (0, 0)
        images.append({'path': f'images/{name}', 'exists': True, 'valid_png': valid, 'width': width, 'height': height, 'bytes': len(data), 'sha256': sha(data)})
    verify_snapshot(snapshot)
    valid_images = all(item.get('valid_png') and item.get('width', 0) > 0 and item.get('height', 0) > 0 for item in images)
    details = {'images': images, 'snapshot_unchanged': True, 'test_results': summarize_events(read_events(events_path)), 'note': 'Actual production widgets and themes rendered with neutral fixture data. A bundled Rubik Hebrew fallback is explicitly loaded for the headless engine. Before/after export captures use identical data and theme.'}
    save(OUT / 'images.json', details)
    return code == 0 and format_code == 0 and valid_images, details


def summarize():
    phases = {}
    for phase in ['gate', 'red', 'captures']:
        path = OUT / f'{phase}-result.json'
        phases[phase] = json.loads(path.read_text()) if path.exists() else {'status': 'NOT_RUN'}
    report = {'product_sha': ARGS.product_sha, 'base_sha': ARGS.base_sha, 'generated_utc': now(), 'status': 'PASS' if all(p.get('status') == 'PASS' for p in phases.values()) else 'FAIL', 'phases': phases, 'quill_scope': CONFIG['quill_scope']}
    save(OUT / 'qa-report.json', report)
    lines = [f'{sha(p.read_bytes())}  {p.relative_to(OUT)}' for p in sorted(OUT.rglob('*')) if p.is_file() and p.name != 'SHA256SUMS']
    (OUT / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')
    print(json.dumps({'report': str(OUT / 'qa-report.json'), 'status': report['status']}, ensure_ascii=False), flush=True)
    return report['status'] == 'PASS'


if ARGS.phase == 'summarize':
    sys.exit(0 if summarize() else 1)
result = {'phase': ARGS.phase, 'product_sha': ARGS.product_sha, 'base_sha': ARGS.base_sha, 'started_utc': now(), 'status': 'FAIL'}
try:
    ok, details = {'gate': gate, 'red': red, 'captures': captures}[ARGS.phase]()
    result.update(details)
    result['status'] = 'PASS' if ok else 'FAIL'
except Exception as error:
    result.update({'error': str(error), 'traceback': traceback.format_exc()})
    print(result['traceback'], file=sys.stderr, flush=True)
finally:
    result.update({'completed_utc': now(), 'stages': STAGES})
    save(OUT / f'{ARGS.phase}-result.json', result)
print('QA_RESULT=' + json.dumps(result, ensure_ascii=False), flush=True)
sys.exit(0 if result['status'] == 'PASS' else 1)
