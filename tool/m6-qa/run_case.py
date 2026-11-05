import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys


case_file, app_dir, logs_dir = map(Path, sys.argv[1:4])
case = json.loads(case_file.read_text())
app_dir = app_dir.resolve()
logs_dir = logs_dir.resolve()
logs_dir.mkdir(parents=True, exist_ok=True)
sequence = 0
results = []


def git(directory, *args, data=None):
    return subprocess.check_output(
        ['git', '-C', str(directory), *args], input=data
    ).decode().strip()


def verify_tree(directory, expected, paths):
    subprocess.run(['git', '-C', str(directory), 'add', '--', *paths], check=True)
    actual = git(directory, 'write-tree')
    assert actual == expected, f'Unexpected source tree: {actual} != {expected}'
    subprocess.run(['git', '-C', str(directory), 'diff', '--exit-code'], check=True)
    print(f'Verified source tree: {actual}', flush=True)


def apply(directory, patch, expected, paths, patch_sha256=None):
    encoded = patch.encode()
    if patch_sha256:
        assert hashlib.sha256(encoded).hexdigest() == patch_sha256
    subprocess.run(
        ['git', '-C', str(directory), 'apply', '--index', '-'],
        input=encoded, check=True,
    )
    verify_tree(directory, expected, paths)


def invoke(command, directory, phase, expected_exit=0):
    global sequence
    sequence += 1
    args = command if isinstance(command, list) else (
        ['bash', '-euo', 'pipefail', '-c', command]
        if '\n' in command else shlex.split(command)
    )
    output = logs_dir / f'{sequence:02d}-{phase}.log'
    print('::group::' + phase + ': ' + shlex.join(args), flush=True)
    with output.open('w') as log:
        process = subprocess.Popen(
            args, cwd=directory, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1,
        )
        for line in process.stdout:
            log.write(line)
            print(line, end='', flush=True)
        status = process.wait()
    print('::endgroup::', flush=True)
    results.append({'phase': phase, 'command': args, 'exit': status, 'log': str(output)})
    (logs_dir / 'commands.json').write_text(json.dumps(results, indent=2))
    assert status == expected_exit, f'{phase} exited {status}, expected {expected_exit}'
    reporter = next((a.split('json:', 1)[1] for a in args if a.startswith('--file-reporter=json:')), None)
    event_path = directory / reporter if reporter else output
    if args[:2] == ['flutter', 'test']:
        events = []
        for line in event_path.read_text(errors='replace').splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict):
                events.append(event)
        assert any(e.get('type') == 'done' for e in events), 'No complete test run'
        tests = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
        failures = [e for e in events if e.get('type') == 'testDone' and e.get('result') in ('failure', 'error')]
        passed = [e for e in events if e.get('type') == 'testDone' and e.get('result') == 'success'
                  and not e.get('skipped') and not e.get('hidden')]
        if expected_exit == 0:
            assert not failures and passed, 'Tests did not run successfully'
            assert any(e.get('type') == 'done' and e.get('success') is True for e in events)
        summary = {'passed': len(passed), 'failed': [tests.get(e['testID'], {}) for e in failures]}
        results[-1]['tests'] = summary
        (logs_dir / 'commands.json').write_text(json.dumps(results, indent=2))
        print(json.dumps(summary, ensure_ascii=False), flush=True)
        return status, event_path, events, tests, failures
    return status, output, [], {}, []


def dependencies(directory, phase):
    invoke(['flutter', 'pub', 'get', '--enforce-lockfile'], directory, phase + '-pub')
    for script in ('tool/generate_search_index.dart', 'tool/generate_settings_l10n.dart'):
        invoke(['dart', 'run', script], directory, phase + '-generate')


def verify_failure(result, spec):
    status, path, events, tests, failures = result
    count = spec.get('expected_assertion_failures', spec.get('expected_failed_test_count'))
    assert len(failures) == count, f'Unexpected failing tests: {len(failures)} != {count}'
    assert any(e.get('type') == 'done' and e.get('success') is False for e in events)
    text = path.read_text(errors='replace')
    for forbidden in ('Dart compiler exited unexpectedly', 'Running build hooks failed', 'Failed to load', 'TimeoutException'):
        assert forbidden not in text, f'Infrastructure/fixture failure: {forbidden}'
    if spec.get('verify_python'):
        verifier = logs_dir / 'verify_before.py'
        verifier.write_text(spec['verify_python'])
        values = {'exit': str(status), 'log': str(path)}
        arguments = [values[key] for key in spec.get('verify_args', ['exit', 'log'])]
        subprocess.run([sys.executable, str(verifier), *arguments], check=True)
    else:
        for failure in failures:
            test_id = failure['testID']
            assert not failure.get('hidden'), 'Loading test failed'
            messages = '\n'.join(str(e.get('error', e.get('message', '')))
                                 for e in events if e.get('testID') == test_id and e.get('type') in ('error', 'print'))
            assert 'Expected:' in messages and 'Actual:' in messages, messages
            assert tests[test_id]['name'] in spec['expected_names'], tests[test_id]['name']
        assert all(e.get('testID') in {f['testID'] for f in failures}
                   for e in events if e.get('type') == 'error'), 'Unexpected fixture error'
    print('Verified expected regression assertions', flush=True)


assert git(app_dir, 'rev-parse', 'HEAD') == case['base']
apply(app_dir, case['patch'], case['expected_tree'], case['files'], case.get('patch_sha256'))
dependencies(app_dir, 'after')
for command in case.get('setup_commands', []):
    invoke(command, app_dir, 'after-setup')
for command in case['after_commands']:
    invoke(command, app_dir, 'after')
verify_tree(app_dir, case['expected_tree'], case['files'])

before = case.get('before')
if before:
    if before['mode'] == 'fixture':
        baseline = app_dir.parent / ('before-' + case['name'])
        subprocess.run(['git', '-C', str(app_dir), 'worktree', 'add', '--detach', str(baseline), case['base']], check=True)
        apply(baseline, before['patch'], before['expected_tree'], before['files'])
        dependencies(baseline, 'before')
        for command in before['commands']:
            verify_failure(invoke(command, baseline, 'before', expected_exit=1), before)
        verify_tree(baseline, before['expected_tree'], before['files'])
    else:
        originals = {name: (app_dir / name).read_bytes() for name in before['restore_files_from_base']}
        try:
            for name in originals:
                base_bytes = subprocess.check_output(['git', '-C', str(app_dir), 'show', case['base'] + ':' + name])
                (app_dir / name).write_bytes(base_bytes)
                assert (app_dir / name).read_bytes() == base_bytes
            for command in before['commands']:
                verify_failure(invoke(command, app_dir, 'before', expected_exit=1), before)
        finally:
            for name, content in originals.items():
                (app_dir / name).write_bytes(content)
            verify_tree(app_dir, case['expected_tree'], case['files'])

(logs_dir / 'result.json').write_text(json.dumps({
    'success': True, 'case': case['name'], 'base': case['base'],
    'expected_tree': case['expected_tree'], 'commands': results,
}, indent=2))
print(f"PASS {case['name']} tree {case['expected_tree']}", flush=True)
