"""Headless VM/checkpoint checks with mocked native Simulator commands."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest import mock

from ios_simulator_driver import SimulatorDriver, vm_identity

SEED_UDID = '11111111-2222-4333-8444-555555555555'
PRIVATE_UDID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
DEVICE_TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-18-5'


def seed_record():
    return {'udid': SEED_UDID, 'name': 'Existing user Simulator',
            'state': 'Booted', 'deviceTypeIdentifier': DEVICE_TYPE}


def private_record():
    return {'udid': PRIVATE_UDID, 'name': 'iPhone Otzaria actual OS name',
            'state': 'Booted', 'deviceTypeIdentifier': DEVICE_TYPE,
            'isAvailable': True, 'dataPath': '/actual/private/simulator/data'}


class VmFixture:
    def __init__(self, payload=None, *, status=200, raw=None):
        self.payload = payload if payload is not None else {
            'type': 'VM', 'pid': 4242, 'startTime': 1794000000123,
            'isolates': [{'id': 'isolates/17', 'number': '17'}],
        }
        self.status, self.raw, self.paths = status, raw, []
        self.before_response = lambda: None
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                fixture.paths.append(self.path)
                fixture.before_response()
                body = fixture.raw if fixture.raw is not None else json.dumps({
                    'jsonrpc': '2.0', 'result': fixture.payload,
                }).encode()
                self.send_response(fixture.status)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(
            target=lambda: self.server.serve_forever(poll_interval=0.01), daemon=True)
        self.uri = f'http://127.0.0.1:{self.server.server_port}/probe_auth-123=/'

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


class VmIdentityTest(unittest.TestCase):
    def test_rejects_unsafe_or_unauthenticated_uri_before_connecting(self):
        invalid = [
            'https://127.0.0.1:1234/auth=/',
            'http://example.com:1234/auth=/',
            'http://127.0.0.1.example.com:1234/auth=/',
            'http://localhost:1234/auth=/',
            'http://2130706433:1234/auth=/',
            'http://0.0.0.0:1234/auth=/',
            'http://user@127.0.0.1:1234/auth=/',
            'http://user:password@127.0.0.1:1234/auth=/',
            'http://127.0.0.1/auth=/',
            'http://127.0.0.1:0/auth=/',
            'http://127.0.0.1:65536/auth=/',
            'http://127.0.0.1:bad/auth=/',
            'http://127.0.0.1:1234/',
            'http://127.0.0.1:1234/auth=',
            'http://127.0.0.1:1234/auth=/another/',
            'http://127.0.0.1:1234/auth%3D/',
            'http://127.0.0.1:1234/auth=/?query=1',
            'http://127.0.0.1:1234/auth=/#fragment',
            'file:///tmp/auth/',
        ]
        for uri in invalid:
            with self.subTest(uri=uri), mock.patch(
                    'ios_simulator_driver.http.client.HTTPConnection') as connection:
                with self.assertRaises(ValueError):
                    vm_identity(uri, 1)
                connection.assert_not_called()

    def test_get_vm_keeps_the_authentication_path_and_native_identity(self):
        with VmFixture() as fixture:
            result = vm_identity(fixture.uri, 2)
            self.assertEqual(result, fixture.payload)
            self.assertEqual(fixture.paths, ['/probe_auth-123=/getVM'])

    def test_non_success_http_status_is_not_accepted_as_a_vm(self):
        with VmFixture(status=503) as fixture:
            with self.assertRaisesRegex(ValueError, 'VM identity response failed'):
                vm_identity(fixture.uri, 2)
            self.assertEqual(len(fixture.paths), 1)

    def test_oversized_or_non_json_responses_are_rejected(self):
        for body in (b'x' * 65537, b'not a JSON VM response'):
            with self.subTest(size=len(body)), VmFixture(raw=body) as fixture:
                with self.assertRaises(ValueError):
                    vm_identity(fixture.uri, 2)
                self.assertEqual(len(fixture.paths), 1)

    def test_pid_and_start_time_must_be_integers_from_a_vm_response(self):
        with VmFixture() as fixture:
            original = dict(fixture.payload)
            for changes in ({'type': 'Error'}, {'pid': None}, {'pid': True},
                            {'pid': '4242'}, {'startTime': None},
                            {'startTime': True}, {'startTime': '1794000000123'}):
                with self.subTest(changes=changes):
                    fixture.payload = {**original, **changes}
                    with self.assertRaisesRegex(ValueError, 'VM process identity'):
                        vm_identity(fixture.uri, 2)


class SimulatorCheckpointTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.coordinator = SimpleNamespace(
            terminal=queue.Queue(), run_id='fresh-generation', native_fork='locked-native-fork')
        self.calls = []

        def run(label, command, timeout, *, on_success=None):
            self.calls.append((label, command, timeout))
            if label == 'simulator-create':
                result = PRIVATE_UDID + '\n'
                if on_success is not None:
                    on_success(result)
                return result
            if label == 'simulator-private-device':
                return json.dumps({'devices': {RUNTIME: [seed_record(), private_record()]}})
            return 'com.mendelg.otzaria: 4242\n' if label == 'ios-launch' else ''

        self.driver = SimulatorDriver(
            self.directory, self.directory / 'repo', SEED_UDID,
            self.coordinator, run, time.monotonic() + 240)
        self.driver.prepare(seed_record(), RUNTIME)

    def checkpoint(self, uri, **changes):
        body = {
            'hostPid': 4242, 'runId': self.coordinator.run_id,
            'nativeFork': self.coordinator.native_fork, 'appBootToken': 'fresh-boot',
            'hostExecutable': '/owned-simulator/Runner.app/Runner',
            'vmServiceUri': uri, 'vmServiceIsolate': 'isolates/17',
            'firstFrameRasterized': True,
        }
        body.update(changes)
        (self.directory / 'partial-app.json').write_text(json.dumps(body))
        self.coordinator.terminal = queue.Queue()
        self.coordinator.terminal.put(('appCheckpoint', time.monotonic()))
        return body

    def start(self):
        return self.driver.start(
            self.directory / 'Runner.app', self.directory / 'flutter-sdk/bin/dart',
            'test_driver/ios_plugin_fonts.dart')

    def test_release_waits_for_vm_pid_and_isolate_validation(self):
        with VmFixture() as fixture:
            expected = self.checkpoint(fixture.uri)
            fixture.before_response = lambda: self.assertFalse(self.driver.release.is_set())
            command, environment = self.start()
            self.assertTrue(self.driver.release.is_set())
            self.assertIs(self.coordinator.startup_release, self.driver.release)
            self.assertEqual(self.driver.checkpoint, expected)
            self.assertEqual(command, [
                str(self.directory / 'flutter-sdk/bin/dart'),
                '--packages=' + str(self.directory / 'repo/.dart_tool/package_config.json'),
                str(self.directory / 'repo/test_driver/ios_plugin_fonts.dart'),
            ])
            self.assertEqual(environment, {'VM_SERVICE_URL': fixture.uri})
            self.assertEqual(json.loads(
                (self.directory / 'ios-vm-identity.json').read_text()), fixture.payload)
            launch = next(command for label, command, _ in self.calls if label == 'ios-launch')
            self.assertNotIn('--start-paused', launch)
            self.assertNotIn('--disable-service-auth-codes', launch)
            self.assertEqual(fixture.paths, ['/probe_auth-123=/getVM'])

    def test_launch_values_reach_only_the_launched_app_environment(self):
        received, original = {}, self.driver.run

        def run(label, command, timeout, **kwargs):
            received[label] = kwargs.pop('env', None)
            return original(label, command, timeout, **kwargs)

        self.driver.run = run
        with VmFixture() as fixture:
            self.checkpoint(fixture.uri)
            self.driver.start(self.directory / 'Runner.app', self.directory / 'flutter-sdk/bin/dart',
                              'test_driver/ios_plugin_fonts.dart',
                              launch_environment={'IOS_FONT_PROBE_TOKEN': 'launch-secret',
                                                  'OTZARIA_FONT_PROBE_INSTANCES': '5'})
        self.assertEqual(received['ios-launch']['SIMCTL_CHILD_IOS_FONT_PROBE_TOKEN'], 'launch-secret')
        self.assertEqual(received['ios-launch']['SIMCTL_CHILD_OTZARIA_FONT_PROBE_INSTANCES'], '5')
        self.assertIsNone(received['ios-install'])
        launch = next(command for label, command, _ in self.calls if label == 'ios-launch')
        self.assertNotIn('launch-secret', ' '.join(launch))

    def test_wrong_checkpoint_identity_cannot_release_or_contact_the_vm(self):
        cases = [
            {'hostPid': 4243}, {'runId': 'stale-generation'},
            {'nativeFork': 'wrong-native-fork'}, {'appBootToken': ''},
            {'hostExecutable': '/owned-simulator/Other.app/Other'},
        ]
        for changes in cases:
            with self.subTest(changes=changes), VmFixture() as fixture:
                self.checkpoint(fixture.uri, **changes)
                with self.assertRaisesRegex(ValueError, 'checkpoint is not'):
                    self.start()
                self.assertFalse(self.driver.release.is_set())
                self.assertEqual(fixture.paths, [])

    def test_missing_or_false_first_frame_evidence_cannot_contact_vm_or_release(self):
        for evidence in ({}, {'firstFrameRasterized': False},
                         {'startupFirstFrameRasterized': False},
                         {'firstFrameRasterized': False, 'startupFirstFrameRasterized': True}):
            with self.subTest(evidence=evidence), VmFixture() as fixture:
                body = self.checkpoint(fixture.uri)
                body.pop('firstFrameRasterized')
                body.update(evidence)
                (self.directory / 'partial-app.json').write_text(json.dumps(body))
                with self.assertRaises(ValueError):
                    self.start()
                self.assertFalse(self.driver.release.is_set())
                self.assertEqual(fixture.paths, [])
                self.assertFalse((self.directory / 'ios-vm-identity.json').exists())

    def test_apple_startup_first_frame_evidence_accepts_the_checkpoint(self):
        with VmFixture() as fixture:
            body = self.checkpoint(fixture.uri)
            body.pop('firstFrameRasterized')
            body['startupFirstFrameRasterized'] = True
            (self.directory / 'partial-app.json').write_text(json.dumps(body))
            _, environment = self.start()
            self.assertEqual(environment, {'VM_SERVICE_URL': fixture.uri})
            self.assertTrue(self.driver.release.is_set())
            self.assertEqual(fixture.paths, ['/probe_auth-123=/getVM'])

    def test_missing_checkpoint_vm_uri_cannot_release_the_application(self):
        self.checkpoint(None)
        with self.assertRaisesRegex(ValueError, 'no VM service URI'):
            self.start()
        self.assertFalse(self.driver.release.is_set())
        self.assertFalse((self.directory / 'ios-vm-identity.json').exists())
        self.driver.close()
        cleanup = [command for label, command, _ in self.calls
                   if label in {'simulator-shutdown', 'simulator-delete'}]
        self.assertEqual(cleanup, [
            ['xcrun', 'simctl', 'shutdown', PRIVATE_UDID],
            ['xcrun', 'simctl', 'delete', PRIVATE_UDID],
        ])

    def test_mismatched_vm_pid_or_ui_isolate_cannot_release_the_application(self):
        for changes in ({'pid': 4243}, {'isolates': []},
                        {'isolates': [{'id': 'isolates/99'}]}):
            with self.subTest(changes=changes), VmFixture() as fixture:
                fixture.payload.update(changes)
                self.checkpoint(fixture.uri)
                with self.assertRaisesRegex(ValueError, 'VM PID or UI isolate'):
                    self.start()
                self.assertFalse(self.driver.release.is_set())
                self.assertFalse((self.directory / 'ios-vm-identity.json').exists())

    def test_unsafe_checkpoint_vm_uri_cannot_open_a_network_connection(self):
        self.checkpoint('http://external.example:1234/auth=/')
        with mock.patch('ios_simulator_driver.http.client.HTTPConnection') as connection:
            with self.assertRaisesRegex(ValueError, 'authenticated loopback URI'):
                self.start()
            connection.assert_not_called()
        self.assertFalse(self.driver.release.is_set())

    def test_pid_mismatch_cleanup_deletes_only_the_private_simulator(self):
        with VmFixture() as fixture:
            fixture.payload['pid'] = 4243
            self.checkpoint(fixture.uri)
            with self.assertRaisesRegex(ValueError, 'VM PID or UI isolate'):
                self.start()
            self.assertFalse(self.driver.release.is_set())
            self.driver.close()
            self.assertTrue(self.driver.ownership['deleted'])
            cleanup = [command for label, command, _ in self.calls
                       if label in {'simulator-shutdown', 'simulator-delete'}]
            self.assertEqual(cleanup, [
                ['xcrun', 'simctl', 'shutdown', PRIVATE_UDID],
                ['xcrun', 'simctl', 'delete', PRIVATE_UDID],
            ])
            for _, command, _ in self.calls:
                self.assertNotIn(SEED_UDID, command)


class PrivateSimulatorOwnershipTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.calls, self.failures = [], {}
        self.create_output = PRIVATE_UDID + '\n'
        self.receipt_failure = None
        self.private_devices = {RUNTIME: [seed_record(), private_record()]}
        coordinator = SimpleNamespace(
            terminal=queue.Queue(), run_id='unique-run-generation', native_fork='locked-fork')

        def run(label, command, timeout, *, on_success=None):
            self.calls.append((label, command, timeout))
            if label in self.failures:
                raise self.failures[label]
            if label == 'simulator-create':
                if on_success is not None:
                    on_success(self.create_output)
                if self.receipt_failure is not None:
                    raise self.receipt_failure
                return self.create_output
            if label == 'simulator-private-device':
                return json.dumps({'devices': self.private_devices})
            return ''

        self.run, self.coordinator = run, coordinator
        self.driver = self.new_driver()

    def new_driver(self):
        return SimulatorDriver(
            self.directory, self.directory / 'repo', SEED_UDID,
            self.coordinator, self.run, time.monotonic() + 300)

    def operations(self):
        return [(label, command) for label, command, _ in self.calls]

    def assert_seed_untouched(self):
        for _, command, _ in self.calls:
            self.assertNotIn(SEED_UDID, command)
            self.assertNotIn('terminate', command)
            self.assertNotIn('launchctl', command)

    def test_copies_device_type_and_runtime_without_mutating_the_seed(self):
        seed = seed_record()
        before = dict(seed)
        self.assertEqual(self.driver.prepare(seed, RUNTIME), PRIVATE_UDID)
        self.assertEqual(seed, before)
        create = next(command for label, command, _ in self.calls
                      if label == 'simulator-create')
        self.assertEqual(create[:3], ['xcrun', 'simctl', 'create'])
        self.assertEqual(create[-2:], [DEVICE_TYPE, RUNTIME])
        self.assertIn('unique-run-generation', create[3])
        self.assertNotEqual(create[3], seed['name'])
        self.assertEqual(self.driver.device, PRIVATE_UDID)
        self.assertEqual(self.driver.ownership['seed'], SEED_UDID)
        self.assertEqual(self.driver.ownership['device'], PRIVATE_UDID)
        self.assertEqual(self.driver.ownership['deviceType'], DEVICE_TYPE)
        self.assertEqual(self.driver.ownership['runtime'], RUNTIME)
        self.assertTrue(self.driver.ownership['created'])
        self.assertTrue(self.driver.ownership['owned'])
        self.assertTrue(self.driver.ownership['booted'])
        self.assertEqual(self.driver.actual_device, private_record())
        self.assertNotEqual(self.driver.actual_device['name'], seed['name'])
        self.assertEqual(self.driver.actual_runtime, RUNTIME)
        query = next(command for label, command, _ in self.calls
                     if label == 'simulator-private-device')
        self.assertEqual(query, ['xcrun', 'simctl', 'list', 'devices', '--json'])
        self.driver.close()
        self.assert_seed_untouched()

    def test_uuid_case_variations_preserve_the_raw_os_record(self):
        for ack in (PRIVATE_UDID, PRIVATE_UDID.upper()):
            for listed in (PRIVATE_UDID, PRIVATE_UDID.upper()):
                with self.subTest(ack=ack, listed=listed):
                    self.calls.clear()
                    self.create_output = ack
                    raw = {**private_record(), 'udid': listed}
                    self.private_devices = {RUNTIME: [seed_record(), raw]}
                    self.driver = self.new_driver()
                    self.assertEqual(self.driver.prepare(seed_record(), RUNTIME), listed)
                    self.assertEqual(self.driver.device, listed)
                    self.assertEqual(self.driver.ownership['device'], listed)
                    self.assertEqual(self.driver.actual_device, raw)
                    self.assertEqual(self.driver.actual_device['udid'], listed)
                    self.driver.close()
                    self.assert_seed_untouched()

    def test_case_sensitive_xcode_destination_uses_the_verified_os_spelling(self):
        listed = PRIVATE_UDID.upper()
        raw = {**private_record(), 'udid': listed}
        self.private_devices = {RUNTIME: [seed_record(), raw]}
        destination = self.driver.prepare(seed_record(), RUNTIME)
        def xcodebuild(device):
            if device != raw['udid']:
                raise subprocess.CalledProcessError(70, ['xcodebuild', '-destination',
                    'platform=iOS Simulator,id=' + device], output='No available device matched the destination')
        xcodebuild(destination)
        self.assertEqual(self.driver.actual_device, raw)
        self.driver.close()
        self.assertEqual(self.operations()[-2:], [
            ('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', listed]),
            ('simulator-delete', ['xcrun', 'simctl', 'delete', listed]),
        ])
        self.assert_seed_untouched()

    def test_post_validation_failure_retains_the_verified_os_spelling_for_cleanup(self):
        listed = PRIVATE_UDID.upper()
        self.private_devices = {RUNTIME: [{**private_record(), 'udid': listed}]}
        failure = subprocess.TimeoutExpired(['open', '-a', 'Simulator'], 30)
        self.failures['simulator-visible'] = failure
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            self.driver.prepare(seed_record(), RUNTIME)
        self.assertIs(caught.exception, failure)
        self.driver.close()
        self.assertEqual(self.operations()[-2:], [
            ('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', listed]),
            ('simulator-delete', ['xcrun', 'simctl', 'delete', listed]),
        ])
        self.assert_seed_untouched()

    def test_duplicate_uuid_case_aliases_are_not_one_os_device(self):
        self.private_devices = {RUNTIME: [private_record(), {**private_record(), 'udid': PRIVATE_UDID.upper()}]}
        with self.assertRaisesRegex(ValueError, 'OS identity differs'):
            self.driver.prepare(seed_record(), RUNTIME)
        self.driver.close()
        self.assertTrue(self.driver.ownership['deleted'])
        self.assert_seed_untouched()

    def test_inventory_budget_accepts_observed_latency_but_preserves_deadlines(self):
        original = self.run
        for seconds, budget, expected_timeout in [(31, 300, None), (36, 300, None),
                                                   (121, 300, 120), (36, 20, 20)]:
            with self.subTest(seconds=seconds, budget=budget):
                self.calls.clear()
                clock = [1000.0]
                def timed(label, command, timeout, **kwargs):
                    result = original(label, command, timeout, **kwargs)
                    if label == 'simulator-private-device':
                        clock[0] += min(seconds, timeout)
                        if seconds > timeout:
                            raise subprocess.TimeoutExpired(command, timeout)
                    return result
                with mock.patch('ios_simulator_driver.time.monotonic', side_effect=lambda: clock[0]):
                    self.driver = self.new_driver()
                    self.driver.run = timed
                    self.driver.deadline = clock[0] + budget
                    if expected_timeout is not None:
                        with self.assertRaises(subprocess.TimeoutExpired) as caught:
                            self.driver.prepare(seed_record(), RUNTIME)
                        self.assertEqual(caught.exception.timeout, expected_timeout)
                    else:
                        self.driver.prepare(seed_record(), RUNTIME)
                        self.assertEqual(self.driver.actual_device, private_record())
                    self.driver.close()
                self.assertTrue(self.driver.ownership['deleted'])
                self.assert_seed_untouched()

    def test_missing_or_mismatched_os_identity_rejects_and_cleans_up_private_device(self):
        cases = {
            'missing': {RUNTIME: [seed_record()]},
            'wrong-runtime': {RUNTIME + '-other': [private_record()]},
            'wrong-type': {RUNTIME: [{**private_record(),
                                    'deviceTypeIdentifier': DEVICE_TYPE + '-other'}]},
            'wrong-type-uppercase': {RUNTIME: [{**private_record(), 'udid': PRIVATE_UDID.upper(),
                                              'deviceTypeIdentifier': DEVICE_TYPE + '-other'}]},
            'not-booted': {RUNTIME: [{**private_record(), 'state': 'Shutdown'}]},
            'duplicate': {RUNTIME: [private_record(), private_record()]},
        }
        for case, devices in cases.items():
            with self.subTest(case=case):
                self.calls.clear()
                self.private_devices = devices
                self.driver = self.new_driver()
                with self.assertRaisesRegex(ValueError, 'OS identity differs'):
                    self.driver.prepare(seed_record(), RUNTIME)
                self.assertNotIn('simulator-visible', [label for label, _, _ in self.calls])
                self.driver.close()
                self.assertEqual(self.operations()[-2:], [
                    ('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', PRIVATE_UDID]),
                    ('simulator-delete', ['xcrun', 'simctl', 'delete', PRIVATE_UDID]),
                ])
                self.assertTrue(self.driver.ownership['deleted'])
                self.assert_seed_untouched()

    def test_cleanup_without_prepare_never_shuts_down_or_deletes_a_device(self):
        self.driver.close()
        self.assertEqual(self.calls, [])
        self.assertTrue(self.driver.release.is_set())

    def test_start_without_a_private_simulator_cannot_install_on_the_seed(self):
        with self.assertRaisesRegex(ValueError, 'owned private Simulator'):
            self.driver.start(self.directory / 'Runner.app', '/sdk/dart', 'driver.dart')
        self.assertEqual(self.calls, [])

    def test_create_failure_never_shuts_down_or_deletes_the_seed(self):
        failure = RuntimeError('simctl create failed')
        self.failures['simulator-create'] = failure
        with self.assertRaises(RuntimeError) as caught:
            self.driver.prepare(seed_record(), RUNTIME)
        self.assertIs(caught.exception, failure)
        self.driver.close()
        self.assertEqual([label for label, _, _ in self.calls], ['simulator-create'])
        self.assertFalse(self.driver.ownership['created'])
        self.assert_seed_untouched()

    def test_create_ack_authorizes_exact_cleanup_even_when_receipt_storage_fails(self):
        failure = OSError('Could not persist the successful simctl create receipt')
        self.receipt_failure = failure
        with self.assertRaises(OSError) as caught:
            self.driver.prepare(seed_record(), RUNTIME)
        self.assertIs(caught.exception, failure)
        self.assertTrue(self.driver.ownership['created'])
        self.assertTrue(self.driver.ownership['owned'])
        self.assertFalse(self.driver.ownership['booted'])
        self.assertEqual(self.driver.device, PRIVATE_UDID)
        self.driver.close()
        self.assertEqual(self.operations(), [
            ('simulator-create', ['xcrun', 'simctl', 'create',
                                  'iPhone Otzaria unique-run-generation', DEVICE_TYPE, RUNTIME]),
            ('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', PRIVATE_UDID]),
            ('simulator-delete', ['xcrun', 'simctl', 'delete', PRIVATE_UDID]),
        ])
        self.assertTrue(self.driver.ownership['deleted'])
        self.assert_seed_untouched()

    def test_invalid_or_seed_create_receipts_cannot_authorize_cleanup(self):
        for receipt in ('not-a-uuid', SEED_UDID, SEED_UDID.upper(),
                        PRIVATE_UDID + '\n' + PRIVATE_UDID):
            with self.subTest(receipt=receipt):
                self.calls.clear()
                self.create_output = receipt
                with self.assertRaises(ValueError):
                    self.driver.prepare(seed_record(), RUNTIME)
                self.driver.close()
                self.assertEqual([label for label, _, _ in self.calls], ['simulator-create'])
                self.assertFalse(self.driver.ownership['created'])
                self.assert_seed_untouched()

    def test_boot_or_readiness_failure_still_releases_only_the_created_device(self):
        for stage in ('simulator-boot', 'simulator-bootstatus'):
            with self.subTest(stage=stage):
                self.calls.clear()
                self.failures = {stage: TimeoutError('boot boundary timed out')}
                self.driver = self.new_driver()
                with self.assertRaises(TimeoutError):
                    self.driver.prepare(seed_record(), RUNTIME)
                self.assertIsNone(self.driver.pid)
                self.driver.close()
                self.assertEqual(self.operations()[-2:], [
                    ('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', PRIVATE_UDID]),
                    ('simulator-delete', ['xcrun', 'simctl', 'delete', PRIVATE_UDID]),
                ])
                self.assertTrue(self.driver.ownership['released'])
                self.assertTrue(self.driver.ownership['deleted'])
                self.assertFalse(self.driver.ownership['owned'])
                self.assert_seed_untouched()

    def test_shutdown_failure_does_not_skip_delete_or_replace_the_first_error(self):
        self.driver.prepare(seed_record(), RUNTIME)
        failure = RuntimeError('original shutdown failure')
        self.failures['simulator-shutdown'] = failure
        self.failures['simulator-delete'] = RuntimeError('later delete failure')
        with self.assertRaises(RuntimeError) as caught:
            self.driver.close()
        self.assertIs(caught.exception, failure)
        self.assertEqual([label for label, _ in self.operations()[-2:]],
                         ['simulator-shutdown', 'simulator-delete'])
        self.assertEqual([item['stage'] for item in self.driver.ownership['cleanupErrors']],
                         ['simulator-shutdown', 'simulator-delete'])
        self.assert_seed_untouched()

    def test_successful_cleanup_is_bounded_and_idempotent_after_run_expiry(self):
        self.driver.prepare(seed_record(), RUNTIME)
        self.driver.deadline = time.monotonic() - 100
        self.driver.close()
        first = list(self.calls)
        self.driver.close()
        self.assertEqual(self.calls, first)
        self.assertEqual(self.operations()[-2:], [
            ('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', PRIVATE_UDID]),
            ('simulator-delete', ['xcrun', 'simctl', 'delete', PRIVATE_UDID]),
        ])
        for _, _, timeout in self.calls[-2:]:
            self.assertGreater(timeout, 0)
            self.assertLessEqual(timeout, 75)
        self.assert_seed_untouched()


if __name__ == '__main__':
    unittest.main()
