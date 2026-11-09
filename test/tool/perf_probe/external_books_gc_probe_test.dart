import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../../tool/perf_probe/external_books_gc_probe.dart' as probe;

/// Runs the real converter/TOC probe in a Flutter test VM (dart:ui is needed).
/// Without --dart-define inputs this is a fast CI smoke test using one book.
/// On representative Windows storage, supply a folder/file via --dart-define.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('personal-book async I/O heartbeat probe', () async {
    const requestedFile = String.fromEnvironment('OTZARIA_GC_PROBE_FILE');
    const requestedFolder = String.fromEnvironment('OTZARIA_GC_PROBE_FOLDER');
    const runs = int.fromEnvironment('OTZARIA_GC_PROBE_RUNS', defaultValue: 1);
    const maxFiles = int.fromEnvironment(
      'OTZARIA_GC_PROBE_MAX_FILES',
      defaultValue: 20000,
    );
    const maxMiB = int.fromEnvironment(
      'OTZARIA_GC_PROBE_MAX_FILE_MIB',
      defaultValue: 128,
    );

    expect(
      requestedFile.isEmpty || requestedFolder.isEmpty,
      isTrue,
      reason: 'Specify either OTZARIA_GC_PROBE_FILE or OTZARIA_GC_PROBE_FOLDER',
    );

    Directory? fixtureDir;
    var input = requestedFile.isNotEmpty ? '--file=$requestedFile' : '';
    if (requestedFolder.isNotEmpty) input = '--folder=$requestedFolder';
    if (input.isEmpty) {
      fixtureDir = await Directory.systemTemp.createTemp('book-gc-smoke-');
      final fixture = File('${fixtureDir.path}${Platform.pathSeparator}sample.md');
      await fixture.writeAsString('# Sample\nA short paragraph');
      input = '--file=${fixture.path}';
    }

    try {
      exitCode = 0;
      await probe.main([
        input,
        '--runs=$runs',
        '--max-files=$maxFiles',
        '--max-file-mib=$maxMiB',
      ]);
      expect(exitCode, 0, reason: 'Sync/async probe result mismatch');
    } finally {
      exitCode = 0;
      if (fixtureDir != null && await fixtureDir.exists()) {
        await fixtureDir.delete(recursive: true);
      }
    }
  }, timeout: const Timeout(Duration(hours: 1)));
}
