import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:path/path.dart' as p;

/// Controlled file I/O makes the async read contract deterministic even on a
/// fast CI disk. A test that only compares converted text cannot detect a
/// regression to readAsBytesSync and the resulting isolate-group GC stall.
class _GatedFile implements File {
  _GatedFile(this.path);

  @override
  final String path;

  final started = Completer<void>();
  final response = Completer<Uint8List>();
  int asyncReadCount = 0;
  bool syncReadAttempted = false;

  @override
  Future<Uint8List> readAsBytes() {
    asyncReadCount++;
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  Uint8List readAsBytesSync() {
    syncReadAttempted = true;
    throw StateError('Synchronous file reads must not occur in this path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('async-book-read-');
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('delayed storage read yields to the event loop before bytes arrive',
      () async {
    const path = 'held.md';
    final file = _GatedFile(path);
    final pending = IOOverrides.runZoned(
      () => convertDocumentFile(path, embedImages: false),
      createFile: (requestedPath) {
        expect(requestedPath, path);
        return file;
      },
    );

    try {
      await file.started.future.timeout(const Duration(seconds: 5));
      expect(file.asyncReadCount, 1);
      expect(file.syncReadAttempted, isFalse);

      // A timer on the caller isolate must execute while the read is still
      // unresolved. The test does not rely on a slow disk or GC heuristics.
      final heartbeat = Completer<void>();
      Timer.run(() => heartbeat.complete());
      await heartbeat.future.timeout(const Duration(seconds: 5));
      expect(file.response.isCompleted, isFalse);
    } finally {
      if (!file.response.isCompleted) {
        file.response.complete(Uint8List.fromList(utf8.encode('# פרק\nטקסט')));
      }
    }

    final actual = await pending.timeout(const Duration(seconds: 5));
    expect(actual, contains('פרק'));
  });

  test('an asynchronous read failure is propagated without sync fallback',
      () async {
    const path = 'vanished.md';
    final file = _GatedFile(path);
    final pending = IOOverrides.runZoned(
      () => convertDocumentFile(path),
      createFile: (_) => file,
    );
    await file.started.future.timeout(const Duration(seconds: 5));
    final assertion = expectLater(
      pending,
      throwsA(isA<FileSystemException>()),
    );
    file.response.completeError(FileSystemException('disappeared', path));
    await assertion;
    expect(file.asyncReadCount, 1);
    expect(file.syncReadAttempted, isFalse);
  });

  test('success and conversion failure both release the file on disk',
      () async {
    final good = File(p.join(tempDir.path, 'good.md'));
    await good.writeAsString('# פרק\nטקסט');
    expect(await convertDocumentFile(good.path), contains('פרק'));
    await good.delete();
    expect(await good.exists(), isFalse);

    final corrupt = File(p.join(tempDir.path, 'broken.wbk'));
    await corrupt.writeAsString('not a Word document');
    await expectLater(
      convertDocumentFile(corrupt.path),
      throwsA(isA<UnsupportedDocumentFormatException>()),
    );
    // Explicitly check removal: swallowing a Windows tearDown lock would
    // conceal an open file handle left by the converter.
    await corrupt.delete();
    expect(await corrupt.exists(), isFalse);
  });

  test('multi-megabyte document retains byte conversion semantics',
      () async {
    final source = Uint8List(2 * 1024 * 1024);
    for (var i = 0; i < source.length; i++) {
      source[i] = i % 80 == 79 ? 0x0a : 0x61;
    }
    final file = File(p.join(tempDir.path, 'large.txt'));
    await file.writeAsBytes(source);

    final expected = convertDocumentBytesSync(
      source,
      'large',
      format: DocumentFormat.txt,
      embedImages: false,
      path: file.path,
    );
    final actual = await Isolate.run(
      () => convertDocumentFile(file.path, embedImages: false),
    );
    expect(actual, expected);
  });
}
