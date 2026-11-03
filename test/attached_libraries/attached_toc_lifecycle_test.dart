import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

AttachedLibrary _library(String path) => AttachedLibrary(
  slug: 'a',
  displayName: 'a',
  path: path,
  priority: 0,
  status: AttachedLibraryStatus.ok,
  addedAt: DateTime(2026),
);

AttachedDbJob<void> _holdWorker(SendPort started) => (repository) async {
  await repository.getBookTocs(SeforimFixtureIds.bereshitId);
  Isolate.current.addOnExitListener(started);
  started.send('opened');
  return Completer<void>().future;
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String dbPath;
  late AttachedLibraryRegistry registry;
  final worker = AttachedFindRefWorker.instance;
  const bookId = SeforimFixtureIds.bereshitId;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await worker.reset();
    root = await Directory.systemTemp.createTemp('attached_toc_');
    dbPath = SeforimFixtureDb.create(root, SeforimFixtureVariant.full);
    registry = AttachedLibraryRegistry(idleTimeout: null)
      ..update([_library(dbPath)]);
  });

  tearDown(() async {
    await registry.closeAll();
    await root.delete(recursive: true);
  });

  test('קריאה שהחלה לפני שחרור אינה פותחת חיבור אחריו', () async {
    final repository = (await registry.repositoryFor('a'))!;
    expect(await repository.getBookTocs(bookId), isNotEmpty);
    final pending = readBookTocEntries(repository, bookId);
    final rejected = expectLater(pending, throwsStateError);
    await registry.close('a');
    await rejected;
    expect(repository.database.isOpen, isFalse);
    await expectLater(readBookTocEntries(repository, bookId), throwsStateError);
    expect(
      await readBookTocEntries((await registry.repositoryFor('a'))!, bookId),
      isNotEmpty,
    );
  });

  for (final release in ['close', 'closeAll', 'update']) {
    test('$release מבטל TOC שממתין בתור ומשחרר את קובץ המסד', () async {
      final repository = (await registry.repositoryFor('a'))!;
      final events = ReceivePort();
      final messages = StreamIterator(events);
      addTearDown(() async {
        await messages.cancel();
        events.close();
      });
      final held = worker.run(
        dbPath,
        immutable: false,
        version: '',
        job: _holdWorker(events.sendPort),
      );
      final heldRejected = expectLater(held, throwsStateError);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, 'opened');
      final pending = readBookTocEntries(repository, bookId);
      final rejected = expectLater(pending, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      switch (release) {
        case 'close':
          await registry.close('a');
        case 'closeAll':
          await registry.closeAll();
        case 'update':
          registry.update([]);
          await registry.close('a');
      }
      // מחיקה ב-Windows מאמתת שהסגירה עצמה שחררה את הקובץ.
      File(dbPath).deleteSync();
      await Future.wait([heldRejected, rejected]);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, isNull, reason: 'ה-worker יצא ושחרר את חיבוריו');
      await expectLater(
        readBookTocEntries(repository, bookId),
        throwsStateError,
      );
      dbPath = SeforimFixtureDb.create(root, SeforimFixtureVariant.full);
      registry.update([_library(dbPath)]);
      final fresh = (await registry.repositoryFor('a'))!;
      expect(fresh, isNot(same(repository)));
      expect(await readBookTocEntries(fresh, bookId), isNotEmpty);
    });
  }

  for (final release in ['reset', 'close']) {
    test('$release ממתין ליציאת worker שכבר החל להיסגר', () async {
      final repository = (await registry.repositoryFor('a'))!;
      expect(await readBookTocEntries(repository, bookId), isNotEmpty);
      var exited = false;
      final first = worker.reset().then((_) => exited = true);
      if (release == 'reset') {
        await worker.reset();
      } else {
        await registry.close('a');
      }
      expect(exited, isTrue);
      await registry.close('a');
      File(dbPath).deleteSync();
      await first;
    });
  }

  test('שינוי נתיב פוסל את המאגר הישן וקורא TOC מהקובץ החדש', () async {
    final old = (await registry.repositoryFor('a'))!;
    expect(await readBookTocEntries(old, bookId), isNotEmpty);
    final other = await Directory('${root.path}/other').create();
    final replacement = SeforimFixtureDb.create(
      other,
      SeforimFixtureVariant.full,
    );
    registry.update([_library(replacement)]);
    await expectLater(readBookTocEntries(old, bookId), throwsStateError);
    final fresh = (await registry.repositoryFor('a'))!;
    expect(fresh.database.path, replacement);
    expect(await readBookTocEntries(fresh, bookId), isNotEmpty);
  });

  test('סגירת סרק מאפשרת לאותו מאגר לקרוא שוב', () async {
    await registry.closeAll();
    registry = AttachedLibraryRegistry(idleTimeout: const Duration(minutes: 1))
      ..update([_library(dbPath)]);
    final repository = (await registry.repositoryFor('a'))!;
    final expected = await repository.getBookTocs(bookId);
    await registry.closeIdle(
      now: DateTime.now().add(const Duration(minutes: 2)),
    );
    expect(repository.database.isOpen, isFalse);
    expect(await readBookTocEntries(repository, bookId), expected);
  });
}
