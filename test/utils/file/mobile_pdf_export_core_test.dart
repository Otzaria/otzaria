import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:otzaria/utils/file/mobile_pdf_export_core.dart';
import 'package:otzaria/utils/file/mobile_pdf_export_models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.create());
  tearDown(() => fixture.dispose());

  test('start returns a unique handle before any producer runs', () async {
    var calls = 0;
    final first = fixture.start(
      producer: (path) async {
        calls++;
        await File(path).writeAsString('%PDF-first');
      },
    );
    final second = fixture.start(
      producer: (path) async {
        calls++;
        await File(path).writeAsString('%PDF-second');
      },
    );
    expect(calls, 0);
    expect(first.id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second.id, isNot(first.id));
    await fixture.backend.waitForExports(2);
    expect(calls, 2);
    final requests = fixture.backend.requests;
    for (final request in requests) {
      expect(p.basename(p.dirname(request.sourcePath)), request.operationId);
      expect(
        p.basename(p.dirname(p.dirname(request.sourcePath))),
        mobilePdfExportDirectoryName,
      );
      expect(p.basename(request.sourcePath), request.fileName);
      expect(
        request.toMap().keys,
        unorderedEquals([
          'version',
          'operationId',
          'sourcePath',
          'fileName',
        ]),
      );
    }
    final firstRequest = requests.singleWhere(
      (item) => item.operationId == first.id,
    );
    final secondRequest = requests.singleWhere(
      (item) => item.operationId == second.id,
    );
    fixture.backend.finish(firstRequest, MobilePdfExportStatus.saved);
    expect((await first.result).status, MobilePdfExportStatus.saved);
    expect(await File(firstRequest.sourcePath).exists(), isFalse);
    expect(await File(secondRequest.sourcePath).exists(), isTrue);
    fixture.backend.finish(secondRequest, MobilePdfExportStatus.saved);
    await second.result;
  });

  test('cancel before the first microtask never creates a file', () async {
    var producerCalls = 0;
    final operation = fixture.start(producer: (_) async => producerCalls++);
    final first = operation.cancel();
    expect(identical(first, operation.cancel()), isTrue);
    await first;
    expect((await operation.result).status, MobilePdfExportStatus.cancelled);
    expect(producerCalls, 0);
    expect(fixture.temporaryCalls, 0);
    expect(fixture.backend.requests, isEmpty);
  });

  test(
    'cancel during directory lookup does not invoke producer/native',
    () async {
      final lookup = fixture.pause();
      final entered = Completer<void>();
      final coordinator = fixture.coordinator(
        temporaryDirectory: () async {
          entered.complete();
          await lookup.future;
          return fixture.directory;
        },
      );
      var calls = 0;
      final operation = fixture.start(
        coordinator: coordinator,
        producer: (_) async => calls++,
      );
      await entered.future;
      await operation.cancel();
      lookup.complete();
      expect((await operation.result).status, MobilePdfExportStatus.cancelled);
      expect(calls, 0);
      expect(await fixture.directory.list().toList(), isEmpty);
    },
  );

  test(
    'cancel waits for the producer to close its actual file handle',
    () async {
      final release = fixture.pause();
      final entered = Completer<String>();
      var callbacks = 0;
      final operation = fixture.start(
        onCancelRequested: () => callbacks++,
        producer: (path) async {
          final handle = await File(path).open(mode: FileMode.write);
          try {
            await handle.writeString('%PDF-open-handle');
            entered.complete(path);
            await release.future;
            await handle.flush();
          } finally {
            await handle.close();
          }
        },
      );
      final path = await entered.future;
      var terminal = false;
      unawaited(operation.result.then((_) => terminal = true));
      await operation.cancel();
      await operation.cancel();
      expect(callbacks, 1);
      expect(await File(path).exists(), isTrue);
      expect(terminal, isFalse);
      expect(fixture.backend.requests, isEmpty);
      release.complete();
      expect((await operation.result).status, MobilePdfExportStatus.cancelled);
      expect(await File(path).exists(), isFalse);
    },
  );

  test('native cancel ACK does not release the original source', () async {
    final operation = fixture.start();
    final request = await fixture.backend.firstExport.future;
    var terminal = false;
    unawaited(operation.result.then((_) => terminal = true));
    await operation.cancel();
    expect(fixture.backend.cancellations, [operation.id]);
    expect(terminal, isFalse);
    expect(await File(request.sourcePath).readAsString(), '%PDF-fixture');
    fixture.backend.complete(
      request,
      MobilePdfExportResult(
        operationId: operation.id,
        status: MobilePdfExportStatus.cancelled,
        residualDocument: 'content://provider/partial/7',
        residualDisplayName: 'עותק חלקי.pdf',
        cleanupStatus: MobilePdfExportCleanupStatus.failed,
        cleanupError: 'provider refused deletion',
      ),
    );
    final result = await operation.result;
    expect(result.status, MobilePdfExportStatus.cancelled);
    expect(result.residualDocument, 'content://provider/partial/7');
    expect(result.residualDisplayName, 'עותק חלקי.pdf');
    expect(result.cleanupStatus, MobilePdfExportCleanupStatus.failed);
    expect(result.cleanupError, 'provider refused deletion');
    expect(await File(request.sourcePath).exists(), isFalse);
  });

  test('an already committed native save wins over a late cancel', () async {
    fixture.backend.onCancel = (_) async => false;
    final operation = fixture.start();
    final request = await fixture.backend.firstExport.future;
    await operation.cancel();
    fixture.backend.complete(
      request,
      MobilePdfExportResult(
        operationId: operation.id,
        status: MobilePdfExportStatus.saved,
        documentUri: 'content://provider/renamed/3',
        displayName: 'ספר (2).pdf',
      ),
    );
    final result = await operation.result;
    expect(operation.isCancellationRequested, isTrue);
    expect(result.status, MobilePdfExportStatus.saved);
    expect(result.displayName, 'ספר (2).pdf');
    expect(result.documentUri, 'content://provider/renamed/3');
  });

  test(
    'late cancel after terminal never calls a disposed producer token',
    () async {
      var callbacks = 0;
      final operation = fixture.start(onCancelRequested: () => callbacks++);
      final request = await fixture.backend.firstExport.future;
      fixture.backend.finish(request, MobilePdfExportStatus.saved);
      final result = await operation.result;
      await operation.cancel();
      expect(callbacks, 0);
      expect(fixture.backend.cancellations, isEmpty);
      expect((await operation.result), same(result));
    },
  );

  test('an outstanding cancel ACK cannot delay terminal cleanup', () async {
    final ack = fixture.pause();
    fixture.backend.onCancel = (_) async {
      await ack.future;
      return true;
    };
    final operation = fixture.start();
    final request = await fixture.backend.firstExport.future;
    var acknowledged = false;
    final cancellation = operation.cancel().then((_) => acknowledged = true);
    fixture.backend.finish(request, MobilePdfExportStatus.cancelled);
    expect((await operation.result).status, MobilePdfExportStatus.cancelled);
    expect(acknowledged, isFalse);
    expect(await File(request.sourcePath).exists(), isFalse);
    ack.complete();
    await cancellation;
  });

  test(
    'cancel callback and ACK failures keep the original export alive',
    () async {
      fixture.backend.onCancel = (_) => Future.error(StateError('lost ACK'));
      final operation = fixture.start(
        onCancelRequested: () {
          throw StateError('producer cancellation callback failed');
        },
      );
      final request = await fixture.backend.firstExport.future;
      await operation.cancel();
      expect(fixture.backend.cancellations, [operation.id]);
      expect(await File(request.sourcePath).exists(), isTrue);
      fixture.backend.finish(request, MobilePdfExportStatus.saved);
      expect((await operation.result).status, MobilePdfExportStatus.saved);
    },
  );

  test(
    'producer failure preserves its cause and removes partial output',
    () async {
      late String source;
      final operation = fixture.start(
        producer: (path) async {
          source = path;
          await File(path).writeAsString('%PDF-partial');
          throw const FileSystemException('disk full');
        },
      );
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.failed);
      expect(result.errorCode, 'producer_failed');
      expect(result.errorMessage, contains('disk full'));
      expect(await File(source).exists(), isFalse);
      expect(fixture.backend.requests, isEmpty);
    },
  );

  test('empty or missing producer output never reaches native', () async {
    for (final delete in [false, true]) {
      final operation = fixture.start(
        producer: (path) async {
          if (delete) await File(path).delete();
        },
      );
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.failed);
      expect(result.errorCode, 'staging_failed');
    }
    expect(fixture.backend.requests, isEmpty);
  });

  test(
    'native exception is terminal and releases only its own child',
    () async {
      final neighbour = await Directory(
        p.join(
          fixture.directory.path,
          mobilePdfExportDirectoryName,
          'other-operation',
        ),
      ).create(recursive: true);
      final kept = File(p.join(neighbour.path, 'keep.pdf'));
      await kept.writeAsString('not owned');
      final operation = fixture.start();
      final request = await fixture.backend.firstExport.future;
      fixture.backend.fail(request, StateError('native failure after close'));
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.failed);
      expect(result.errorCode, 'native_failed');
      expect(await File(request.sourcePath).exists(), isFalse);
      expect(await kept.readAsString(), 'not owned');
    },
  );

  test(
    'native cleanup before replying is idempotent for Dart cleanup',
    () async {
      final operation = fixture.start();
      final request = await fixture.backend.firstExport.future;
      await File(request.sourcePath).parent.delete(recursive: true);
      fixture.backend.finish(request, MobilePdfExportStatus.saved);
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.saved);
      expect(result.cleanupError, isNull);
      expect(result.displayName, isNull);
    },
  );

  test(
    'staging cleanup failure never replaces saved or destination metadata',
    () async {
      final operation = fixture.start(
        coordinator: fixture.coordinator(
          deleteStagingDirectory: (_) => Future.error(
            const FileSystemException('cleanup denied'),
          ),
        ),
      );
      final request = await fixture.backend.firstExport.future;
      fixture.backend.complete(
        request,
        MobilePdfExportResult(
          operationId: operation.id,
          status: MobilePdfExportStatus.saved,
          documentUri: 'content://provider/saved/4',
          displayName: 'שם בפועל.pdf',
        ),
      );
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.saved);
      expect(result.documentUri, 'content://provider/saved/4');
      expect(result.displayName, 'שם בפועל.pdf');
      expect(result.residualDocument, isNull);
      expect(result.cleanupStatus, MobilePdfExportCleanupStatus.notNeeded);
      expect(result.cleanupError, contains('staging:'));
      expect(result.cleanupError, contains('cleanup denied'));
    },
  );

  for (final replaceDirectory in [false, true]) {
    test(
      'native staging refusal preserves replacement (directory=$replaceDirectory)',
      () async {
        final operation = fixture.start();
        final request = await fixture.backend.firstExport.future;
        final source = File(request.sourcePath);
        if (replaceDirectory) {
          await source.parent.delete(recursive: true);
          await source.parent.create();
        } else {
          await source.delete();
        }
        await source.writeAsString('replacement must survive');
        final reason = replaceDirectory
            ? 'operation_directory_replaced'
            : 'source_replaced';
        final diagnostic = 'staging_cleanup_failed: $reason';
        fixture.backend.complete(
          request,
          MobilePdfExportResult(
            operationId: operation.id,
            status: MobilePdfExportStatus.saved,
            documentUri: 'content://provider/committed',
            cleanupError: diagnostic,
          ),
        );
        final result = await operation.result;
        expect(result.status, MobilePdfExportStatus.saved);
        expect(result.documentUri, 'content://provider/committed');
        expect(result.cleanupStatus, MobilePdfExportCleanupStatus.notNeeded);
        expect(result.cleanupError, diagnostic);
        expect(await source.readAsString(), 'replacement must survive');
      },
    );
  }

  test('cleanup never removes an unexpected sibling in its child', () async {
    final operation = fixture.start();
    final request = await fixture.backend.firstExport.future;
    final sibling = File(
      p.join(File(request.sourcePath).parent.path, 'foreign.pdf'),
    );
    await sibling.writeAsString('foreign bytes');
    fixture.backend.finish(request, MobilePdfExportStatus.saved);
    final result = await operation.result;
    expect(result.status, MobilePdfExportStatus.saved);
    expect(result.cleanupError, contains('staging:'));
    expect(await sibling.readAsString(), 'foreign bytes');
    expect(await File(request.sourcePath).exists(), isFalse);
  });

  test('secondary cleanup failure preserves a producer failure', () async {
    final operation = fixture.start(
      coordinator: fixture.coordinator(
        deleteStagingDirectory: (_) {
          throw StateError('secondary cleanup');
        },
      ),
      producer: (_) => Future.error(StateError('primary producer')),
    );
    final result = await operation.result;
    expect(result.errorCode, 'producer_failed');
    expect(result.errorMessage, contains('primary producer'));
    expect(result.cleanupError, contains('secondary cleanup'));
  });

  test('a foreign result id is rejected without claiming saved', () async {
    final operation = fixture.start();
    final request = await fixture.backend.firstExport.future;
    fixture.backend.complete(
      request,
      const MobilePdfExportResult(
        operationId: 'someone-else',
        status: MobilePdfExportStatus.saved,
      ),
    );
    final result = await operation.result;
    expect(result.status, MobilePdfExportStatus.failed);
    expect(result.errorCode, 'invalid_native_result');
    expect(await File(request.sourcePath).exists(), isFalse);
  });

  test('an existing operation child is never adopted or deleted', () async {
    final lookup = fixture.pause();
    final operation = fixture.start(
      coordinator: fixture.coordinator(
        temporaryDirectory: () async {
          await lookup.future;
          return fixture.directory;
        },
      ),
    );
    final foreign = File(
      p.join(
        fixture.directory.path,
        mobilePdfExportDirectoryName,
        operation.id,
        'unrelated.pdf',
      ),
    );
    await foreign.parent.create(recursive: true);
    await foreign.writeAsString('keep me');
    lookup.complete();
    final result = await operation.result;
    expect(result.status, MobilePdfExportStatus.failed);
    expect(await foreign.readAsString(), 'keep me');
    expect(fixture.backend.requests, isEmpty);
  });

  test(
    'a source symlink is rejected without changing its target',
    () async {
      final original = File(p.join(fixture.directory.path, 'original.pdf'));
      await original.writeAsString('original bytes');
      final operation = fixture.start(
        producer: (path) async {
          await File(path).delete();
          await Link(path).create(original.path);
        },
      );
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.failed);
      expect(fixture.backend.requests, isEmpty);
      expect(await original.readAsString(), 'original bytes');
    },
    skip: Platform.isWindows
        ? 'Creating symlinks needs host privileges'
        : false,
  );

  test(
    'an export-root symlink is refused before producer or cleanup',
    () async {
      final elsewhere = await Directory(
        p.join(fixture.directory.path, 'elsewhere'),
      ).create();
      final root = Link(
        p.join(fixture.directory.path, mobilePdfExportDirectoryName),
      );
      await root.create(elsewhere.path);
      var calls = 0;
      final operation = fixture.start(producer: (_) async => calls++);
      expect((await operation.result).status, MobilePdfExportStatus.failed);
      expect(calls, 0);
      expect(await elsewhere.list().toList(), isEmpty);
      expect(await root.exists(), isTrue);
    },
    skip: Platform.isWindows
        ? 'Creating symlinks needs host privileges'
        : false,
  );

  test(
    'replacing the owned child with a link cannot delete foreign data',
    () async {
      final elsewhere = await Directory(
        p.join(fixture.directory.path, 'foreign'),
      ).create();
      final original = File(p.join(elsewhere.path, 'ספר.pdf'));
      await original.writeAsString('foreign source');
      late String childPath;
      final operation = fixture.start(
        producer: (path) async {
          final child = File(path).parent;
          childPath = child.path;
          await child.delete(recursive: true);
          await Link(child.path).create(elsewhere.path);
        },
      );
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.failed);
      expect(fixture.backend.requests, isEmpty);
      expect(
        await FileSystemEntity.type(childPath, followLinks: false),
        FileSystemEntityType.notFound,
      );
      expect(await original.readAsString(), 'foreign source');
    },
    skip: Platform.isWindows
        ? 'Creating symlinks needs host privileges'
        : false,
  );

  test(
    'a replaced root cannot redirect cleanup into a foreign directory',
    () async {
      final elsewhere = await Directory(
        p.join(fixture.directory.path, 'foreign'),
      ).create();
      late File foreign;
      final operation = fixture.start(
        producer: (path) async {
          final child = File(path).parent;
          final root = child.parent;
          foreign = File(
            p.join(elsewhere.path, p.basename(child.path), 'keep.pdf'),
          );
          await foreign.parent.create();
          await foreign.writeAsString('foreign bytes');
          await root.rename('${root.path}-original');
          await Link(root.path).create(elsewhere.path);
        },
      );
      final result = await operation.result;
      expect(result.status, MobilePdfExportStatus.failed);
      expect(result.cleanupError, contains('staging:'));
      expect(fixture.backend.requests, isEmpty);
      expect(await foreign.readAsString(), 'foreign bytes');
    },
    skip: Platform.isWindows
        ? 'Creating symlinks needs host privileges'
        : false,
  );

  test(
    'unsupported hosts never touch the filesystem or call the backend',
    () async {
      final coordinator = fixture.coordinator(
        platform: MobilePdfExportPlatform.unsupported,
      );
      expect(coordinator.isSupported, isFalse);
      final operation = fixture.start(coordinator: coordinator);
      expect((await operation.result).errorCode, 'unsupported_platform');
      expect(fixture.temporaryCalls, 0);
      expect(fixture.backend.requests, isEmpty);
    },
  );

  test('filename contract keeps Unicode without paths or oversized UTF-8', () {
    expect(safeMobilePdfFileName('ספר.PDF.pdf'), 'ספר.pdf');
    expect(safeMobilePdfFileName('  ..  '), 'document.pdf');
    expect(safeMobilePdfFileName('a/b\\c\u0000\n.pdf'), 'a_b_c__.pdf');
    for (final value in ['א' * 300, '📚' * 200, 'A' * 300]) {
      final name = safeMobilePdfFileName(value);
      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(name.endsWith('.pdf'), isTrue);
      expect(utf8.decode(utf8.encode(name)), name);
      expect(name, isNot(contains('\uFFFD')));
    }
  });
}

