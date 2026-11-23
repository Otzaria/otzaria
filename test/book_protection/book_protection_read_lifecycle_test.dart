import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String> fixture({int rows = 1}) async {
    final root = await Directory.systemTemp.createTemp('pr-5513-review-');
    addTearDown(() => root.delete(recursive: true));
    final path = '${root.path}/seforim.db';
    final db = sqlite3.open(path);
    try {
      db.execute(
        'CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER)',
      );
      db.execute("INSERT INTO book VALUES (1, 'ספר בדיקה', 1)");
      db.execute(
        'CREATE TABLE book_protection (bookId INTEGER PRIMARY KEY, level INTEGER)',
      );
      db.execute(
        'WITH RECURSIVE nums(n) AS (VALUES(1) UNION ALL SELECT n + 1 FROM nums WHERE n < ?) '
        'INSERT INTO book_protection (bookId, level) SELECT n, 2 FROM nums',
        [rows],
      );
    } finally {
      db.close();
    }
    return path;
  }

  test('הגבלה נשמרת כשהקריאות הזמניות האחרות תופסות את המכסה', () async {
    final path = await fixture();
    final db = MyDatabase.withPath(path, readOnly: true, official: true);
    addTearDown(db.close);
    final repository = SeforimRepository(db);
    final service = BookProtectionRepository.instance;
    service.debugRepositoryFor = (_) async => repository;
    addTearDown(service.debugReset);
    final originalTimeout = DbReadWorker.admissionTimeout;
    DbReadWorker.admissionTimeout = const Duration(milliseconds: 20);
    final gate = Completer<void>();
    final reads = List.generate(
      DbReadWorker.maxFallbackReads,
      (_) => DbReadWorker.trackTemporaryRead(() => gate.future),
    );
    int levelWhenBusy;
    try {
      levelWhenBusy = (await service.forBookId(1)).level;
    } finally {
      gate.complete();
      await Future.wait(reads);
      DbReadWorker.admissionTimeout = originalTimeout;
    }
    expect((await service.forBookId(1)).level, 2);
    expect(levelWhenBusy, 2);
  });

  test(
    'סגירת מסד מצורף אינה משאירה קריאת הגנות פעילה',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final path = await fixture(rows: 75000);
      final registry = AttachedLibraryRegistry(idleTimeout: null)
        ..update([
          AttachedLibrary(
            slug: 'review',
            displayName: 'review',
            path: path,
            priority: 0,
            status: AttachedLibraryStatus.ok,
            addedAt: DateTime(2026),
          ),
        ]);
      addTearDown(registry.closeAll);
      final repository = (await registry.repositoryFor('review'))!;
      var completed = false;
      final pending = repository.getBookProtectionTables().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      await registry.close('review');
      final completedWhenClosed = completed;
      expect((await pending).levels[1], 2);
      expect(completedWhenClosed, isTrue);
    },
  );
  test('החלפת המסד פוסלת תוצאת הגנה מהמאגר הישן', () async {
    final path = await fixture();
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue(SettingsRepository.keyDbEffectivePath, path);
    final old = _DelayedProtectionRepository(
      MyDatabase.withPath(path, readOnly: true),
    );
    final provider = SqliteDataProvider.withRepository(old);
    addTearDown(provider.dispose);
    var completed = false;
    final reading = provider.getBookProtectionTables().whenComplete(() {
      completed = true;
    });
    await old.started.future;
    await provider.closeForExternalWrite();
    try {
      old.result.complete((
        levels: {1: 1},
        banners: <int, String>{},
        booksByTitle: <String, List<({int id, int? categoryId})>>{},
      ));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
    } finally {
      await provider.reopenAfterExternalWrite();
    }
    expect((await reading)?.levels, {1: 2});
  });
}

class _DelayedProtectionRepository extends SeforimRepository {
  _DelayedProtectionRepository(super.database);

  final started = Completer<void>();
  final result = Completer<BookProtectionTables>();

  @override
  Future<BookProtectionTables> getBookProtectionTables() {
    started.complete();
    return result.future;
  }
}
