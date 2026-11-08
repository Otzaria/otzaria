"""Launch the prebuilt Simulator app without Flutter's OS log reader."""
import http.client
import json
from pathlib import Path
import queue
import re
import threading
import time
import uuid
from urllib.parse import urlsplit


def require(condition, message):
    if not condition:
        raise ValueError(message)


def vm_identity(uri, timeout):
    require(isinstance(uri, str) and all(32 < ord(char) < 127 for char in uri), 'VM service URI contains invalid characters')
    parsed = urlsplit(uri)
    require(parsed.scheme == 'http' and parsed.hostname in {'127.0.0.1', '::1'} and
            parsed.username is None and parsed.password is None and parsed.port and
            not parsed.query and not parsed.fragment and
            re.fullmatch(r'/[A-Za-z0-9_=-]+/', parsed.path),
            'VM service must retain its authenticated loopback URI')
    connection = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=timeout)
    try:
        connection.request('GET', parsed.path + 'getVM')
        response = connection.getresponse()
        body = response.read(65537)
        require(response.status == 200 and len(body) <= 65536, 'VM identity response failed or exceeded its limit')
        result = json.loads(body)['result']
        require(result.get('type') == 'VM' and type(result.get('pid')) is int and result['pid'] > 0 and
                type(result.get('startTime')) is int and result['startTime'] > 0, 'VM process identity is unavailable')
        return result
    finally:
        connection.close()


class SimulatorDriver:
    def __init__(self, directory, repository, device, coordinator, run, deadline):
        self.directory, self.repository, self.device = directory, Path(repository), device
        self.coordinator, self.run, self.deadline = coordinator, run, deadline
        self.pid = None
        self.ownership = {'seed': device, 'created': False, 'owned': False, 'booted': False,
                          'deleted': False, 'released': False}
        self.checkpoint = None
        self.release = coordinator.startup_release = threading.Event()

    def remaining(self, maximum):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('The Simulator driver boundary deadline expired')
        return min(maximum, remaining)

    def prepare(self, seed, runtime):
        require(seed['udid'] == self.device and isinstance(seed.get('deviceTypeIdentifier'), str),
                'The Simulator seed has no exact device type')
        self.ownership.update(deviceType=seed['deviceTypeIdentifier'], runtime=runtime)
        def created_acknowledged(text):
            created = str(uuid.UUID(text.strip()))
            require(created.lower() != seed['udid'].lower(), 'The private Simulator must differ from its seed')
            self.device = created
            self.ownership.update(device=created, created=True, owned=True)
        self.run('simulator-create', ['xcrun', 'simctl', 'create',
            'iPhone Otzaria ' + self.coordinator.run_id, seed['deviceTypeIdentifier'], runtime],
            self.remaining(30), on_success=created_acknowledged)
        require(self.ownership['created'], 'The private Simulator create ACK was not observed')
        created = self.device
        self.run('simulator-boot', ['xcrun', 'simctl', 'boot', created], self.remaining(60))
        self.ownership['booted'] = True
        self.run('simulator-bootstatus', ['xcrun', 'simctl', 'bootstatus', created, '-b'], self.remaining(240))
        text = self.run('simulator-private-device', ['xcrun', 'simctl', 'list', 'devices', '--json'], self.remaining(15))
        matches = [(key, device) for key, devices in json.loads(text)['devices'].items()
                   for device in devices if device['udid'] == created]
        require(len(matches) == 1 and matches[0][0] == runtime and
                matches[0][1].get('deviceTypeIdentifier') == seed['deviceTypeIdentifier'] and
                matches[0][1].get('state') == 'Booted', 'The private Simulator OS identity differs from its creation request')
        self.actual_runtime, self.actual_device = matches[0]
        self.run('simulator-visible', ['open', '-a', 'Simulator'], self.remaining(30))
        return created

    def start(self, application, dart, entrypoint):
        require(self.ownership['created'] and self.ownership['booted'], 'The application requires an owned private Simulator')
        self.run('ios-install', ['xcrun', 'simctl', 'install', self.device, str(application)], self.remaining(120))
        self.deadline = min(self.deadline, time.monotonic() + 180)
        text = self.run('ios-launch', ['xcrun', 'simctl', 'launch', self.device, 'com.mendelg.otzaria',
                        '--enable-checked-mode', '--verify-entry-points', '--disable-vm-service-publication'], self.remaining(30))
        match = re.fullmatch(r'com\.mendelg\.otzaria: ([1-9][0-9]*)', text.strip())
        require(match, 'simctl did not acknowledge the launched application PID')
        self.pid = int(match[1])
        try:
            event = self.coordinator.terminal.get(timeout=self.remaining(180))
        except queue.Empty as error:
            raise TimeoutError('No authenticated iOS app checkpoint within 180s') from error
        require(event[0] == 'appCheckpoint', 'The Simulator controller failed before the app checkpoint')
        self.coordinator.terminal.put(event)
        checkpoint = json.loads((self.directory / 'partial-app.json').read_text())
        require(checkpoint.get('hostPid') == self.pid and checkpoint.get('runId') == self.coordinator.run_id and
                checkpoint.get('nativeFork') == self.coordinator.native_fork and checkpoint.get('appBootToken') and
                Path(checkpoint.get('hostExecutable', '')).name == 'Runner', 'The checkpoint is not the launched application')
        require(checkpoint.get('firstFrameRasterized', checkpoint.get('startupFirstFrameRasterized')) is True,
                'The original Simulator app has not rasterized its first frame')
        uri = checkpoint.get('vmServiceUri')
        require(isinstance(uri, str), 'The authenticated checkpoint has no VM service URI')
        vm = vm_identity(uri, self.remaining(10))
        require(vm['pid'] == self.pid and vm.get('isolates') and
                vm['isolates'][0].get('id') == checkpoint.get('vmServiceIsolate'), 'VM PID or UI isolate differs from the launched application')
        self.checkpoint = checkpoint
        (self.directory / 'ios-vm-identity.json').write_text(json.dumps(vm, indent=2) + '\n')
        self.release.set()
        return [str(dart), '--packages=' + str(self.repository / '.dart_tool/package_config.json'),
                str(self.repository / entrypoint)], {'VM_SERVICE_URL': uri}

    def close(self):
        self.coordinator.stopping = True
        self.release.set()
        if not self.ownership['created'] or self.ownership['deleted']:
            return
        self.deadline = time.monotonic() + 75
        failure = None
        for stage, command, maximum in [
            ('simulator-shutdown', ['xcrun', 'simctl', 'shutdown', self.device], 60),
            ('simulator-delete', ['xcrun', 'simctl', 'delete', self.device], 15),
        ]:
            try:
                self.run(stage, command, self.remaining(maximum))
                if stage == 'simulator-delete':
                    self.ownership.update(deleted=True, released=True, owned=False)
            except Exception as error:
                self.ownership.setdefault('cleanupErrors', []).append({'stage': stage, 'error': str(error)})
                failure = failure or error
        if failure is not None:
            raise failure
