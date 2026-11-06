#!/usr/bin/env python3
"""Verify the exact final candidate with full suites and combined RED/GREEN proof."""
import hashlib
import difflib
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
    """Require the specific Quill failure observed for each empty-line scenario."""
    signatures = {
        'Alt Left+Backspace אינו הופך פריט לפסקה': {
            'error': 'StateError:<Bad state: No element>',
            'message': 'Bad state: No element',
            'frames': [
                ('RenderEditableTextLine.getLineBoundary',
                 'flutter_quill/src/editor/widgets/text/text_line.dart'),
            ],
        },
        'Alt+Backspace בפריט הראשון עדיין מסיר רשימה': {
            'error': 'RangeError:<RangeError (start): Invalid value: Not in inclusive range 0..1: 8>',
            'message': 'RangeError (start): Invalid value: Not in inclusive range 0..1: 8',
            'frames': [
                ('EditorKeyboardShortcutsActionsManager._replaceText',
                 'flutter_quill/src/editor/raw_editor/keyboard_shortcuts/editor_keyboard_shortcut_actions_manager.dart'),
                ('QuillEditorDeleteTextAction.invoke.execute',
                 'flutter_quill/src/editor/raw_editor/keyboard_shortcuts/editor_keyboard_shortcut_actions.dart'),
            ],
        },
    }
    signature = signatures[name]
    test_id = proof['accepted_assertions'][name]['test_id']
    messages = [(position, row['message']) for position, row in enumerate(data)
                if row.get('type') == 'print' and row.get('testID') == test_id
                and row.get('messageType') == 'print']
    diagnostics = [(position, message) for position, message in messages
                   if 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' in message]
    if len(diagnostics) != 1:
        raise RuntimeError('Alt RED needs exactly one classified Flutter assertion')
    diagnostic_position, diagnostic = diagnostics[0]
    actual = '  Actual: ' + signature['error']
    if [line for line in diagnostic.splitlines() if line.startswith('Expected: ')] != ['Expected: null'] or [line for line in diagnostic.splitlines() if line.startswith('  Actual: ')] != [actual]:
        raise RuntimeError('Alt RED did not capture the exact expected exception for: ' + name)
    preceding = '\n'.join(message for position, message in messages if position < diagnostic_position)
    label = 'List keyboard error: ' + signature['message']
    if [line for line in preceding.splitlines() if line.startswith('List keyboard error: ')] != [label]:
        raise RuntimeError('Alt RED must include its one original keyboard error diagnostic')
    cursor = preceding.index(label) + len(label)
    origin_frames = []
    for symbol, path in signature['frames']:
        frame = re.search(
            rf'(?m)^#\d+[ \t]+{re.escape(symbol)}[ \t]+'
            rf'\(package:{re.escape(path)}:\d+:\d+\)$',
            preceding[cursor:],
        )
        if frame is None:
            raise RuntimeError('Alt RED must trace the original error through its expected Quill source: ' + name)
        origin_frames.append(frame.group(0))
        cursor += frame.end()
    return {'test_id': test_id, 'actual': actual.strip(), 'origin_frames': origin_frames}


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
base_control_fixtures = {
    repo / 'test/personal_notes/widgets/qa_reader_marker_selection_base_test.dart':
        bundle / 'reader_marker_selection_base_test.dart',
}
created_test_fixtures = set()


def copy_test_fixtures(fixtures):
    for destination, source in fixtures.items():
        if destination.exists():
            raise RuntimeError('Temporary QA test would overwrite a repository file')
        created_test_fixtures.add(destination)
        shutil.copyfile(source, destination)


def remove_test_fixtures():
    for destination in tuple(created_test_fixtures):
        if destination.exists():
            destination.unlink()
        created_test_fixtures.remove(destination)


def require_clean_checkout(commit, context):
    if git('rev-parse', 'HEAD') != commit or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError(context + ' requires the exact clean checkout')


def blob_sha(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()


def verify_reader_failure_signature(data, proof):
    """Recognize only the CI7 source-prefix mismatch at the classified assertion."""
    accepted = {}
    for name, assertion in proof['accepted_assertions'].items():
        test_id = assertion['test_id']
        diagnostics = [row['message'] for row in data
                       if row.get('type') == 'print' and row.get('testID') == test_id
                       and row.get('messageType') == 'print'
                       and 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' in row.get('message', '')]
        if len(diagnostics) != 1:
            raise RuntimeError('Reader known RED needs its one classified Flutter assertion')
        lines = diagnostics[0].splitlines()
        expected = "Expected: a string starting with 'הַבֹּכִ֑ים'"
        actual = "  Actual: 'כִ֑ים {פ} וַיֹּ֩אמֶר֩'"
        if [line for line in lines if line.startswith('Expected: ')] != [expected] or [line for line in lines if line.startswith('  Actual: ')] != [actual]:
            raise RuntimeError('Reader known RED differs from the exact CI7 source-prefix mismatch: ' + name)
        accepted[name] = {'test_id': test_id, 'expected': expected, 'actual': actual}
    return accepted


def run_exact_green(label, names, paths):
    result_path = out / (label + '.json')
    selection = '^(?:' + '|'.join(re.escape(name) for name in sorted(names)) + ')$'
    code = run(label, [
        'flutter', 'test', '--no-pub', '--file-reporter', 'json:' + str(result_path),
        '--name', selection, *map(str, paths),
    ])
    if not result_path.exists():
        raise RuntimeError(label + ' produced no test report')
    result = summarize(result_path)
    if code or not result['success'] or not result['completed'] or result['passed'] != len(names) or set(result['passed_names']) != set(names) or result['skipped'] or result['failed'] or result['errors']:
        raise RuntimeError(label + ' must pass every exact expected name without skips or errors')
    return result


def run_reader_known_red(label, commit):
    require_clean_checkout(commit, label)
    result = {'commit': commit, 'status': 'FAIL', 'meaning': 'Known pre-existing issue 3260; this product does not fix it.'}
    report.setdefault('reader_known_red', {})[label] = result
    try:
        copy_test_fixtures(base_control_fixtures)
        result['shown_marks_pass'] = run_exact_green(
            label + '-reader-pass', expected_reader_pass, base_control_fixtures,
        )
        result_path = out / (label + '-reader-known-red.json')
        selection = '^(?:' + '|'.join(re.escape(name) for name in sorted(expected_reader_red)) + ')$'
        code = run(label + '-reader-known-red', [
            'flutter', 'test', '--no-pub', '--file-reporter', 'json:' + str(result_path),
            '--name', selection, *map(str, base_control_fixtures),
        ])
        if not result_path.exists():
            raise RuntimeError(label + ' reader known RED produced no test report')
        data = events(result_path)
        proof = classify_red(data, reader_red_locations, code)
        proof['source_prefix_failures'] = verify_reader_failure_signature(data, proof)
        result['hidden_marks_known_red'] = proof
    finally:
        remove_test_fixtures()
        require_clean_checkout(commit, label + ' cleanup')
        result['clean_checkout_restored'] = True
    result['status'] = 'EXPECTED_KNOWN_RED_PROVED'


overlay_backups = {}


def restore_pr_overlay():
    failures = []
    for name, original in tuple(overlay_backups.items()):
        try:
            (repo / name).write_bytes(original)
            if (repo / name).read_bytes() != original:
                raise RuntimeError('Restored bytes differ')
            del overlay_backups[name]
        except Exception as error:
            failures.append(name + ': ' + str(error))
    if failures:
        raise RuntimeError('PR3036 overlay restoration failed: ' + '; '.join(failures))


def overlay_diff(originals, replacements):
    return ''.join(
        line
        for name in originals
        for line in difflib.unified_diff(
            originals[name].decode('utf-8').splitlines(keepends=True),
            replacements[name].decode('utf-8').splitlines(keepends=True),
            fromfile='a/' + name, tofile='b/' + name,
        )
    )


def validate_overlay_sources():
    originals = {}
    replacements = {}
    for spec in overlay['files']:
        name = spec['path']
        original = (repo / name).read_bytes()
        replacement = (bundle / spec['fixture']).read_bytes()
        if hashlib.sha256(original).hexdigest() != spec['original_sha256'] or blob_sha(original) != spec['original_blob']:
            raise RuntimeError('Original PR3036 overlay path differs from the reviewed base: ' + name)
        if git('rev-parse', base + ':' + name) != spec['original_blob'] or git('rev-parse', target + ':' + name) != spec['original_blob']:
            raise RuntimeError('PR3036 overlay original is not identical on base and candidate: ' + name)
        if hashlib.sha256(replacement).hexdigest() != spec['sha256'] or blob_sha(replacement) != spec['blob'] or len(replacement) != spec['bytes']:
            raise RuntimeError('PR3036 overlay does not match its exact author blob: ' + name)
        originals[name] = original
        replacements[name] = replacement
    patch = overlay_diff(originals, replacements).encode('utf-8')
    if patch != (bundle / overlay['diff_fixture']).read_bytes() or hashlib.sha256(patch).hexdigest() != overlay['diff_sha256']:
        raise RuntimeError('PR3036 overlay diff differs from the reviewed complete-file diff')
    control = overlay['unchanged_plugin_control']
    control_data = (repo / control['path']).read_bytes()
    if hashlib.sha256(control_data).hexdigest() != control['sha256'] or blob_sha(control_data) != control['blob'] or git('rev-parse', base + ':' + control['path']) != control['blob'] or git('rev-parse', target + ':' + control['path']) != control['blob']:
        raise RuntimeError('Unchanged reader-selection plugin suite differs from the reviewed source')
    return originals, replacements, patch


def run_pr3036_overlay():
    require_clean_checkout(target, 'PR3036 overlay start')
    result = {'status': 'FAIL', 'product_commit': target, 'head_sha': overlay['head_sha'], 'meaning': 'QA-only pinned PR3036 experiment; no overlay file belongs to the product diff.'}
    report['pr3036_overlay'] = result
    originals, replacements, patch = validate_overlay_sources()
    # Back up every original before the first write, including partial-copy failures.
    overlay_backups.update(originals)
    try:
        for name, replacement in replacements.items():
            (repo / name).write_bytes(replacement)
            if (repo / name).read_bytes() != replacement:
                raise RuntimeError('PR3036 overlay copy changed bytes: ' + name)
        (out / 'pr3036-overlay.patch').write_bytes(patch)
        result['diff_sha256'] = hashlib.sha256(patch).hexdigest()
        result['source_files'] = overlay['files']
        copy_test_fixtures(base_control_fixtures)
        result['reader_green'] = run_exact_green(
            'pr3036-overlay-reader-green', expected_base_controls, base_control_fixtures,
        )
        result['plugin_green'] = run_exact_green(
            'pr3036-overlay-plugin-green', expected_plugin_names, overlay['plugin_test_targets'],
        )
    finally:
        try:
            remove_test_fixtures()
        finally:
            restore_pr_overlay()
            require_clean_checkout(target, 'PR3036 overlay cleanup')
            result['clean_checkout_restored'] = True
    result['status'] = 'PASS'


try:
    for sha in [target, base]:
        if not re.fullmatch('[0-9a-f]{40}', sha):
            raise RuntimeError('Expected a frozen commit SHA')
    if manifest.get('product_inventory_frozen') is not True:
        raise RuntimeError('The final reviewed product inventory has not been frozen')
    if target != manifest['candidate_sha']:
        raise RuntimeError('TARGET_SHA differs from the reviewed manifest candidate')
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
    base_control = manifest['upstream_control']
    control_names = base_control['test_names']
    expected_base_controls = set(control_names)
    expected_reader_pass = {
        'Judges reader selection crosses paragraph marker (removeMarks=false, HtmlWidget=false)',
        'Judges reader selection crosses paragraph marker (removeMarks=false, HtmlWidget=true)',
    }
    expected_reader_red = {
        'Judges reader selection crosses paragraph marker (removeMarks=true, HtmlWidget=false)',
        'Judges reader selection crosses paragraph marker (removeMarks=true, HtmlWidget=true)',
    }
    if len(control_names) != 4 or expected_base_controls != expected_reader_pass | expected_reader_red:
        raise RuntimeError('Issue 3260 proof must name exactly the four frozen reader cases')
    if len(base_control['expected_pass_names']) != 2 or set(base_control['expected_pass_names']) != expected_reader_pass or len(base_control['expected_known_red_names']) != 2 or set(base_control['expected_known_red_names']) != expected_reader_red:
        raise RuntimeError('Issue 3260 proof must separate the two PASS and two known RED cases')
    absent_reader_source = 'test/personal_notes/widgets/personal_note_reader_marker_selection_test.dart'
    if base_control['issue'] != 3260 or base_control['fixture'] != 'reader_marker_selection_base_test.dart' or base_control['product_source_must_be_absent'] != absent_reader_source or base_control['destination'] != 'test/personal_notes/widgets/qa_reader_marker_selection_base_test.dart':
        raise RuntimeError('Unexpected QA-only reader fixture mapping')
    if base_control['sha256'] != '02a4cc8c7f40b7afb26ae87cb163e5a6ab2581d39cfd7cc16b495e069142dd5c':
        raise RuntimeError('Reader fixture is not the unchanged reviewed CI7 fixture')
    if base_control['red_assertion'] != {
        'anchor': 'expect(repository.sourceText, startsWith(_firstWord));',
        'expected': "Expected: a string starting with 'הַבֹּכִ֑ים'",
        'actual': "  Actual: 'כִ֑ים {פ} וַיֹּ֩אמֶר֩'",
    }:
        raise RuntimeError('Reader known-RED assertion must match the observed CI7 source-prefix failure')
    reader_red_specs = {name: {
        'fixture': base_control['fixture'], 'path': base_control['destination'],
        'anchor': base_control['red_assertion']['anchor'], 'kind': 'widget',
    } for name in expected_reader_red}
    reader_red_locations = resolve_red_assertions(bundle, reader_red_specs)
    report['intended_reader_known_red_assertions'] = reader_red_locations
    overlay = manifest['pr3036_overlay']
    if overlay['repository'] != 'Otzaria/otzaria' or overlay['pull_request'] != 3036 or overlay['author'] != 'mmichaelush' or overlay['head_sha'] != 'b07bb4b8bf3ed7c4d0ac8f34b68d5238bccc94af':
        raise RuntimeError('Overlay must use the exact reviewed PR3036 author revision')
    expected_overlay_blobs = {
        'lib/plugins/services/text_source_map_service.dart': '68b6f7e21edddc037e55c1689b593da2331688bf',
        'test/plugins/services/text_source_map_service_test.dart': '3de394b209c63b5fe63939c6b49acd6332819139',
        'test/plugins/services/text_source_map_engine_test.dart': 'c82549f76a477dc7f9271601115e811779ea4228',
    }
    if len(overlay['files']) != 3 or {spec['path']: spec['blob'] for spec in overlay['files']} != expected_overlay_blobs:
        raise RuntimeError('Overlay must contain exactly the three complete author blobs')
    for spec in overlay['files']:
        if spec['fixture'] != 'pr3036/' + spec['path'] or spec['head'] != overlay['head_sha'] or spec['source_url'] != 'https://github.com/Otzaria/otzaria/blob/' + overlay['head_sha'] + '/' + spec['path']:
            raise RuntimeError('Unexpected PR3036 source provenance')
    if overlay['diff_fixture'] != 'pr3036/overlay.patch' or overlay['provenance_fixture'] != 'pr3036/provenance.json':
        raise RuntimeError('Unexpected PR3036 overlay evidence mapping')
    provenance_bytes = (bundle / overlay['provenance_fixture']).read_bytes()
    provenance = json.loads(provenance_bytes)
    if hashlib.sha256(provenance_bytes).hexdigest() != overlay['provenance_sha256'] or provenance['head'] != overlay['head_sha'] or provenance['base_sha'] != base or provenance['files'] != overlay['files'] or provenance['overlay_diff_sha256'] != overlay['diff_sha256']:
        raise RuntimeError('PR3036 provenance differs from the pinned manifest')
    plugin_targets = overlay['plugin_test_targets']
    if len(plugin_targets) != 3 or set(plugin_targets) != {
        'test/plugins/services/text_source_map_service_test.dart',
        'test/plugins/services/text_source_map_engine_test.dart',
        'test/plugins/services/reader_selection_service_test.dart',
    } or set(overlay['plugin_test_names_by_file']) != set(plugin_targets):
        raise RuntimeError('Overlay must run exactly the three reviewed plugin suites')
    plugin_names = [name for names in overlay['plugin_test_names_by_file'].values() for name in names]
    expected_plugin_names = set(plugin_names)
    if len(plugin_names) != 35 or len(expected_plugin_names) != 35 or overlay['plugin_expected_passes'] != 35 or overlay['unchanged_plugin_control']['path'] != 'test/plugins/services/reader_selection_service_test.dart':
        raise RuntimeError('Overlay must include all 35 distinct plugin test names')
    inventory = manifest['changed_files']
    if len(inventory) != 20 or len(inventory) != len(set(inventory)) or set(manifest['source_sha256']) != set(inventory) or absent_reader_source in inventory or (repo / absent_reader_source).exists():
        raise RuntimeError('Every changed product file must have a frozen source hash')
    if manifest['full_suite_expected_passes'] != 659:
        raise RuntimeError('Product suite must contain the 659 existing tests without the QA-only reader fixture')
    red_selection = '^(?:' + '|'.join(re.escape(name) for name in sorted(expected_red)) + ')$'
    red_locations = resolve_red_assertions(bundle, red_assertion_specs)
    if set(red_locations) != expected_red:
        raise RuntimeError('Intended assertion locations do not match the RED manifest')
    report['intended_red_assertions'] = red_locations
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('QA must start on the exact clean product commit')
    if git('rev-parse', target + '^') != base:
        raise RuntimeError('Product commit is not based on the reviewed upstream commit')
    if git('rev-parse', target + '^{tree}') != manifest['candidate_tree_sha']:
        raise RuntimeError('Product tree differs from the reviewed manifest tree')
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

    control_fixture_hash = hashlib.sha256((bundle / base_control['fixture']).read_bytes()).hexdigest()
    if control_fixture_hash != base_control['sha256']:
        raise RuntimeError('QA-only reader fixture differs from the complete reviewed CI7 fixture')
    report['reader_fixture_sha256'] = control_fixture_hash
    validate_overlay_sources()

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

    if any(path.exists() for path in (*red_fixtures, *base_control_fixtures)):
        raise RuntimeError('Temporary QA test would overwrite a repository file')
    subprocess.run(['git', 'checkout', '--detach', base], cwd=repo, check=True)
    if git('rev-parse', 'HEAD') != base or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('RED must start on the exact clean reviewed base')
    run_reader_known_red('baseline', base)
    copy_test_fixtures(red_fixtures)
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

    remove_test_fixtures()
    subprocess.run(['git', 'checkout', '--detach', target], cwd=repo, check=True)
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('GREEN must start on the exact clean product commit')
    copy_test_fixtures(red_fixtures)
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
    remove_test_fixtures()
    if git('rev-parse', 'HEAD') != target or git('status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('Product checkout changed during verification')
    run_reader_known_red('candidate', target)
    run_pr3036_overlay()
    require_clean_checkout(target, 'Final product verification')
    focused = report['focused_tests']
    if not focused['success'] or not focused['completed'] or focused['passed'] != manifest['full_suite_expected_passes'] or not (expected_red | required_controls).issubset(focused['passed_names']) or focused['skipped'] or focused['failed'] or focused['errors']:
        raise RuntimeError('Full suites must pass and include every regression and required draft control')
    if any([format_code, analyze_code, test_code, green_code]):
        raise RuntimeError('One or more product checks failed')
    report['status'] = 'PASS'
except Exception as error:
    report['error'] = str(error)
    print('QA ERROR: ' + str(error), flush=True)
finally:
    cleanup_errors = []
    for cleanup in (remove_test_fixtures, restore_pr_overlay):
        try:
            cleanup()
        except Exception as error:
            cleanup_errors.append(str(error))
    try:
        tracked_diff = git('diff', 'HEAD', '--binary')
        if tracked_diff:
            (out / 'working-tree-diff.patch').write_text(tracked_diff + '\n')
        checkout = subprocess.run(['git', 'checkout', '--detach', target], cwd=repo, check=False)
        if checkout.returncode:
            raise RuntimeError('Cannot restore the exact product commit after QA')
        require_clean_checkout(target, 'Final cleanup')
    except Exception as error:
        cleanup_errors.append(str(error))
    if cleanup_errors:
        report['status'] = 'FAIL'
        report['cleanup_errors'] = cleanup_errors
    else:
        report['final_clean_checkout'] = target
    (out / 'qa-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    sums = [hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + str(path.relative_to(out)) for path in sorted(out.rglob('*')) if path.is_file() and path.name != 'SHA256SUMS']
    (out / 'SHA256SUMS').write_text('\n'.join(sums) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
sys.exit(0 if report['status'] == 'PASS' else 1)