class _Fixture {
  _Fixture(this.directory);
  final Directory directory;
  final backend = _Backend();
  final operations = <MobilePdfExportOperation>[];
  final pauses = <Completer<void>>[];
  var temporaryCalls = 0;

  static Future<_Fixture> create() async => _Fixture(
    await Directory.systemTemp.createTemp('otzaria-mobile-export-test-'),
  );

  Completer<void> pause() {
    final value = Completer<void>();
    pauses.add(value);
    return value;
  }

  MobilePdfExportCoordinator coordinator({
    MobilePdfExportPlatform platform = MobilePdfExportPlatform.android,
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function(Directory)? deleteStagingDirectory,
  }) => MobilePdfExportCoordinator(
    platform: platform,
    backend: backend,
    temporaryDirectory:
        temporaryDirectory ??
        () async {
          temporaryCalls++;
          return directory;
        },
    deleteStagingDirectory: deleteStagingDirectory,
  );

  MobilePdfExportOperation start({
    MobilePdfExportCoordinator? coordinator,
    Future<void> Function(String)? producer,
    void Function()? onCancelRequested,
  }) {
    final operation = (coordinator ?? this.coordinator()).start(
      fileName: 'ספר.pdf',
      producer:
          producer ??
          (path) async {
            await File(path).writeAsString('%PDF-fixture');
          },
      onCancelRequested: onCancelRequested,
    );
    operations.add(operation);
    return operation;
  }

