import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/ios_font_probe.dart';

class _RealHttpOverrides extends HttpOverrides {}

const _server = r'''
import json, sys, threading
from http.server import ThreadingHTTPServer
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[4]) / 'tool/perf_probe'))
from run_ios_plugin_fonts import FontProbeCoordinator
from apple_plugin_activity.run import Handler

root, generation, fork = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
coordinator = FontProbeCoordinator(root, generation, 'font-test-token', 'ios', 6)
coordinator.native_fork = fork
finished, receipt = threading.Event(), {}
class ObservedHandler(Handler):
    def do_POST(self):
        receipt.update(contentLength=self.headers.get('Content-Length'),
                       transferEncoding=self.headers.get('Transfer-Encoding'))
        try:
            super().do_POST()
        finally:
            finished.set()
    def send_response(self, code, message=None):
        receipt['status'] = code
        super().send_response(code, message)
server = ThreadingHTTPServer(('127.0.0.1', 0), ObservedHandler)
server.coordinator, server.daemon_threads = coordinator, True
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
print(json.dumps({'port': server.server_port}), flush=True)
if not finished.wait(10):
    raise RuntimeError('No checkpoint request reached the actual Handler')
server.shutdown()
server.server_close()
thread.join(5)
checkpoint = root / 'partial-app.json'
receipt['checkpoint'] = json.loads(checkpoint.read_text(encoding='utf-8')) if checkpoint.exists() else None
(root / 'receipt.json').write_text(json.dumps(receipt, ensure_ascii=False), encoding='utf-8')
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory repository;
  setUpAll(() async {
    repository = Directory.current.absolute;
    while (!await File(
      '${repository.path}/tool/perf_probe/run_ios_plugin_fonts.py',
    ).exists()) {
      final parent = repository.parent;
      if (parent.path == repository.path) {
        throw StateError('Cannot locate the font coordinator source');
      }
      repository = parent;
    }
  });
  for (final (name, generation, fork) in [
    ('ASCII', 'font-run', 'native-fork'),
    ('UTF-8', 'הרצה-é🧪', 'פורק-é🧪'),
  ]) {
    test('the actual coordinator accepts the $name font checkpoint', () async {
      final root = await Directory.systemTemp.createTemp('font-checkpoint-');
      addTearDown(() => root.delete(recursive: true));
      final process = await Process.start(
        Platform.isWindows ? 'python' : 'python3',
        [
          '-u',
          '-c',
          _server,
          root.path,
          generation,
          fork,
          repository.path,
        ],
        workingDirectory: repository.path,
        environment: {'PYTHONUTF8': '1', 'PYTHONIOENCODING': 'utf-8'},
      );
      final stderr = process.stderr.transform(utf8.decoder).join();
      addTearDown(() async {
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return process.exitCode.timeout(const Duration(seconds: 5));
          },
        );
      });
      final ready =
          jsonDecode(
                await process.stdout
                    .transform(utf8.decoder)
                    .transform(const LineSplitter())
                    .first
                    .timeout(const Duration(seconds: 10)),
              )
              as Map;
      Object? requestError;
      try {
        await HttpOverrides.runWithHttpOverrides(
          () => notifyIosFontProbeStarted(
            coordinator: 'http://127.0.0.1:${ready['port']}',
            token: 'font-test-token',
            generation: generation,
            nativeFork: fork,
            firstFrameRasterized: true,
          ),
          _RealHttpOverrides(),
        ).timeout(const Duration(seconds: 15));
      } catch (error) {
        requestError = error;
      }
      expect(
        await process.exitCode.timeout(const Duration(seconds: 15)),
        0,
        reason: await stderr.timeout(const Duration(seconds: 5)),
      );
      final receipt =
          jsonDecode(
                await File('${root.path}/receipt.json').readAsString(),
              )
              as Map;
      expect(receipt['status'], HttpStatus.ok, reason: jsonEncode(receipt));
      expect(requestError, isNull);
      expect(receipt['transferEncoding'], isNull);
      final checkpoint = receipt['checkpoint'] as Map;
      expect(checkpoint['runId'], generation);
      expect(checkpoint['hostPid'], pid);
      expect(checkpoint['nativeFork'], fork);
      expect(checkpoint['firstFrameRasterized'], isTrue);
      expect(checkpoint['hostExecutable'], Platform.resolvedExecutable);
      final json = jsonEncode(checkpoint);
      expect(
        int.parse(receipt['contentLength'] as String),
        utf8.encode(json).length,
      );
      if (name == 'UTF-8') {
        expect(utf8.encode(json).length, greaterThan(json.length));
      }
    });
  }
}
