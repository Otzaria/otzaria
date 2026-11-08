#!/usr/bin/env python3
"""Run the actual debug iOS Simulator fixture with bounded, retained evidence."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse

from validate_ios_plugin_fonts import (FLUTTER_REVISION, NATIVE_PACKAGES, lock_pin, read_json,
                                       require, validate_artifacts)

ROOT = Path(__file__).resolve().parents[2]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_simulator(devices, runtimes):
    available = {r['identifier']: r for r in runtimes['runtimes']
                 if r.get('isAvailable') is True and '.iOS-' in r['identifier']}
    candidates = [(available[r], d) for r, values in devices['devices'].items() if r in available
                  for d in values if d.get('isAvailable') is True and d['name'].startswith('iPhone')]
    require(candidates, 'No available iPhone Simulator; native coverage is NOT_RUN')
    candidates.sort(key=lambda item: (tuple(int(v) for v in item[0]['version'].split('.')),
                                     item[1]['state'] == 'Booted'), reverse=True)
    runtime, device = candidates[0]
    return {'deviceKind': 'simulator', 'device': device, 'identifier': runtime['identifier'],
            'version': runtime['version'], 'buildversion': runtime['buildversion'], 'booted': False}


def signal_group(pid, sig):
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        pass


def group_alive(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False


class CommandFailure(ValueError):
    def __init__(self, record):
        self.command_record = record
        super().__init__(record['failures'][0]['error'])


class Commands:
    def __init__(self, output):
        self.output = output
        self.records = []
        self.on_record = lambda record: None
        self.cleanup_mode = False

    def run(self, label, command, timeout=120, *, cwd=ROOT, env=None, check=True):
        log = self.output / (label + '.log')
        record = {'label': label, 'command': command, 'cwd': str(cwd),
                  'timeoutSeconds': timeout, 'timedOut': False, 'returncode': None,
                  'startedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'log': log.name, 'started': False, 'groupDrained': True, 'failures': []}
        self.records.append(record)
        self.on_record(record)
        start = time.monotonic()
        interrupted, process, stream, text = None, None, None, ''
        exit_noted = False

        def failure(step, error, kind):
            nonlocal interrupted
            record['failures'].append({'step': step, 'kind': kind,
                                       'type': type(error).__name__, 'error': str(error)})
            record.setdefault('error', str(error))
            if isinstance(error, (InterruptedError, KeyboardInterrupt)):
                interrupted = interrupted or error
                record['cancelled'] = True

        def attempt(step, operation, kind='diagnostic'):
            try:
                return operation()
            except (Exception, KeyboardInterrupt) as error:
                failure(step, error, kind)
                return None

        def completed(returncode):
            nonlocal exit_noted
            record['returncode'] = returncode
            if returncode is not None and not exit_noted:
                exit_noted = True
                if returncode != 0 and not record['timedOut'] and interrupted is None:
                    failure('process-exit', ValueError(f'{label} failed with exit code {returncode}'), 'execution')
            # Ownership and the driver reference must survive every later I/O operation.
            self.on_record(record)

        attempt('receipt-before', lambda: write_json(self.output / 'commands.json', self.records))
        if self.cleanup_mode or not record['failures']:
            stream = attempt('log-open', lambda: log.open('w'))
        try:
            if self.cleanup_mode or not record['failures']:
                process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                           stdout=stream if stream is not None else subprocess.DEVNULL,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                record.update(started=True, pid=process.pid, processGroup=process.pid, groupDrained=False)
                try:
                    completed(process.wait(timeout=timeout))
                except subprocess.TimeoutExpired as error:
                    record['timedOut'] = True
                    failure('process-timeout', error, 'execution')
                    attempt('timeout-term', lambda: signal_group(process.pid, signal.SIGTERM), 'cleanup')
                    try:
                        completed(process.wait(timeout=5))
                    except subprocess.TimeoutExpired:
                        attempt('timeout-kill', lambda: signal_group(process.pid, signal.SIGKILL), 'cleanup')
                        attempt('timeout-wait', lambda: completed(process.wait(timeout=5)), 'cleanup')
                    except (Exception, KeyboardInterrupt) as error:
                        failure('timeout-wait', error, 'cleanup')
                except (Exception, KeyboardInterrupt) as error:
                    failure('process-wait', error, 'execution')
                finally:
                    attempt('drain-term', lambda: signal_group(process.pid, signal.SIGTERM), 'cleanup')
                    attempt('drain-kill', lambda: signal_group(process.pid, signal.SIGKILL), 'cleanup')
                    attempt('drain-wait', lambda: completed(process.wait(timeout=5)), 'cleanup')
                    deadline = time.monotonic() + 5
                    try:
                        while group_alive(process.pid) and time.monotonic() < deadline:
                            time.sleep(0.05)
                        record['groupDrained'] = not group_alive(process.pid)
                        require(record['groupDrained'], f'{label} owned process group did not drain')
                    except (Exception, KeyboardInterrupt) as error:
                        failure('drain-check', error, 'cleanup')
        except (Exception, KeyboardInterrupt) as error:
            failure('process-start', error, 'execution')
        finally:
            if stream is not None:
                attempt('log-close', stream.close)
                text = attempt('log-read', lambda: log.read_text(errors='replace').strip()) or ''
            record['elapsedSeconds'] = round(time.monotonic() - start, 3)
            attempt('receipt-after', lambda: write_json(self.output / 'commands.json', self.records))
        if interrupted is not None:
            interrupted.command_record = record
            raise interrupted
        if check and record['failures']:
            raise CommandFailure(record)
        return text, record


class ProbeFailures:
    def __init__(self, environment):
        self.environment = environment
        self.entries = []

    @property
    def error(self):
        return self.entries[0]['error'] if self.entries else None

    def add(self, step, failure, *, cleanup=False, reporting=False):
        record = getattr(failure, 'command_record', None)
        details = record['failures'] if record is not None else [
            {'type': type(failure).__name__, 'error': str(failure)}]
        for detail in details:
            entry = {'step': step, 'type': detail['type'], 'error': detail['error']}
            if record is not None:
                entry.update(command=record['label'], commandStep=detail['step'], kind=detail['kind'])
            self.entries.append(entry)
            if cleanup:
                self.environment.setdefault('cleanupErrors', []).append({'step': step, 'error': detail['error']})
                self.environment.setdefault('cleanupError', detail['error'])
            if reporting:
                self.environment.setdefault('reportingErrors', []).append(entry)
                self.environment['reportingStatus'] = 'failed'
        self.environment.update(error=self.error, primaryFailure=self.entries[0],
                                secondaryErrors=self.entries[1:], runStatus='failed', captureStatus='failed')
        if isinstance(failure, (InterruptedError, KeyboardInterrupt)) or (record and record.get('cancelled')):
            self.environment['cancelled'] = True

    def result(self, compatibility):
        if not self.entries:
            return {'status': 'complete', 'compatibility': compatibility}
        return {'status': 'invalid-or-not-run', 'reason': self.error, 'primaryFailure': self.entries[0],
                'secondaryErrors': self.entries[1:], 'drive': self.environment.get('drive'),
                'commandRecords': self.environment['commandRecords'], 'decision': 'keep-default-off',
                'physicalProfile': 'NOT_RUN', 'physicalRelease': 'NOT_RUN'}


def stderr_summary(result):
    summary = {key: result[key] for key in ('status', 'reason', 'primaryFailure', 'secondaryErrors', 'decision')}
    drive = result.get('drive')
    summary['drive'] = {key: drive.get(key) for key in ('returncode', 'timedOut', 'groupDrained', 'log')} if drive else None
    summary['truncated'] = False
    summary['secondaryErrorCount'] = len(summary['secondaryErrors'])
    summary['omittedSecondaryErrors'] = 0
    for entry in [summary['primaryFailure'], *summary['secondaryErrors']]:
        if len(entry['error']) > 4096:
            summary['truncated'] = True
    summary['reason'] = summary['reason'][:4096]
    summary['primaryFailure'] = dict(summary['primaryFailure'], error=summary['primaryFailure']['error'][:4096])
    summary['secondaryErrors'] = [dict(entry, error=entry['error'][:4096]) for entry in summary['secondaryErrors']]
    text = json.dumps(summary, ensure_ascii=True, allow_nan=False)
    while len(text.encode()) > 65535 and summary['secondaryErrors']:
        summary['secondaryErrors'].pop()
        summary['omittedSecondaryErrors'] += 1
        summary['truncated'] = True
        text = json.dumps(summary, ensure_ascii=True, allow_nan=False)
    while len(text.encode()) > 65535:
        summary['reason'] = summary['reason'][:len(summary['reason']) // 2]
        summary['primaryFailure']['error'] = summary['reason']
        summary['truncated'] = True
        text = json.dumps(summary, ensure_ascii=True, allow_nan=False)
    sys.stderr.write(text + '\n')
    sys.stderr.flush()


def report_probe(output, environment, failures, compatibility):
    def attempt(step, operation):
        try:
            operation()
            return True
        except (Exception, KeyboardInterrupt) as error:
            failures.add(step, error, reporting=True)
            return False

    def comparison():
        write_json(output / 'comparison.json', failures.result(compatibility))

    # A success capture is persisted only after comparison and stdout were attempted.
    pending = dict(environment, captureStatus='failed' if failures.entries else 'pending-reporting', reportingStatus='pending')
    attempt('environment-report', lambda: write_json(output / 'environment.json', pending))
    attempt('comparison-report', comparison)
    attempt('stdout-report', lambda: print(json.dumps(failures.result(compatibility), indent=2, allow_nan=False), flush=True))
    if environment.get('reportingErrors'):
        attempt('comparison-refresh', comparison)
    environment['reportingStatus'] = 'failed' if failures.entries else 'complete'
    environment['captureStatus'] = 'failed' if failures.entries else 'complete'
    if not attempt('environment-final', lambda: write_json(output / 'environment.json', environment)):
        attempt('comparison-final', comparison)
    if environment.get('reportingErrors'):
        if not attempt('stderr-report', lambda: stderr_summary(failures.result(compatibility))):
            attempt('environment-fallback', lambda: write_json(output / 'environment.json', environment))
            attempt('comparison-fallback', comparison)
    return 0 if not failures.entries else 1


def retain_committed_lock(commands, commit, working_lock):
    commands.run('committed-pubspec-lock', ['git', 'show', f'{commit}:pubspec.lock'], cwd=working_lock.parent)
    committed = (commands.output / 'committed-pubspec-lock.log').read_bytes()
    require(committed == working_lock.read_bytes(), 'Working lock differs from the selected source commit')
    blob = commands.run('committed-lock-blob', ['git', 'rev-parse', f'{commit}:pubspec.lock'], cwd=working_lock.parent)[0]
    (commands.output / 'pubspec.lock').write_bytes(committed)
    return {'committedLockSha256': hashlib.sha256(committed).hexdigest(),
            'lockSourceCommit': commit, 'lockSourceBlob': blob}


def capture_sources(commands, environment, *, after=False):
    suffix = 'After' if after else ''
    environment['sourceStatus' + suffix] = commands.run('source-status' + suffix,
        ['git', 'status', '--porcelain'])[0]
    environment['lockSha256' + suffix] = sha256(ROOT / 'pubspec.lock')
    sdk = Path(shutil.which('flutter')).resolve().parents[1]
    environment['flutterSourceStatus' + suffix] = commands.run('flutter-status' + suffix,
        ['git', 'status', '--porcelain'], cwd=sdk)[0]
    environment['sourceCommit' + suffix] = commands.run('source-commit' + suffix, ['git', 'rev-parse', 'HEAD'])[0]
    environment['sourceTree' + suffix] = commands.run('source-tree' + suffix, ['git', 'rev-parse', environment['sourceCommit' + suffix] + '^{tree}'])[0]
    environment['flutterSourceCommit' + suffix] = commands.run('flutter-commit' + suffix, ['git', 'rev-parse', 'HEAD'], cwd=sdk)[0]
    if not after:
        environment['flutter'] = json.loads(commands.run('flutter-version', ['flutter', '--version', '--machine'])[0])
        require(environment['flutterSourceCommit'] == FLUTTER_REVISION, 'Unexpected Flutter source checkout')
        config = ROOT / '.dart_tool/package_config.json'
        packages = {p['name']: p for p in read_json(config)['packages']}
        environment.update(retain_committed_lock(commands, environment['sourceCommit'], ROOT / 'pubspec.lock'))
        text = (commands.output / 'pubspec.lock').read_text()
        environment['nativeSources'] = {}
        for name in NATIVE_PACKAGES:
            resolved = urlparse(urljoin(config.as_uri(), packages[name]['rootUri']))
            require(resolved.scheme == 'file', 'Native source must resolve to local pinned Git')
            root = Path(unquote(resolved.path))
            environment['nativeSources'][name] = {'root': str(root), 'lockPin': lock_pin(text, name),
                'head': commands.run(name + '-head', ['git', 'rev-parse', 'HEAD'], cwd=root)[0]}
        environment['enginePin'] = environment['nativeSources']['otzaria_search_engine']['lockPin']
        environment['webviewPin'] = environment['nativeSources']['flutter_inappwebview_ios']['lockPin']
    for name, source in environment['nativeSources'].items():
        if after:
            source['headAfter'] = commands.run(name + '-headAfter', ['git', 'rev-parse', 'HEAD'], cwd=Path(source['root']))[0]
        source['status' + suffix] = commands.run(name + '-status' + suffix,
            ['git', 'status', '--porcelain'], cwd=Path(source['root']))[0]
        require(source['status' + suffix] == '' and source['head' + suffix] == source['lockPin'],
                f'Modified or unlocked native dependency: {name}')
    require(environment['sourceStatus' + suffix] == environment['flutterSourceStatus' + suffix] == '', 'App or Flutter checkout is modified')


def retain_source_diff(commands, environment):
    if environment.get('cancelled'):
        return
    if not environment.get('sourceStatusAfter'):
        return
    # The source gate has already recorded its failure. Diagnostic I/O must not
    # replace that failure or prevent Podfile.lock retention and owned shutdown.
    label = 'source-diffAfter'
    commands.run(label, ['git', 'diff', '--no-ext-diff', '--no-textconv', '--binary',
                         environment['sourceCommit'], '--'])
    path = commands.output / (label + '.log')
    environment['sourceDiffAfter'] = {'baseCommit': environment['sourceCommit'],
                                      'file': path.name, 'sha256': sha256(path)}


def run_probe(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--instances', type=int, choices=(1, 5, 10), required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    setup_files = {'workflow.json', 'rust-targets.log', 'pub-get.log'}
    require(all(p.name in setup_files and p.is_file() and not p.is_symlink()
                for p in output.iterdir()), 'Output already contains evidence; use a new directory')
    commands = Commands(output)
    environment = {'schemaVersion': 1, 'captureStatus': 'pending', 'runStatus': 'not-run',
                   'mode': 'debug', 'instances': args.instances, 'physicalProfile': 'NOT_RUN',
                   'physicalRelease': 'NOT_RUN', 'decision': 'keep-default-off', 'commandRecords': []}
    failures = ProbeFailures(environment)
    shutdown, boot_candidate = None, None

    def observe(record):
        nonlocal shutdown
        if not any(item is record for item in environment['commandRecords']):
            environment['commandRecords'].append(record)
        if record['label'] == 'flutter-drive':
            environment['drive'] = record
        if record['label'] == 'simulator-boot' and record['returncode'] == 0:
            shutdown = boot_candidate
            environment['simulatorOwnership'].update(owned=True, bootReturncode=0)
        if record['label'] == 'simulator-shutdown' and record['returncode'] == 0:
            shutdown = None
            environment['simulatorOwnership'].update(released=True, shutdownReturncode=0)

    commands.on_record = observe
    step = 'environment-initial'
    try:
        write_json(output / 'environment.json', environment)
        step = 'probe'
        require(platform.system() == 'Darwin', 'Actual iOS Simulator requires macOS and Xcode')
        capture_sources(commands, environment)
        for key, command in {
            'xcode': ['xcodebuild', '-version'],
            'sdkVersion': ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'],
            'sdkBuild': ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-build-version'],
            'hostOS': ['sw_vers'], 'hostArchitecture': ['uname', '-m'],
            'rustc': ['rustc', '--version', '--verbose'], 'cargo': ['cargo', '--version'],
            'rustToolchain': ['rustup', 'show', 'active-toolchain'],
            'rustTargets': ['rustup', 'target', 'list', '--installed'],
        }.items():
            environment[key] = commands.run(key, command)[0]
        devices = json.loads(commands.run('simulator-devices', ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'])[0])
        runtimes = json.loads(commands.run('simulator-runtimes', ['xcrun', 'simctl', 'list', 'runtimes', '--json'])[0])
        runtime = environment['runtime'] = select_simulator(devices, runtimes)
        device = runtime['device']['udid']
        environment['simulatorOwnership'] = {'device': device, 'owned': False, 'released': False}
        if runtime['device']['state'] != 'Booted':
            boot_candidate = device
            _, boot = commands.run('simulator-boot', ['xcrun', 'simctl', 'boot', device])
            if boot['returncode'] == 0:
                shutdown = device
                environment['simulatorOwnership'].update(owned=True, bootReturncode=0)
            require(boot['returncode'] == 0 and not boot['timedOut'] and boot['groupDrained'], 'Simulator boot failed')
        commands.run('simulator-bootstatus', ['xcrun', 'simctl', 'bootstatus', device, '-b'], 240)
        commands.run('simulator-visible', ['open', '-a', 'Simulator'], 30)
        runtime['booted'] = True
        environment['captureStatus'] = 'ready'
        step = 'environment-ready'
        write_json(output / 'environment.json', environment)
        step = 'driver'
        env = dict(os.environ, IOS_FONT_PROBE_REPORTS=str(output / 'reports'))
        _, drive = commands.run('flutter-drive', [
            'flutter', 'drive', '--no-pub', '--debug', '-d', device,
            '--driver=test_driver/ios_plugin_fonts.dart',
            '--target=integration_test/ios_plugin_font_probe_test.dart',
            f'--dart-define=OTZARIA_FONT_PROBE_INSTANCES={args.instances}',
            '--dart-define=OTZARIA_IOS_FONT_PROBE_DEVICE=simulator',
            '--dart-define=OTZARIA_IOS_FONT_PROBE_SOURCE=' + environment['sourceCommit'],
            '--dart-define=OTZARIA_IOS_FONT_PROBE_LOCK_SHA256=' + environment['lockSha256'],
        ], 3000, env=env, check=False)
        environment['drive'] = drive
        if drive.get('failures'):
            raise CommandFailure(drive)
        require(drive['returncode'] == 0 and not drive['timedOut'] and drive['groupDrained'], 'Actual Flutter Driver run failed or exceeded its deadline')
        environment['runStatus'] = 'completed'
    except (Exception, KeyboardInterrupt) as failure:
        failures.add(step, failure)
    finally:
        try:
            if environment.get('nativeSources') and not environment.get('cancelled'):
                capture_sources(commands, environment, after=True)
        except (Exception, KeyboardInterrupt) as cleanup:
            failures.add('sources-after', cleanup, cleanup=True)
        try:
            if environment.get('sourceCommit'):
                retain_source_diff(commands, environment)
        except (Exception, KeyboardInterrupt) as cleanup:
            failures.add('source-diff', cleanup, cleanup=True)
        try:
            pods = ROOT / 'ios/Podfile.lock'
            if pods.exists():
                shutil.copyfile(pods, output / 'Podfile.lock')
                environment['podfileLockSha256'] = sha256(pods)
        except (Exception, KeyboardInterrupt) as cleanup:
            failures.add('podfile-lock', cleanup, cleanup=True)
        try:
            if shutdown:
                commands.cleanup_mode = True
                try:
                    commands.run('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', shutdown],
                                 10 if environment.get('cancelled') else 60)
                finally:
                    commands.cleanup_mode = False
        except (Exception, KeyboardInterrupt) as cleanup:
            failures.add('simulator-shutdown', cleanup, cleanup=True)
        if not failures.entries:
            environment['captureStatus'] = 'complete'
        environment['error'] = failures.error
    compatibility = None
    if not failures.entries:
        try:
            paths = list((output / 'reports').glob('run-*/report.json'))
            require(len(paths) == 1, 'Exactly one complete framework report is required')
            compatibility = validate_artifacts(paths[0], environment, output)
        except (Exception, KeyboardInterrupt) as failure:
            failures.add('validation', failure)
    return report_probe(output, environment, failures, compatibility)


def main(argv=None):
    def cancelled(signum, frame):
        raise InterruptedError(f'Probe cancelled by signal {signum}')
    previous = signal.signal(signal.SIGTERM, cancelled)
    try:
        return run_probe(argv)
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == '__main__':
    sys.exit(main())
