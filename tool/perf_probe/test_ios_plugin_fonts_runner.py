"""Host-runner failure and provenance controls; no native coverage is inferred."""
import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import run_ios_plugin_fonts as runner
from run_ios_plugin_fonts import Commands, ROOT, lock_pin, main, retain_committed_lock, select_simulator
from validate_ios_plugin_fonts import WEBVIEW_PACKAGES


class RunnerTests(unittest.TestCase):
    def test_retained_lock_comes_from_the_exact_git_commit(self):
        with tempfile.TemporaryDirectory() as temp:
            repository, output = Path(temp, 'repo'), Path(temp, 'output')
            repository.mkdir()
            output.mkdir()
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repository, stderr=subprocess.STDOUT).decode().strip()
            git('init', '-q')
            lock = repository / 'pubspec.lock'
            original = b'packages:\n  fixture: locked\n'
            lock.write_bytes(original)
            git('add', 'pubspec.lock')
            git('-c', 'user.name=Y-PLONI', '-c', 'user.email=7353755@gmail.com',
                'commit', '-q', '-m', 'Synthetic lock provenance control')
            commit = git('rev-parse', 'HEAD')
            captured = retain_committed_lock(Commands(output), commit, lock)
            self.assertEqual((output / 'pubspec.lock').read_bytes(), original)
            self.assertEqual(captured['lockSourceCommit'], commit)
            self.assertEqual(captured['lockSourceBlob'], git('rev-parse', 'HEAD:pubspec.lock'))
            lock.write_bytes(original + b'changed working copy\n')
            with self.assertRaisesRegex(ValueError, 'selected source commit'):
                retain_committed_lock(Commands(output), commit, lock)
            self.assertEqual((output / 'pubspec.lock').read_bytes(), original)
            git('add', 'pubspec.lock')
            git('-c', 'user.name=Y-PLONI', '-c', 'user.email=7353755@gmail.com',
                'commit', '-q', '-m', 'Synthetic different HEAD')
            with self.assertRaisesRegex(ValueError, 'selected source commit'):
                retain_committed_lock(Commands(output), commit, lock)

    def test_lock_parser_reads_the_actual_pinned_dependencies(self):
        text = (ROOT / 'pubspec.lock').read_text()
        self.assertRegex(lock_pin(text, 'otzaria_search_engine'), r'^[0-9a-f]{40}$')
        webview_pin = lock_pin(text, 'flutter_inappwebview')
        for name in WEBVIEW_PACKAGES:
            self.assertEqual(lock_pin(text, name), webview_pin)
        with self.assertRaises(ValueError):
            lock_pin(text, 'not-a-dependency')
        with self.assertRaises(ValueError):
            lock_pin(text.replace('    source: git', '    source: path'), 'flutter_inappwebview_ios')

    def test_runtime_selection_does_not_substitute_macos_or_unavailable_ios(self):
        runtimes = {'runtimes': [
            {'identifier': 'com.apple.iOS-26-7', 'isAvailable': True, 'version': '26.7', 'buildversion': 'A'},
            {'identifier': 'com.apple.iOS-26-6', 'isAvailable': True, 'version': '26.6', 'buildversion': 'B'},
            {'identifier': 'com.apple.iOS-30-0', 'isAvailable': False, 'version': '30.0', 'buildversion': 'C'},
            {'identifier': 'com.apple.tvOS-26-7', 'isAvailable': True, 'version': '26.7', 'buildversion': 'D'},
        ]}
        def device(name, udid, state='Shutdown'):
            return {'name': name, 'udid': udid, 'isAvailable': True, 'state': state}
        devices = {'devices': {'com.apple.iOS-26-7': [device('iPad', 'ipad'), device('iPhone A', 'new')],
                               'com.apple.iOS-26-6': [device('iPhone B', 'old', 'Booted')],
                               'com.apple.iOS-30-0': [device('iPhone unavailable', 'unavailable')],
                               'com.apple.tvOS-26-7': [device('Apple TV', 'tv')]}}
        selected = select_simulator(devices, runtimes)
        self.assertEqual(selected['device']['udid'], 'new')
        self.assertEqual(selected['version'], '26.7')
        self.assertFalse(selected['booted'])
        devices['devices'].clear()
        with self.assertRaisesRegex(ValueError, 'NOT_RUN'):
            select_simulator(devices, runtimes)

    def test_deadline_retains_partial_output_and_nonzero_verdict(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            runner = Commands(output)
            text, record = runner.run('deadline', [sys.executable, '-u', '-c',
                'import time; print("partial native trace", flush=True); time.sleep(10)'], timeout=0.1, check=False)
            self.assertTrue(record['timedOut'])
            self.assertNotEqual(record['returncode'], 0)
            self.assertIn('partial native trace', text)
            self.assertEqual(json.loads((output / 'commands.json').read_text())[0]['timedOut'], True)
            self.assertLess(record['elapsedSeconds'], 6)

    def test_failure_cannot_return_a_successful_empty_capture(self):
        with tempfile.TemporaryDirectory() as temp:
            runner = Commands(Path(temp))
            with self.assertRaisesRegex(ValueError, 'failed'):
                runner.run('native-failure', [sys.executable, '-c', 'raise SystemExit(7)'])
            self.assertEqual(runner.records[0]['returncode'], 7)
            self.assertFalse(runner.records[0]['timedOut'])

    def test_no_macos_retains_invalid_or_not_run_artifacts(self):
        with tempfile.TemporaryDirectory() as temp, patch('run_ios_plugin_fonts.platform.system', return_value='Linux'):
            with contextlib.redirect_stdout(io.StringIO()):
                result = main(['--instances', '1', '--output', temp])
            self.assertEqual(result, 1)
            comparison = json.loads(Path(temp, 'comparison.json').read_text())
            self.assertEqual(comparison['status'], 'invalid-or-not-run')
            self.assertEqual(comparison['physicalProfile'], 'NOT_RUN')
            self.assertEqual(comparison['physicalRelease'], 'NOT_RUN')
            environment = json.loads(Path(temp, 'environment.json').read_text())
            self.assertEqual(environment['runStatus'], 'failed')
            self.assertNotEqual(environment['captureStatus'], 'complete')

    def test_old_report_without_commands_cannot_be_reused_or_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            old = Path(temp, 'reports/run-old/report.json')
            old.parent.mkdir(parents=True)
            old.write_text('old native evidence')
            before = old.stat().st_mtime_ns
            with self.assertRaisesRegex(ValueError, 'already contains evidence'):
                main(['--instances', '1', '--output', temp])
            self.assertEqual(old.read_text(), 'old native evidence')
            self.assertEqual(old.stat().st_mtime_ns, before)
            self.assertFalse(Path(temp, 'environment.json').exists())

    def test_sigterm_drains_owned_command_and_preserves_a_foreign_process(self):
        with tempfile.TemporaryDirectory() as temp:
            script = '''
import sys
from pathlib import Path
import run_ios_plugin_fonts as runner
def controlled(argv):
    runner.Commands(Path(sys.argv[1])).run('cancel-native',
        [sys.executable, '-u', '-c', 'import time; print("ready", flush=True); time.sleep(30)'])
runner.run_probe = controlled
try:
    runner.main([])
except InterruptedError:
    sys.exit(0)
sys.exit(9)
'''
            env = dict(os.environ, PYTHONPATH=str(ROOT / 'tool/perf_probe'))
            foreign = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
            process = subprocess.Popen([sys.executable, '-c', script, temp], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                deadline = time.monotonic() + 5
                log = Path(temp, 'cancel-native.log')
                while time.monotonic() < deadline and (not log.exists() or 'ready' not in log.read_text()):
                    time.sleep(0.02)
                self.assertTrue(log.exists() and 'ready' in log.read_text())
                process.send_signal(signal.SIGTERM)
                output, _ = process.communicate(timeout=12)
                self.assertEqual(process.returncode, 0, output)
                record = json.loads(Path(temp, 'commands.json').read_text())[0]
                self.assertTrue(record['groupDrained'])
                self.assertFalse(record['timedOut'])
                self.assertNotEqual(record['returncode'], 0)
                self.assertIn('cancelled by signal', record['error'])
                self.assertIsNone(foreign.poll())
            finally:
                for child in (process, foreign):
                    if child.poll() is None:
                        child.kill()
                    child.wait(timeout=5)


class CleanupTests(unittest.TestCase):
    def exercise(self, *, booted=False, source_failure=False, copy_failure=False,
                 hash_failure=False, shutdown_failure=False, drive_failure=None):
        with tempfile.TemporaryDirectory() as temp:
            checkout, output = Path(temp, 'checkout'), Path(temp, 'output')
            pods = checkout / 'ios/Podfile.lock'
            pods.parent.mkdir(parents=True)
            pods.write_bytes(b'Controlled CocoaPods evidence\n')
            calls, state = [], {'running': booted}

            class ControlledCommands:
                def __init__(self, path):
                    self.output = path

                def run(self, label, command, timeout=120, **kwargs):
                    calls.append((label, command, timeout))
                    if label == 'simulator-boot':
                        state['running'] = True
                    elif label == 'simulator-shutdown':
                        if shutdown_failure:
                            raise OSError('shutdown failed')
                        state['running'] = False
                    if label == 'simulator-devices':
                        text = json.dumps({'devices': {'com.apple.iOS-26-7': [{
                            'udid': 'CONTROLLED-SIMULATOR', 'name': 'iPhone control', 'isAvailable': True,
                            'state': 'Booted' if booted else 'Shutdown'}]}})
                    elif label == 'simulator-runtimes':
                        text = json.dumps({'runtimes': [{'identifier': 'com.apple.iOS-26-7',
                            'version': '26.7', 'buildversion': 'control', 'isAvailable': True}]})
                    else:
                        text = 'controlled command; no native execution'
                    if label == 'flutter-drive':
                        if drive_failure is not None:
                            raise drive_failure
                        report = self.output / 'reports/run-control/report.json'
                        report.parent.mkdir(parents=True)
                        report.write_text('{}')
                    return text, {'returncode': 0, 'timedOut': False, 'groupDrained': True}

            def capture(commands, environment, *, after=False):
                calls.append(('sources-after' if after else 'sources-before', [], None))
                if after and source_failure:
                    raise ValueError('source verification failed')
                environment.update(nativeSources={'control': {}}, sourceCommit='1' * 40, lockSha256='2' * 64)

            actual_copy, actual_hash = runner.shutil.copyfile, runner.sha256

            def copy(source, destination):
                calls.append(('podfile-copy', [str(source), str(destination)], None))
                if copy_failure:
                    raise OSError('Podfile.lock copy failed')
                return actual_copy(source, destination)

            def hash_file(path):
                calls.append(('podfile-hash', [str(path)], None))
                if hash_failure:
                    raise OSError('Podfile.lock hash failed')
                return actual_hash(path)

            with patch.object(runner, 'ROOT', checkout), patch.object(runner, 'Commands', ControlledCommands), \
                 patch.object(runner, 'capture_sources', capture), patch.object(runner.platform, 'system', return_value='Darwin'), \
                 patch.object(runner.shutil, 'copyfile', copy), patch.object(runner, 'sha256', hash_file), \
                 patch.object(runner, 'validate_artifacts', return_value={'controlled': True}) as validate, \
                 contextlib.redirect_stdout(io.StringIO()):
                code = runner.run_probe(['--instances', '1', '--output', str(output)])
            environment = json.loads((output / 'environment.json').read_text())
            comparison = json.loads((output / 'comparison.json').read_text())
            if drive_failure is not None or source_failure or copy_failure or hash_failure or shutdown_failure:
                self.assertEqual(code, 1)
                self.assertEqual(environment['runStatus'], 'failed')
                self.assertNotEqual(environment['captureStatus'], 'complete')
                self.assertEqual(comparison['status'], 'invalid-or-not-run')
                self.assertEqual(comparison['reason'], environment['error'])
                self.assertEqual(comparison['decision'], 'keep-default-off')
                validate.assert_not_called()
            else:
                self.assertEqual(code, 0)
                self.assertEqual(environment['runStatus'], 'completed')
                self.assertEqual(environment['captureStatus'], 'complete')
                self.assertIsNone(environment['error'])
                self.assertNotIn('cleanupError', environment)
                self.assertNotIn('cleanupErrors', environment)
                validate.assert_called_once()
            shutdowns = [call for call in calls if call[0] == 'simulator-shutdown']
            self.assertEqual(len(shutdowns), 0 if booted else 1)
            if shutdowns:
                self.assertEqual(shutdowns[0][1], ['xcrun', 'simctl', 'shutdown', 'CONTROLLED-SIMULATOR'])
                self.assertEqual(shutdowns[0][2], 10 if isinstance(drive_failure, InterruptedError) else 60)
            self.assertEqual(state['running'], booted or shutdown_failure)
            if not copy_failure:
                self.assertEqual((output / 'Podfile.lock').read_bytes(), pods.read_bytes())
            if not copy_failure and not hash_failure:
                self.assertEqual(environment['podfileLockSha256'], actual_hash(pods))
            return environment, [call[0] for call in calls]

    def assert_cleanup_errors(self, environment, expected, primary=None):
        self.assertEqual(environment['cleanupErrors'], [{'step': step, 'error': error} for step, error in expected])
        self.assertEqual(environment['cleanupError'], expected[0][1])
        self.assertEqual(environment['error'], expected[0][1] if primary is None else primary)

    def test_success_shuts_down_only_the_owned_simulator(self):
        self.exercise()

    def test_success_leaves_a_preexisting_simulator_running(self):
        self.exercise(booted=True)

    def test_source_failure_still_retains_pods_and_shuts_down(self):
        environment, calls = self.exercise(source_failure=True)
        self.assert_cleanup_errors(environment, [('sources-after', 'source verification failed')])
        self.assertLess(calls.index('sources-after'), calls.index('podfile-copy'))
        self.assertLess(calls.index('podfile-copy'), calls.index('simulator-shutdown'))

    def test_pod_copy_failure_still_shuts_down(self):
        environment, _ = self.exercise(copy_failure=True)
        self.assert_cleanup_errors(environment, [('podfile-lock', 'Podfile.lock copy failed')])

    def test_pod_hash_failure_still_shuts_down(self):
        environment, _ = self.exercise(hash_failure=True)
        self.assert_cleanup_errors(environment, [('podfile-lock', 'Podfile.lock hash failed')])

    def test_driver_failure_survives_a_source_failure(self):
        environment, _ = self.exercise(drive_failure=ValueError('driver failed'), source_failure=True)
        self.assert_cleanup_errors(environment, [('sources-after', 'source verification failed')], 'driver failed')

    def test_shutdown_failure_is_a_failed_capture(self):
        environment, _ = self.exercise(shutdown_failure=True)
        self.assert_cleanup_errors(environment, [('simulator-shutdown', 'shutdown failed')])

    def test_multiple_cleanup_failures_do_not_skip_shutdown(self):
        environment, _ = self.exercise(source_failure=True, copy_failure=True)
        self.assert_cleanup_errors(environment, [('sources-after', 'source verification failed'),
                                                 ('podfile-lock', 'Podfile.lock copy failed')])

    def test_all_cleanup_failures_are_retained_in_order(self):
        environment, _ = self.exercise(source_failure=True, copy_failure=True, shutdown_failure=True)
        self.assert_cleanup_errors(environment, [('sources-after', 'source verification failed'),
            ('podfile-lock', 'Podfile.lock copy failed'), ('simulator-shutdown', 'shutdown failed')])

    def test_primary_failure_survives_all_cleanup_failures(self):
        environment, _ = self.exercise(drive_failure=ValueError('driver failed'), source_failure=True,
                                       copy_failure=True, shutdown_failure=True)
        self.assert_cleanup_errors(environment, [('sources-after', 'source verification failed'),
            ('podfile-lock', 'Podfile.lock copy failed'), ('simulator-shutdown', 'shutdown failed')], 'driver failed')

    def test_an_empty_primary_failure_is_not_replaced(self):
        environment, _ = self.exercise(drive_failure=ValueError(''), source_failure=True)
        self.assert_cleanup_errors(environment, [('sources-after', 'source verification failed')], '')

    def test_cleanup_failures_leave_a_preexisting_simulator_untouched(self):
        environment, _ = self.exercise(booted=True, source_failure=True, copy_failure=True)
        self.assert_cleanup_errors(environment, [('sources-after', 'source verification failed'),
                                                 ('podfile-lock', 'Podfile.lock copy failed')])

    def test_cancellation_preserves_failure_and_the_short_owned_shutdown(self):
        environment, calls = self.exercise(drive_failure=InterruptedError('cancelled driver'))
        self.assertEqual(environment['error'], 'cancelled driver')
        self.assertTrue(environment['cancelled'])
        self.assertNotIn('sources-after', calls)
        self.assertNotIn('cleanupErrors', environment)


class RunnerIoTests(unittest.TestCase):
    """Exercise the real command runner with owned children and filesystem faults."""

    def exercise(self, **scenario):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            checkout, output = directory / 'checkout', directory / 'output'
            pods = checkout / 'ios/Podfile.lock'
            pods.parent.mkdir(parents=True)
            pods.write_text('Controlled CocoaPods lock\n')
            (directory / 'scenario.json').write_text(json.dumps(scenario))
            (directory / 'state.json').write_text(json.dumps({'running': scenario.get('borrowed', False)}))
            child = directory / 'child.py'
            child.write_text(r'''
import json, os, sys, time
from pathlib import Path
directory, label = Path(sys.argv[1]), sys.argv[2]
scenario = json.loads((directory / 'scenario.json').read_text())
output = directory / 'output'
state = json.loads((directory / 'state.json').read_text())
with (directory / 'children.jsonl').open('a') as stream:
    stream.write(json.dumps({'label': label, 'pgid': os.getpgrp()}) + '\n')
def block(name):
    path = output / name
    if path.is_file():
        path.unlink()
    path.mkdir(exist_ok=True)
if label == 'simulator-devices':
    print(json.dumps({'devices': {'com.apple.iOS-26-7': [{'udid': 'OWNED-IO-CONTROL',
        'name': 'iPhone control', 'isAvailable': True, 'state': 'Booted' if state['running'] else 'Shutdown'}]}}))
elif label == 'simulator-runtimes':
    print(json.dumps({'runtimes': [{'identifier': 'com.apple.iOS-26-7',
        'version': '26.7', 'buildversion': 'control', 'isAvailable': True}]}))
else:
    print('controlled child: ' + label, flush=True)
if label == 'simulator-boot':
    state['running'] = True
    (directory / 'state.json').write_text(json.dumps(state))
    if scenario.get('bootReceiptFault'):
        block('commands.json')
if label == 'flutter-drive':
    report = output / 'reports/run-control/report.json'
    report.parent.mkdir(parents=True)
    report.write_text('{}')
    for flag, name in [('driveReceiptFault', 'commands.json'), ('podFault', 'Podfile.lock'),
                       ('environmentFault', 'environment.json'), ('comparisonFault', 'comparison.json'),
                       ('shutdownLogFault', 'simulator-shutdown.log')]:
        if scenario.get(flag):
            block(name)
    if scenario.get('driveTimeout'):
        time.sleep(10)
if scenario.get('readFault') == label:
    block(label + '.log')
if label == 'source-after' and scenario.get('sourceExit'):
    sys.exit(scenario['sourceExit'])
if label == 'simulator-shutdown':
    if scenario.get('shutdownExit'):
        sys.exit(scenario['shutdownExit'])
    state['running'] = False
    (directory / 'state.json').write_text(json.dumps(state))
if label == 'flutter-drive':
    sys.exit(scenario.get('driveExit', 0))
''')
            instances, writes, environment_refs, wrapped_logs = [], [], [], []
            actual_commands = runner.Commands

            class ChildCommands(actual_commands):
                def __init__(self, path):
                    super().__init__(path)
                    instances.append(self)

                def run(self, label, command, timeout=120, *, cwd=None, env=None, check=True):
                    command = [sys.executable, str(child), str(directory), label]
                    if label == 'flutter-drive' and scenario.get('startFault'):
                        command = [str(directory / 'missing-executable')]
                    deadline = 0.2 if label == 'flutter-drive' and scenario.get('driveTimeout') else min(timeout, 5)
                    return super().run(label, command, deadline, cwd=checkout, env=env, check=check)

            def capture(commands, environment, *, after=False):
                if not after:
                    environment.update(nativeSources={'control': {}}, sourceCommit='1' * 40, lockSha256='2' * 64)
                commands.run('source-after' if after else 'source-before', ['controlled source'])

            actual_write, actual_open = runner.write_json, Path.open

            def block(path):
                if path.is_file():
                    path.unlink()
                path.mkdir(exist_ok=True)

            def write(path, value):
                writes.append({'name': path.name, 'value': copy.deepcopy(value)})
                if path.name == 'environment.json':
                    environment_refs.append(value)
                if path.name == 'commands.json':
                    last = value[-1]
                    if ((scenario.get('shutdownReceiptFault') and last['label'] == 'simulator-shutdown') or
                        (scenario.get('bootBeforeReceiptFault') and last['label'] == 'simulator-boot')):
                        if last['returncode'] is None:
                            block(path)
                if path.name == 'environment.json':
                    if ((scenario.get('initialEnvironmentFault') and value['captureStatus'] == 'pending') or
                        (scenario.get('readyEnvironmentFault') and value['captureStatus'] == 'ready') or
                        (scenario.get('finalEnvironmentFault') and value.get('reportingStatus') == 'complete')):
                        block(path)
                return actual_write(path, value)

            class CloseFault:
                def __init__(self, stream):
                    self.stream = stream

                def fileno(self):
                    return self.stream.fileno()

                def close(self):
                    self.stream.close()
                    raise OSError('controlled log close failure')

            def open_file(path, *args, **kwargs):
                stream = actual_open(path, *args, **kwargs)
                if scenario.get('closeFault') and path == output / (scenario['closeFault'] + '.log') and args[:1] == ('w',):
                    wrapper = CloseFault(stream)
                    wrapped_logs.append(wrapper)
                    return wrapper
                return stream

            class BrokenStream(io.StringIO):
                def write(self, text):
                    raise BrokenPipeError('controlled reporting pipe is closed')

            stdout = BrokenStream() if scenario.get('stdoutFault') else io.StringIO()
            stderr = BrokenStream() if scenario.get('stderrFault') else io.StringIO()
            with patch.object(runner, 'ROOT', checkout), patch.object(runner, 'Commands', ChildCommands), \
                 patch.object(runner, 'capture_sources', capture), patch.object(runner.platform, 'system', return_value='Darwin'), \
                 patch.object(runner, 'write_json', write), patch.object(Path, 'open', open_file), \
                 patch.object(runner, 'validate_artifacts', return_value={'controlled': True}) as validate, \
                 contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = runner.run_probe(['--instances', '1', '--output', str(output)])
            records = instances[0].records
            environment = environment_refs[-1]
            comparison = json.loads((output / 'comparison.json').read_text()) if (output / 'comparison.json').is_file() else None
            children_path = directory / 'children.jsonl'
            children = [json.loads(line) for line in children_path.read_text().splitlines()] if children_path.exists() else []
            labels = [item['label'] for item in children]
            state = json.loads((directory / 'state.json').read_text())
            for item in children:
                self.assertFalse(runner.group_alive(item['pgid']), item)
            self.assertTrue(all(record['groupDrained'] for record in records))
            self.assertTrue(all(wrapper.stream.closed for wrapper in wrapped_logs))
            self.assertEqual(len([name for name in labels if name == 'simulator-shutdown']),
                             1 if 'simulator-boot' in labels else 0)
            self.assertEqual(state['running'], scenario.get('borrowed', False) or bool(scenario.get('shutdownExit')))
            self.assertEqual(code, 1 if any(value for key, value in scenario.items() if key != 'borrowed') else 0)
            if code:
                self.assertEqual(environment['runStatus'], 'failed')
                self.assertNotEqual(environment['captureStatus'], 'complete')
                self.assertEqual(environment['reportingStatus'], 'failed')
                if (output / 'environment.json').is_file():
                    self.assertNotEqual(json.loads((output / 'environment.json').read_text())['captureStatus'], 'complete')
                if comparison is not None:
                    self.assertEqual(comparison['status'], 'invalid-or-not-run')
                    self.assertEqual(comparison['reason'], environment['error'])
            if scenario.get('driveExit') == 23:
                self.assertEqual(environment['drive']['returncode'], 23)
                self.assertIn('flutter-drive', environment['error'])
                self.assertIn('23', environment['error'])
            if scenario.get('borrowed'):
                self.assertFalse(environment['simulatorOwnership']['owned'])
                self.assertNotIn('simulator-boot', labels)
                self.assertNotIn('simulator-shutdown', labels)
            evidence = {'scenario': scenario, 'exit': code, 'environment': environment, 'comparison': comparison,
                        'records': records, 'children': children, 'state': state, 'stdout': stdout.getvalue(),
                        'stderr': stderr.getvalue(), 'allOwnedGroupsDrained': True, 'nativeExecution': False,
                        'validatorCalls': validate.call_count}
            if os.environ.get('IOS_FONT_RUNNER_TEST_EVIDENCE'):
                identifier = self.id().split('.')[-1] + '-' + hashlib.sha256(json.dumps(scenario, sort_keys=True).encode()).hexdigest()[:12]
                destination = Path(os.environ['IOS_FONT_RUNNER_TEST_EVIDENCE']) / identifier
                shutil.copytree(directory, destination)
                (destination / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
            return evidence

    def test_real_children_retain_driver_exit_and_successful_boot_ownership(self):
        for scenario in ({'driveExit': 23, 'driveReceiptFault': True}, {'bootReceiptFault': True},
                         {'bootBeforeReceiptFault': True}):
            with self.subTest(scenario=scenario):
                result = self.exercise(**scenario)
                if scenario.get('bootReceiptFault'):
                    self.assertTrue(result['environment']['simulatorOwnership']['owned'])
                    self.assertTrue(result['environment']['simulatorOwnership']['released'])
                    boot = next(item for item in result['records'] if item['label'] == 'simulator-boot')
                    self.assertEqual(boot['returncode'], 0)
                if scenario.get('bootBeforeReceiptFault'):
                    self.assertFalse(result['environment']['simulatorOwnership']['owned'])

    def test_shutdown_executes_without_receipt_or_log_storage(self):
        for fault in ({'shutdownReceiptFault': True}, {'shutdownLogFault': True},
                      {'shutdownReceiptFault': True, 'shutdownLogFault': True}):
            with self.subTest(fault=fault):
                result = self.exercise(driveExit=23, **fault)
                shutdown = next(item for item in result['records'] if item['label'] == 'simulator-shutdown')
                self.assertTrue(shutdown['started'])
                self.assertEqual(shutdown['returncode'], 0)
                self.assertTrue(shutdown['failures'])

    def test_log_close_and_read_failures_cannot_erase_command_outcomes(self):
        for label in ('simulator-boot', 'flutter-drive'):
            for fault in ('closeFault', 'readFault'):
                with self.subTest(label=label, fault=fault):
                    scenario = {fault: label}
                    if label == 'flutter-drive':
                        scenario['driveExit'] = 23
                    result = self.exercise(**scenario)
                    command = next(item for item in result['records'] if item['label'] == label)
                    self.assertEqual(command['returncode'], 23 if label == 'flutter-drive' else 0)
                    self.assertTrue(result['environment']['simulatorOwnership']['released'])

    def test_final_environment_comparison_and_stdout_fail_independently(self):
        for fault in ('environmentFault', 'comparisonFault', 'stdoutFault'):
            with self.subTest(fault=fault):
                result = self.exercise(driveExit=23, **{fault: True})
                self.assertTrue(result['environment']['reportingErrors'])
                self.assertLessEqual(len(result['stderr'].encode()), 65536)

    def test_diagnostic_only_failures_remain_failed(self):
        for fault in ('driveReceiptFault', 'environmentFault', 'comparisonFault', 'stdoutFault'):
            with self.subTest(fault=fault):
                result = self.exercise(**{fault: True})
                self.assertEqual(result['environment']['drive']['returncode'], 0)
                self.assertEqual(result['exit'], 1)

    def test_initial_and_ready_environment_faults_release_only_acquired_resources(self):
        for fault in ('initialEnvironmentFault', 'readyEnvironmentFault'):
            with self.subTest(fault=fault):
                result = self.exercise(**{fault: True})
                self.assertNotIn('drive', result['environment'])
                if fault == 'initialEnvironmentFault':
                    self.assertEqual(result['children'], [])
                else:
                    self.assertTrue(result['environment']['simulatorOwnership']['released'])

    def test_driver_failure_survives_all_later_command_and_reporting_failures(self):
        result = self.exercise(driveExit=23, sourceExit=29, podFault=True, shutdownExit=31,
                               shutdownReceiptFault=True, environmentFault=True, comparisonFault=True,
                               stdoutFault=True, stderrFault=True)
        errors = result['environment']['secondaryErrors']
        self.assertTrue(any('29' in item['error'] for item in errors))
        self.assertTrue(any('31' in item['error'] for item in errors))
        self.assertTrue(any(item['step'] == 'stderr-report' for item in errors))
        self.assertTrue(result['state']['running'])

    def test_borrowed_simulator_is_untouched_under_combined_failures(self):
        self.exercise(borrowed=True, driveExit=23, sourceExit=29, podFault=True, driveReceiptFault=True,
                      environmentFault=True, comparisonFault=True, stdoutFault=True, stderrFault=True)

    def test_start_failure_keeps_driver_record_and_releases_owned_simulator(self):
        result = self.exercise(startFault=True)
        self.assertIn('drive', result['environment'])
        self.assertFalse(result['environment']['drive']['started'])
        self.assertIsNone(result['environment']['drive']['returncode'])
        self.assertTrue(result['environment']['simulatorOwnership']['released'])

    def test_timeout_survives_receipt_fault_with_owned_group_drained(self):
        result = self.exercise(driveTimeout=True, driveReceiptFault=True)
        drive = result['environment']['drive']
        self.assertTrue(drive['timedOut'])
        self.assertNotEqual(drive['returncode'], 0)
        self.assertTrue(drive['groupDrained'])
        self.assertIn('timed out', result['environment']['error'])

    def test_failed_final_environment_commit_leaves_no_success_capture(self):
        result = self.exercise(finalEnvironmentFault=True)
        self.assertEqual(result['comparison']['status'], 'invalid-or-not-run')
        self.assertTrue(result['environment']['reportingErrors'])
        self.assertIn('environment', result['stderr'])

    def test_positive_real_children_preserve_owned_and_borrowed_controls(self):
        self.exercise()
        self.exercise(borrowed=True)

    def test_stderr_fallback_is_bounded_and_keeps_the_primary_failure(self):
        environment = {'commandRecords': [], 'drive': {'returncode': 23}}
        failures = runner.ProbeFailures(environment)
        failures.add('driver', ValueError('primary exit23'))
        for index in range(100):
            failures.add('secondary', OSError(str(index) + '\U0001f680' * 10000), reporting=True)
        with contextlib.redirect_stderr(io.StringIO()) as stream:
            runner.stderr_summary(failures.result(None))
        self.assertLessEqual(len(stream.getvalue().encode()), 65536)
        summary = json.loads(stream.getvalue())
        self.assertEqual(summary['reason'], 'primary exit23')
        self.assertEqual(summary['drive']['returncode'], 23)
        self.assertTrue(summary['truncated'])
        self.assertEqual(summary['secondaryErrorCount'], 100)
        self.assertEqual(summary['omittedSecondaryErrors'] + len(summary['secondaryErrors']), 100)
        self.assertEqual(len(environment['secondaryErrors']), 100)

    def test_native_exit_precedes_drain_and_receipt_failures(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            commands = runner.Commands(output)
            actual_write = runner.write_json

            def write(path, value):
                if value[-1]['returncode'] is not None:
                    path.unlink()
                    path.mkdir()
                return actual_write(path, value)

            with patch.object(runner, 'write_json', write), \
                 patch.object(runner, 'group_alive', side_effect=PermissionError('controlled group query failure')):
                _, record = commands.run('native-exit', [sys.executable, '-c', 'raise SystemExit(23)'], check=False)
            self.assertEqual(record['returncode'], 23)
            self.assertIn('exit code 23', record['failures'][0]['error'])
            self.assertEqual([item['step'] for item in record['failures']],
                             ['process-exit', 'drain-check', 'receipt-after'])
            self.assertFalse(record['groupDrained'])
            self.assertFalse(runner.group_alive(record['processGroup']))
            if os.environ.get('IOS_FONT_RUNNER_TEST_EVIDENCE'):
                path = Path(os.environ['IOS_FONT_RUNNER_TEST_EVIDENCE']) / 'native-exit-drain-receipt.json'
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    unittest.main()
