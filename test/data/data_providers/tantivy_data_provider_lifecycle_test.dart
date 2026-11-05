import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../test_helpers/memory_cache_provider.dart';

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('concurrent and repeated disposal close each engine once', () async {
    final engine = _Engine()..closeGate = Completer<void>();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    final first = provider.dispose();
    final second = provider.dispose();
    await engine.closeEntered.future;
    await _tick();
    final callsWhileClosing = List.of(engine.calls);
    engine.closeGate!.complete();
    await Future.wait([first, second]);
    await provider.dispose();

    expect(callsWhileClosing, ['close']);
    expect(engine.calls, ['close', 'dispose']);
  });

  test('disposal does not initialize an engine after a failed open', () async {
    final opening = Completer<SearchEngine>();
    var opens = 0;
    final provider = TantivyDataProvider.forTesting(
      opening.future,
      createEngine: () async {
        opens++;
        return _Engine();
      },
    );
    final failure = expectLater(provider.engine, throwsStateError);
    opening.completeError(StateError('open failed'));
    await failure;
    await _tick();
    await provider.dispose();

    expect(opens, 0);
  });

  test(
    'engine access waits for explicit reopen and gets a fresh handle',
    () async {
      final old = _Engine()..closeGate = Completer<void>();
      final replacement = _Engine();
      var opens = 0;
      final provider = TantivyDataProvider.forTesting(
        Future.value(old),
        createEngine: () async {
          opens++;
          return replacement;
        },
      );
      final disposing = provider.dispose();
      await old.closeEntered.future;
      final reopening = provider.reopenIndex(force: true);
      var ready = false;
      final reading = provider.engine.then((value) {
        ready = true;
        return value;
      });
      await _tick();
      final readyBeforeClose = ready;
      old.closeGate!.complete();
      await disposing;
      await reopening;
      final current = await reading;

      expect(readyBeforeClose, isFalse);
      expect(current, same(replacement));
      expect(current.isDisposed, isFalse);
      expect(opens, 1);
      await provider.dispose();
    },
  );

  test('a released engine stays closed until explicit reopen', () async {
    var opens = 0;
    final provider = TantivyDataProvider.forTesting(
      Future.value(_Engine()),
      createEngine: () async {
        opens++;
        return _Engine();
      },
    );
    await provider.dispose();

    await expectLater(provider.engine, throwsStateError);
    expect(opens, 0);
    await provider.reopenIndex(force: true);
    expect((await provider.engine).isDisposed, isFalse);
    expect(opens, 1);
    await provider.dispose();
  });

  test(
    'disposal does not clear a replacement assigned while closing',
    () async {
      final old = _Engine()..closeGate = Completer<void>();
      final replacement = _Engine();
      final provider = TantivyDataProvider.forTesting(Future.value(old));
      final disposing = provider.dispose();
      await old.closeEntered.future;
      provider.engine = Future.value(replacement);
      final reading = provider.engine;
      old.closeGate!.complete();
      await disposing;

      expect(await reading, same(replacement));
      expect(await provider.engine, same(replacement));
      expect(replacement.isDisposed, isFalse);
      await provider.dispose();
    },
  );

  test('cancellation still reaches the old handle while closing', () async {
    final engine = _Engine()..closeGate = Completer<void>();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    await RustSearchEngineOperations.prepareCancellation(engine);
    final disposing = provider.dispose();
    await engine.closeEntered.future;
    await provider.cancelLexicalSearch(61);
    final cancelledBeforeClose = List.of(engine.handle.cancelled);
    engine.closeGate!.complete();
    await disposing;

    expect(cancelledBeforeClose, [61]);
    expect(engine.handle.isDisposed, isTrue);
  });

  test('reopen waits for reset to release and replace its directory', () async {
    final directory = await Directory.systemTemp.createTemp('writer_reset_');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final marker = File('${directory.path}/old-index');
    await marker.writeAsString('committed');
    final old = _Engine()..closeGate = Completer<void>();
    final replacement = _Engine();
    bool? oldDirectoryAtOpen;
    final provider = TantivyDataProvider.forTesting(
      Future.value(old),
      createEngine: () async {
        oldDirectoryAtOpen = await marker.exists();
        return replacement;
      },
    );
    final resetting = provider.resetIndex(directory.path);
    await old.closeEntered.future;
    final reopening = provider.reopenIndex(force: true);
    old.closeGate!.complete();
    await resetting;
    await reopening;

    expect(oldDirectoryAtOpen, isFalse);
    expect(await provider.engine, same(replacement));
    expect(replacement.isDisposed, isFalse);
    await provider.dispose();
  });

  test('economy change during reopen applies once to the new engine', () async {
    final old = _Engine()..closeGate = Completer<void>();
    final replacement = _Engine();
    final provider = TantivyDataProvider.forTesting(
      Future.value(old),
      createEngine: () async => replacement,
    );
    final reopening = provider.reopenIndex(force: true);
    await old.closeEntered.future;
    final changing = provider.setEconomyIndexing(true);
    await _tick();
    final oldCallsWhileClosing = List.of(old.economyCalls);
    old.closeGate!.complete();
    await reopening;
    await changing;

    expect(oldCallsWhileClosing, isEmpty);
    expect(replacement.economyCalls, [true]);
    expect(provider.isEconomyIndexing, isTrue);
    await provider.dispose();
  });

  test('failed economy restore closes the writer before disposal', () async {
    final provider = TantivyDataProvider.forTesting(Future.value(_Engine()));
    await provider.setEconomyIndexing(true);
    final failed = _Engine()
      ..economyError = StateError('restore failed')
      ..closeGate = Completer<void>();
    provider.engine = Future.value(failed);
    final opening = expectLater(provider.engine, throwsStateError);
    await Future.any([failed.closeEntered.future, opening]);
    final callsBeforeClose = List.of(failed.calls);
    failed.closeGate!.complete();
    await opening;

    expect(callsBeforeClose, ['close']);
    expect(failed.calls, ['close', 'dispose']);
  });

  test('an economy update retries when its engine is being reopened', () async {
    final old = _Engine()
      ..closeGate = Completer<void>()
      ..economyGate = Completer<void>();
    final replacement = _Engine();
    final provider = TantivyDataProvider.forTesting(
      Future.value(old),
      createEngine: () async => replacement,
    );
    final changing = provider.setEconomyIndexing(true);
    final changed = expectLater(changing, completes);
    await old.economyEntered.future;
    final reopening = provider.reopenIndex(force: true);
    await old.closeEntered.future;
    old.economyGate!.completeError(StateError('writer closed'));
    await _tick();
    old.closeGate!.complete();
    await reopening;
    await changed;

    expect(replacement.economyCalls, [true]);
    expect(provider.isEconomyIndexing, isTrue);
    await provider.dispose();
  });

  test(
    'failed index deletion stays closed and a later clear can retry',
    () async {
      final root = await Directory.systemTemp.createTemp('writer_clear_');
      final index = await Directory('${root.path}/index').create();
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue(SettingsRepository.keyIndexPath, index.path);
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        '${root.path}/books',
      );
      AppPaths.debugOverrideDataRootPath('${root.path}/data');
      addTearDown(() async {
        AppPaths.debugOverrideDataRootPath(null);
        await Settings.clearCache();
        if (await root.exists()) await root.delete(recursive: true);
      });
      var opens = 0;
      final replacement = _Engine();
      final provider = TantivyDataProvider.forTesting(
        Future.value(_Engine()),
        createEngine: () async {
          opens++;
          return replacement;
        },
      );
      await IOOverrides.runWithIOOverrides(
        () =>
            expectLater(provider.clear(), throwsA(isA<FileSystemException>())),
        _LockedIndex(index.path),
      );

      expect(opens, 0);
      await expectLater(provider.engine, throwsStateError);
      await provider.clear();
      expect(opens, 1);
      expect(await provider.engine, same(replacement));
      await provider.dispose();
    },
  );
}