  Future<void> dispose() async {
    final cancellations = [for (final op in operations) op.cancel()];
    for (final pause in pauses) {
      if (!pause.isCompleted) pause.complete();
    }
    for (final request in backend.requests) {
      if (!backend.pending[request.operationId]!.isCompleted) {
        backend.finish(request, MobilePdfExportStatus.cancelled);
      }
    }
    await Future.wait([
      for (final op in operations) op.result,
    ]).timeout(const Duration(seconds: 5));
    await Future.wait(cancellations).timeout(const Duration(seconds: 5));
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _Backend implements MobilePdfExportBackend {
  final requests = <MobilePdfExportRequest>[];
  final cancellations = <String>[];
  final pending = <String, Completer<MobilePdfExportResult>>{};
  final firstExport = Completer<MobilePdfExportRequest>();
  final _exportCounts = <int, Completer<void>>{};
  Future<bool> Function(String)? onCancel;

  @override
  Future<MobilePdfExportResult> exportFile(MobilePdfExportRequest request) {
    requests.add(request);
    final completer = Completer<MobilePdfExportResult>();
    pending[request.operationId] = completer;
    if (!firstExport.isCompleted) firstExport.complete(request);
    _exportCounts.remove(requests.length)?.complete();
    return completer.future;
  }

  Future<void> waitForExports(int count) {
    if (requests.length >= count) return Future.value();
    return (_exportCounts[count] ??= Completer<void>()).future;
  }

  @override
  Future<bool> cancelExport(String operationId) {
    cancellations.add(operationId);
    return onCancel?.call(operationId) ?? Future.value(true);
  }

  void complete(MobilePdfExportRequest request, MobilePdfExportResult result) =>
      pending[request.operationId]!.complete(result);

  void finish(MobilePdfExportRequest request, MobilePdfExportStatus status) =>
      complete(
        request,
        MobilePdfExportResult(
          operationId: request.operationId,
          status: status,
        ),
      );

  void fail(MobilePdfExportRequest request, Object error) =>
      pending[request.operationId]!.completeError(error);
}
