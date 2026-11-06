#!/usr/bin/env python3
"""Verify the exact editor candidate and prove four list regressions on its base."""
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
        'passed_names': sorted(tests.get(row['testID'], {}).get('name', str(row['testID'])) for row in results if row['result'] == 'success' and not row.get('skipped', False)),
        'skipped': sum(row.get('skipped', False) for row in results),
        'failed': [tests.get(row['testID'], {}).get('name', str(row['testID'])) for row in results if row['result'] != 'success'],
        'completed': any(row['type'] == 'done' for row in data),
    }


def resolve_red_assertions(fixture_root, specs):
    locations = {}
    for name, spec in specs.items():
        data = (fixture_root / spec['fixture']).read_bytes()
        lines = data.decode('utf-8').splitlines()
        candidates = [i for i, line in enumerate(lines) if line.strip() == spec['anchor']]
        if 'marker' in spec:
            markers = [i for i, line in enumerate(lines) if line.strip() == spec['marker']]
            if len(markers) != 1:
                raise RuntimeError('Expected one regression marker: ' + name)
            candidates = [i for i in candidates if i < markers[0]]
            candidates = candidates[-1:]
        if 'previous' in spec:
            candidates = [i for i in candidates if next((line.strip() for line in reversed(lines[:i]) if line.strip()), None) == spec['previous']]
        if len(candidates) != 1:
            raise RuntimeError('Intended regression assertion is not unique: ' + name)
        locations[name] = {
            'path': spec['path'],
            'line': candidates[0] + 1,
            'anchor': spec['anchor'],
            'kind': spec['kind'],
            'fixture_sha256': hashlib.sha256(data).hexdigest(),
        }
    return locations