class _LockedIndex extends IOOverrides {
  _LockedIndex(this.path);
  final String path;

  @override
  Directory createDirectory(String directoryPath) {
    final directory = super.createDirectory(directoryPath);
    return directoryPath == path ? _LockedDirectory(directory) : directory;
  }
}

class _LockedDirectory implements Directory {
  _LockedDirectory(this.inner);
  final Directory inner;

  @override
  String get path => inner.path;

  @override
  Directory get parent => inner.parent;

  @override
  Future<bool> exists() => inner.exists();

  @override
  Future<Directory> delete({bool recursive = false}) =>
      Future.error(FileSystemException('index locked', path));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Engine implements SearchEngine {
  final calls = <String>[];
  final economyCalls = <bool>[];
  final closeEntered = Completer<void>();
  final economyEntered = Completer<void>();
  final handle = _Handle();
  Completer<void>? closeGate;
  Completer<void>? economyGate;
  Object? economyError;
  bool disposed = false;

  @override
  Future<void> closeIndexWriter() {
    if (disposed) throw StateError('engine disposed');
    calls.add('close');
    if (!closeEntered.isCompleted) closeEntered.complete();
    return closeGate?.future ?? Future<void>.value();
  }

  @override
  Future<void> setEconomyIndexing({required bool enabled}) async {
    if (disposed) throw StateError('engine disposed');
    economyCalls.add(enabled);
    if (!economyEntered.isCompleted) economyEntered.complete();
    await economyGate?.future;
    if (economyError != null) throw economyError!;
  }

  @override
  Future<LexicalCancellationHandle> lexicalCancellationHandle() async => handle;

  @override
  void dispose() {
    if (disposed) return;
    calls.add('dispose');
    disposed = true;
  }

  @override
  bool get isDisposed => disposed;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #searchExact) {
      return Future.value(<SearchResult>[]);
    }
    throw UnimplementedError('$invocation');
  }
}

class _Handle implements LexicalCancellationHandle {
  final cancelled = <int>[];
  bool disposed = false;

  @override
  void cancel({required int requestId}) {
    if (disposed) throw StateError('handle disposed');
    cancelled.add(requestId);
  }

  @override
  void dispose() => disposed = true;

  @override
  bool get isDisposed => disposed;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
