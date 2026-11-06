#!/usr/bin/env python3
"""Verify the exact final candidate with full suites and combined RED/GREEN proof."""
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
    if not data or any(not isinstance(row, dict) or not isinstance(row.get('type'), str) for row in data):
        raise RuntimeError('Malformed test event stream: ' + str(path))
    done = [row for row in data if row['type'] == 'done']
    if len(done) != 1 or data[-1] is not done[0]:
        raise RuntimeError('Test stream must have exactly one final done event')
    tests = {}
    results = {}
    for row in data:
        if row['type'] == 'testStart':
            test = row.get('test')
            if not isinstance(test, dict) or type(test.get('id')) is not int or not isinstance(test.get('name'), str) or test['id'] in tests:
                raise RuntimeError('Malformed or duplicate testStart')
            tests[test['id']] = test['name']
        elif row['type'] == 'testDone':
            test_id = row.get('testID')
            if test_id not in tests or test_id in results or type(row.get('skipped')) is not bool or type(row.get('hidden')) is not bool or row.get('result') not in ('success', 'failure', 'error'):
                raise RuntimeError('Malformed, unknown or duplicate testDone')
            results[test_id] = row
    if not tests or set(tests) != set(results):
        raise RuntimeError('Test stream has no tests or unfinished tests')
    visible = {test_id: row for test_id, row in results.items() if not row['hidden']}
    passed_names = sorted(tests[test_id] for test_id, row in visible.items() if row['result'] == 'success' and not row['skipped'])
    return {
        'passed': len(passed_names),
        'passed_names': passed_names,
        'skipped': sum(row['skipped'] for row in results.values()),
        'failed': [tests[test_id] for test_id, row in results.items() if row['result'] != 'success'],
        'errors': sum(row['type'] == 'error' for row in data),
        'completed': True,
        'success': done[0].get('success') is True,
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


def verify_alt_failure_signature(data, proof, name):
    """Require the known Quill boundary error, not an unrelated queued exception."""
    test_id = proof['accepted_assertions'][name]['test_id']
    messages = [(position, row['message']) for position, row in enumerate(data)
                if row.get('type') == 'print' and row.get('testID') == test_id
                and row.get('messageType') == 'print']
    diagnostics = [(position, message) for position, message in messages
                   if 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' in message]
    if len(diagnostics) != 1:
        raise RuntimeError('Alt RED needs exactly one classified Flutter assertion')
    diagnostic_position, diagnostic = diagnostics[0]
    actual = '  Actual: StateError:<Bad state: No element>'
    if [line for line in diagnostic.splitlines() if line.startswith('Expected: ')] != ['Expected: null'] or [line for line in diagnostic.splitlines() if line.startswith('  Actual: ')] != [actual]:
        raise RuntimeError('Alt RED did not capture the expected StateError: No element')
    preceding = '\n'.join(message for position, message in messages if position < diagnostic_position)
    label = 'List keyboard error: Bad state: No element'
    if preceding.splitlines().count(label) != 1:
        raise RuntimeError('Alt RED must include its one original keyboard error diagnostic')
    frame = re.search(
        r'(?m)^#\d+[ \t]+RenderEditableTextLine\.getLineBoundary[ \t]+'
        r'\(package:flutter_quill/src/editor/widgets/text/text_line\.dart:\d+:\d+\)$',
        preceding,
    )
    if frame is None or preceding.index(label) > frame.start():
        raise RuntimeError('Alt RED must trace the original error to Quill getLineBoundary')
    return {'test_id': test_id, 'actual': actual.strip(), 'origin_frame': frame.group(0)}


red_assertion_specs = {'reposition refuses an already deleted note instead of reporting success': {'fixture': 'mutation_ack_red_test.dart',
                                                                             'path': 'test/personal_notes/qa_mutation_ack_red_test.dart',
                                                                             'anchor': 'await expectLater(',
                                                                             'marker': 'NotesMessages.noteNoLongerExists,',
                                                                             'kind': 'matcher'},
 'reposition refuses an id belonging to a different book': {'fixture': 'mutation_ack_red_test.dart',
                                                            'path': 'test/personal_notes/qa_mutation_ack_red_test.dart',
                                                            'anchor': 'await expectLater(',
                                                            'marker': 'NotesMessages.noteMovedToDifferentBook,',
                                                            'kind': 'matcher'},
 'manager acknowledges delete without a post-write list read': {'fixture': 'manager_confirmation_red_test.dart',
                                                                'path': 'test/personal_notes/qa_manager_confirmation_red_test.dart',
                                                                'anchor': 'expect(find.text(success), '
                                                                          'findsOneWidget);',
                                                                'previous': 'expect(database.writes, 1);',
                                                                'kind': 'widget'},
 'manager acknowledges reposition without a post-write list read': {'fixture': 'manager_confirmation_red_test.dart',
                                                                    'path': 'test/personal_notes/qa_manager_confirmation_red_test.dart',
                                                                    'anchor': 'expect(find.text(success), '
                                                                              'findsOneWidget);',
                                                                    'previous': 'expect(database.writes, 1);',
                                                                    'kind': 'widget'},
 'sidebar does not announce a failed reposition as successful': {'fixture': 'sidebar_confirmation_red_test.dart',
                                                                 'path': 'test/personal_notes/widgets/qa_sidebar_confirmation_red_test.dart',
                                                                 'anchor': 'expect(announcedBeforeWrite, '
                                                                           'isFalse);',
                                                                 'kind': 'widget'},
 'Backspace אחרי Enter יוצא מרשימת bullet ב-inline': {'fixture': 'list_backspace_red_test.dart',
                                                      'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                                      'anchor': 'expect(controller.document.toDelta().toJson(), [',
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
                                                      'anchor': 'expect(controller.document.toDelta().toJson(), [',
                                                      'previous': 'await _press(tester, '
                                                                  'LogicalKeyboardKey.backspace);',
                                                      'kind': 'widget'},
 'Backspace אחרי Enter יוצא מרשימת ordered ב-dialog': {'fixture': 'list_backspace_red_test.dart',
                                                       'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                                       'anchor': 'expect(controller.document.toDelta().toJson(), '
                                                                 '[',
                                                       'previous': 'await _press(tester, '
                                                                   'LogicalKeyboardKey.backspace);',
                                                       'kind': 'widget'},
 'Alt Left+Backspace אינו הופך פריט לפסקה': {'fixture': 'list_backspace_red_test.dart',
                                             'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                             'anchor': 'expect(tester.takeException(), isNull);',
                                             'kind': 'widget'},
 'Alt+Backspace בפריט הראשון עדיין מסיר רשימה': {'fixture': 'list_backspace_red_test.dart',
                                                 'path': 'test/personal_notes/widgets/qa_list_backspace_red_test.dart',
                                                 'anchor': 'expect(tester.takeException(), isNull);',
                                                 'kind': 'widget'},
 'save completed after panel removal does not reopen a duplicate': {'fixture': 'draft_navigation_red_test.dart',
                                                                    'path': 'test/personal_notes/widgets/qa_draft_navigation_red_test.dart',
                                                                    'anchor': 'expect(',
                                                                    'marker': 'reason: '
                                                                              "'qa-red:draft-saved-no-duplicate',",
                                                                    'kind': 'widget'},
 'late save keeps a newer draft at the same location': {'fixture': 'draft_navigation_red_test.dart',
                                                        'path': 'test/personal_notes/widgets/qa_draft_navigation_red_test.dart',
                                                        'anchor': 'expect(',
                                                        'marker': 'reason: '
                                                                  "'qa-red:draft-newer-same-key-retained',",
                                                        'kind': 'widget'},
 'restoring the panel while save is pending does not revive the draft': {'fixture': 'draft_navigation_red_test.dart',
                                                                         'path': 'test/personal_notes/widgets/qa_draft_navigation_red_test.dart',
                                                                         'anchor': 'expect(',
                                                                         'marker': 'reason: '
                                                                                   "'qa-red:draft-restored-save-completes',",
                                                                         'kind': 'widget'},
 'queued creation survives completion of the preceding save': {'fixture': 'draft_navigation_red_test.dart',
                                                               'path': 'test/personal_notes/widgets/qa_draft_navigation_red_test.dart',
                                                               'anchor': 'expect(',
                                                               'marker': 'reason: '
                                                                         "'qa-red:draft-queued-creation-retained',",
                                                               'kind': 'widget'}}

red_fixtures = {
    repo / spec['path']: bundle / spec['fixture']
    for spec in red_assertion_specs.values()
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
    if manifest.get('product_inventory_frozen') is not True:
        raise RuntimeError('The final reviewed product inventory has not been frozen')
    names = manifest['red_test_names']
    expected_red = set(names)
    if len(names) != len(expected_red) or expected_red != set(red_assertion_specs):
        raise RuntimeError('RED manifest must name each intended regression exactly once')
    targets = manifest['test_targets']
    if len(targets) != 5 or set(targets) != {
        'test/personal_notes',
        'test/pdf_book/pdf_personal_note_viewer_test.dart',
        'test/pdf_book/pdf_personal_note_anchor_test.dart',
        'test/pdf_book/pdf_hand_mode_test.dart',
        'test/pdf_book/pdf_book_screen_test.dart',
    }:
        raise RuntimeError('Full test manifest must contain all personal-note tests and four PDF suites')
    required_controls = {
        'tab navigation without Save keeps one live draft',
        'adaptive pane hide and show without Save keeps one live draft',
        'restored editor preserves new typing before its debounce',
    }
    inventory = manifest['changed_files']
    if not inventory or len(inventory) != len(set(inventory)) or set(manifest['source_sha256']) != set(inventory):
        raise RuntimeError('Every changed product file must have a frozen source hash')
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
    if sorted(changed) != sorted(inventory):
        raise RuntimeError('Unexpected product file inventory: ' + repr(changed))
    report['source_hashes'] = {}
    for name, expected in manifest['source_sha256'].items():
        actual = hashlib.sha256((repo / name).read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError('Source hash mismatch: ' + name)
        report['source_hashes'][name] = actual
    fixture_hashes = {
        source.name: hashlib.sha256(source.read_bytes()).hexdigest()
        for source in red_fixtures.values()
    }
    if fixture_hashes != manifest['red_fixture_hashes']:
        raise RuntimeError('RED fixture inventory or source hash differs from the frozen manifest')
    report['red_fixture_hashes'] = fixture_hashes
    fixture_source = 'test/personal_notes/widgets/personal_note_list_backspace_test.dart'
    fixture_hash = fixture_hashes['list_backspace_red_test.dart']
    if manifest['red_fixture_source'] != fixture_source or fixture_hash != manifest['red_fixture_sha256'] or fixture_hash != report['source_hashes'][fixture_source]:
        raise RuntimeError('List RED fixture must match the product regression test byte for byte')
    report['red_fixture_sha256'] = fixture_hash
    draft_source = 'test/personal_notes/widgets/personal_notes_draft_navigation_test.dart'
    if manifest['draft_fixture_source'] != draft_source or manifest['draft_fixture_source_sha256'] != report['source_hashes'][draft_source] or manifest['draft_fixture_sha256'] != fixture_hashes['draft_navigation_red_test.dart']:
        raise RuntimeError('Draft RED fixture must derive from the frozen reviewed product test')

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
        *targets,
    ])
    if not test_report.exists():
        raise RuntimeError('Full suite run produced no test report')
    report['focused_tests'] = summarize(test_report)
    if report['focused_tests']['skipped']:
        raise RuntimeError('Full personal-note and PDF suites must not skip tests')

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
    red_events = events(red_report)
    report['red_proof'] = classify_red(red_events, red_locations, red_code)
    report['red_proof']['alt_boundary_failures'] = {
        name: verify_alt_failure_signature(red_events, report['red_proof'], name)
        for name in (
            'Alt Left+Backspace אינו הופך פריט לפסקה',
            'Alt+Backspace בפריט הראשון עדיין מסיר רשימה',
        )
    }

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
    if not green.get('success') or not green.get('completed') or green.get('passed') != len(expected_red) or set(green.get('passed_names', [])) != expected_red or green.get('skipped') or green.get('failed') or green.get('errors'):
        raise RuntimeError('Exactly the selected regression assertions must pass on the product commit without skips or errors')
    remove_red_fixtures()
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('Product checkout changed during verification')
    focused = report['focused_tests']
    if not focused['success'] or not focused['passed'] or not (expected_red | required_controls).issubset(focused['passed_names']) or focused['failed'] or focused['errors']:
        raise RuntimeError('Full suites must pass and include every regression and required draft control')
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