def classify_red(data, locations, exit_code):
    """Accept only the intended assertions, including Flutter's widget wrapper."""
    if exit_code != 1:
        raise RuntimeError('RED must exit with the test-failure status 1')
    if not isinstance(data, list) or not data or any(not isinstance(row, dict) or not isinstance(row.get('type'), str) for row in data):
        raise RuntimeError('Malformed RED event stream')
    done = [row for row in data if row['type'] == 'done']
    if len(done) != 1 or data[-1] is not done[0] or done[0].get('success') is not False:
        raise RuntimeError('RED must have one final unsuccessful done event')
    if not locations:
        raise RuntimeError('RED needs explicit intended regression assertions')

    tests = {}
    starts = {}
    results = {}
    result_positions = {}
    for position, row in enumerate(data):
        if row['type'] == 'testStart':
            test = row.get('test')
            if not isinstance(test, dict) or type(test.get('id')) is not int or not isinstance(test.get('name'), str) or test['id'] in tests:
                raise RuntimeError('Malformed or duplicate RED testStart')
            tests[test['id']] = test['name']
            starts[test['id']] = position
        elif row['type'] == 'testDone':
            test_id = row.get('testID')
            if test_id not in tests or test_id in results:
                raise RuntimeError('Unknown or duplicate RED testDone')
            results[test_id] = row
            result_positions[test_id] = position
    if set(results) != set(tests):
        raise RuntimeError('RED contains tests without completed results')

    selected = {test_id: name for test_id, name in tests.items() if name in locations}
    if len(selected) != len(locations) or set(selected.values()) != set(locations):
        raise RuntimeError('RED must execute each expected test name exactly once')
    visible = {test_id for test_id, row in results.items() if not row.get('hidden', False)}
    if visible != set(selected):
        raise RuntimeError('RED visible test inventory differs from the expected regressions')
    for test_id, row in results.items():
        if row.get('skipped') is not False:
            raise RuntimeError('RED must not skip any tests')
        if test_id in selected:
            if row.get('hidden') is not False or row.get('result') not in ('failure', 'error'):
                raise RuntimeError('Every intended RED assertion must fail visibly')
        elif row.get('hidden') is not True or row.get('result') != 'success':
            raise RuntimeError('RED loading or lifecycle test failed')

    errors = {test_id: [] for test_id in selected}
    diagnostics = {test_id: [] for test_id in selected}
    for position, row in enumerate(data):
        if row['type'] == 'error':
            test_id = row.get('testID')
            if test_id not in selected:
                raise RuntimeError('RED has an error outside the expected assertions')
            errors[test_id].append((position, row))
        elif row['type'] == 'print':
            message = row.get('message')
            if not isinstance(message, str):
                raise RuntimeError('Malformed RED print event')
            if 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' in message:
                test_id = row.get('testID')
                if test_id not in selected:
                    raise RuntimeError('Unexpected Flutter exception outside a regression test')
                diagnostics[test_id].append((position, row))

    accepted = {}
    for test_id, name in selected.items():
        location = locations[name]
        if len(errors[test_id]) != 1:
            raise RuntimeError('Expected exactly one assertion error for: ' + name)
        error_position, error = errors[test_id][0]
        if not starts[test_id] < error_position < result_positions[test_id]:
            raise RuntimeError('RED assertion events are out of order: ' + name)
        path = re.escape(location['path'])
        line = location['line']
        if location['kind'] == 'matcher':
            if error.get('isFailure') is not True or diagnostics[test_id] or results[test_id]['result'] != 'failure':
                raise RuntimeError('Expected a direct matcher assertion for: ' + name)
            message = error.get('error', '')
            stack = error.get('stackTrace', '')
            if not isinstance(message, str) or not message.startswith('Expected: ') or '\n  Actual: ' not in message or not isinstance(stack, str):
                raise RuntimeError('RED error is not a matcher expectation: ' + name)
            if re.search(r'TimeoutException|TestTimeoutException|Compilation failed|Failed to load', message):
                raise RuntimeError('RED matcher encountered a timeout or infrastructure error: ' + name)
            if not re.search(rf'(?m)^{path} {line}:\d+\s', stack):
                raise RuntimeError('Matcher failed outside the intended regression assertion: ' + name)
        elif location['kind'] == 'widget':
            wrapper = 'Test failed. See exception logs above.\nThe test description was: ' + name
            if error.get('isFailure') is not False or error.get('error') != wrapper or error.get('stackTrace') != '' or results[test_id]['result'] != 'error':
                raise RuntimeError('Expected the exact Flutter widget failure wrapper: ' + name)
            if len(diagnostics[test_id]) != 1:
                raise RuntimeError('Expected one Flutter TestFailure, without additional exceptions: ' + name)
            print_position, diagnostic = diagnostics[test_id][0]
            if not starts[test_id] < print_position < error_position or diagnostic.get('messageType') != 'print':
                raise RuntimeError('Flutter TestFailure must precede its wrapper in the same test: ' + name)
            message = diagnostic['message']
            lines = message.splitlines()
            if len(lines) < 3 or not re.fullmatch(r'══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═+', lines[0]) or lines[1] != 'The following TestFailure was thrown running a test:':
                raise RuntimeError('Flutter failure is not a TestFailure assertion: ' + name)
            if not re.search(r'(?m)^Expected: ', message) or not re.search(r'(?m)^  Actual: ', message):
                raise RuntimeError('Flutter diagnostic has no matcher expectation: ' + name)
            stack_location = rf'(?m)^#\d+\s+[^\n]+\(file://[^\n]+/{path}:{line}:\d+\)$'
            assertion_location = rf'(?m)^This was caught by the test expectation on the following line:\n  file://[^\n]+/{path} line {line}$'
            description = '\nThe test description was:\n  ' + name + '\n'
            if not re.search(stack_location, message) or not re.search(assertion_location, message) or description not in message:
                raise RuntimeError('Flutter TestFailure is outside the intended regression assertion: ' + name)
        else:
            raise RuntimeError('Unknown regression assertion kind: ' + name)
        accepted[name] = {'test_id': test_id, **location}
    return {
        'expected_assertion_failures': sorted(locations),
        'accepted_assertions': accepted,
        'passed': 0,
        'skipped': 0,
        'failed': sorted(locations),
        'completed': True,
    }


red_assertion_specs = {'Backspace אחרי Enter יוצא מרשימת bullet ב-inline': {'fixture': 'list_backspace_red_test.dart',
                                                      'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                                      'anchor': 'expect(controller.document.toDelta().toJson(), '
                                                                '[',
                                                      'previous': 'await _press(tester, '
                                                                  'LogicalKeyboardKey.backspace);',
                                                      'kind': 'widget'},
 'Backspace אחרי Enter יוצא מרשימת ordered ב-inline': {'fixture': 'list_backspace_red_test.dart',
                                                       'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                                       'anchor': 'expect(controller.document.toDelta().toJson(), '
                                                                 '[',
                                                       'previous': 'await _press(tester, '
                                                                   'LogicalKeyboardKey.backspace);',
                                                       'kind': 'widget'},
 'Backspace אחרי Enter יוצא מרשימת bullet ב-dialog': {'fixture': 'list_backspace_red_test.dart',
                                                      'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                                      'anchor': 'expect(controller.document.toDelta().toJson(), '
                                                                '[',
                                                      'previous': 'await _press(tester, '
                                                                  'LogicalKeyboardKey.backspace);',
                                                      'kind': 'widget'},
 'Backspace אחרי Enter יוצא מרשימת ordered ב-dialog': {'fixture': 'list_backspace_red_test.dart',
                                                       'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                                       'anchor': 'expect(controller.document.toDelta().toJson(), '
                                                                 '[',
                                                       'previous': 'await _press(tester, '
                                                                   'LogicalKeyboardKey.backspace);',
                                                       'kind': 'widget'}}


red_fixtures = {
    repo / 'test/personal_notes/widgets/qa_list_backspace_red_test.dart': bundle / 'list_backspace_red_test.dart',
}
created_red_fixtures = set()


def copy_red_fixtures():
    for destination, source in red_fixtures.items():
        if destination.exists():
            raise RuntimeError('Temporary RED test would overwrite a repository file')
        shutil.copyfile(source, destination)
        created_red_fixtures.add(destination)


def remove_red_fixtures():
    for destination in tuple(created_red_fixtures):
        if destination.exists():
            destination.unlink()
        created_red_fixtures.remove(destination)


try:
    for sha in [target, base]:
        if not re.fullmatch('[0-9a-f]{40}', sha):
            raise RuntimeError('Expected a frozen commit SHA')
    expected_red = set(manifest['red_test_names'])
    if expected_red != {
        'Backspace אחרי Enter יוצא מרשימת bullet ב-inline',
        'Backspace אחרי Enter יוצא מרשימת ordered ב-inline',
        'Backspace אחרי Enter יוצא מרשימת bullet ב-dialog',
        'Backspace אחרי Enter יוצא מרשימת ordered ב-dialog',
    }:
        raise RuntimeError('RED manifest does not name the four list regression assertions')
    if set(manifest['test_targets']) != {
        'test/personal_notes/widgets/personal_note_list_backspace_test.dart',
        'test/personal_notes/widgets/inline_note_editor_test.dart',
        'test/personal_notes/widgets/personal_note_editor_dialog_keyboard_test.dart',
        'test/personal_notes/widgets/personal_note_editor_lifecycle_test.dart',
        'test/personal_notes/personal_notes_manager_loading_test.dart',
    }:
        raise RuntimeError('Focused test manifest must contain all five editor and manager suites')
    if len(manifest['changed_files']) != 12 or set(manifest['source_sha256']) != set(manifest['changed_files']):
        raise RuntimeError('All twelve changed product files must have source hashes')
    red_selection = '^(?:' + '|'.join(re.escape(name) for name in sorted(expected_red)) + ')$'
    red_locations = resolve_red_assertions(bundle, red_assertion_specs)
    if set(red_locations) != expected_red:
        raise RuntimeError('Intended assertion locations do not match the RED manifest')
    report['intended_red_assertions'] = red_locations
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
    fixture_source = 'test/personal_notes/widgets/personal_note_list_backspace_test.dart'
    fixture_hash = hashlib.sha256((bundle / 'list_backspace_red_test.dart').read_bytes()).hexdigest()
    if manifest['red_fixture_source'] != fixture_source or fixture_hash != manifest['red_fixture_sha256'] or fixture_hash != report['source_hashes'][fixture_source]:
        raise RuntimeError('RED fixture must match the frozen product regression test byte for byte')
    report['red_fixture_sha256'] = fixture_hash

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
    analyze_code = run('analyze', ['flutter', 'analyze', '--no-pub'])
    test_report = out / 'focused-tests.json'
    test_code = run('focused-tests', [
        'flutter', 'test', '--no-pub', '-j', '4', '--file-reporter', 'json:' + str(test_report),
        *manifest['test_targets'],
    ])
    if not test_report.exists():
        raise RuntimeError('Focused run produced no test report')
    report['focused_tests'] = summarize(test_report)
    if not report['focused_tests']['completed']:
        raise RuntimeError('Focused test stream did not complete')
    if report['focused_tests']['skipped']:
        raise RuntimeError('Focused editor tests must not be skipped')

    if any(path.exists() for path in red_fixtures):
        raise RuntimeError('Temporary RED test would overwrite a repository file')
    subprocess.run(['git', 'checkout', '--detach', base], cwd=repo, check=True)
    if git('rev-parse', 'HEAD') != base or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('RED must start on the exact clean reviewed base')
    copy_red_fixtures()
    red_report = out / 'red-tests.json'
    red_code = run('red-tests', [
        'flutter', 'test', '--no-pub', '--file-reporter', 'json:' + str(red_report),
        '--name', red_selection, *map(str, red_fixtures),
    ])
    if not red_report.exists():
        raise RuntimeError('RED run produced no test report')
    report['red_proof'] = classify_red(events(red_report), red_locations, red_code)

    remove_red_fixtures()
    subprocess.run(['git', 'checkout', '--detach', target], cwd=repo, check=True)
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('GREEN must start on the exact clean product commit')
    copy_red_fixtures()
    green_report = out / 'green-tests.json'
    green_code = run('green-tests', [
        'flutter', 'test', '--no-pub', '--file-reporter', 'json:' + str(green_report),
        '--name', red_selection, *map(str, red_fixtures),
    ])
    if green_report.exists():
        report['green_proof'] = summarize(green_report)
    green = report.get('green_proof', {})
    if not green.get('completed') or green.get('passed') != len(expected_red) or set(green.get('passed_names', [])) != expected_red or green.get('skipped') or green.get('failed'):
        raise RuntimeError('Exactly the four list regression assertions must pass on the product commit without skips')
    remove_red_fixtures()
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('Product checkout changed during verification')
    focused = report['focused_tests']
    if not focused['passed'] or not expected_red.issubset(focused['passed_names']) or focused['failed']:
        raise RuntimeError('Focused editor suites must pass and include all four list regressions')
    if any([format_code, analyze_code, test_code, green_code]):
        raise RuntimeError('One or more product checks failed')
    report['status'] = 'PASS'
except Exception as error:
    report['error'] = str(error)
    print('QA ERROR: ' + str(error), flush=True)
finally:
    remove_red_fixtures()
    tracked_diff = git('diff', 'HEAD', '--binary')
    if tracked_diff:
        (out / 'working-tree-diff.patch').write_text(tracked_diff + '\n')
    subprocess.run(['git', 'checkout', '--detach', target], cwd=repo, check=False)
    (out / 'qa-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    sums = [hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + str(path.relative_to(out)) for path in sorted(out.rglob('*')) if path.is_file() and path.name != 'SHA256SUMS']
    (out / 'SHA256SUMS').write_text('\n'.join(sums) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
sys.exit(0 if report['status'] == 'PASS' else 1)
