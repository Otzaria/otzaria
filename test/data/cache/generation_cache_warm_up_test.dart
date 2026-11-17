import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('קריאת דורות בוחרת דור מוקדם ומשחררת את המסד גם בשגיאה', () async {
    final tempDir = await Directory.systemTemp.createTemp('generation_rows');
    addTearDown(() => tempDir.delete(recursive: true));
    final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
    final writer = sqlite3.open(path);
    addTearDown(writer.close);
    const bookId = SeforimFixtureIds.rashiId;
    writer.execute('INSERT INTO generation VALUES (2, ?), (3, ?)', [
      CommentaryEra.chazal.hebrewName,
      CommentaryEra.modern.hebrewName,
    ]);
    writer.execute('INSERT INTO book_generation VALUES (?, 2), (?, 3)', [
      bookId,
      bookId,
    ]);

    final target = (path: path, untrusted: true, immutable: false);
    expect(await GenerationCache.readGenerationsInIsolate(target), {
      bookId: CommentaryEra.chazal.order,
    });

    writer.execute("UPDATE generation SET name = X'01' WHERE id = 1");
    expect(
      () => GenerationCache.readGenerations(target),
      throwsA(isA<TypeError>()),
    );
    writer.execute('BEGIN EXCLUSIVE');
    writer.execute('ROLLBACK');
  });

  test('חימום ממתין גם לרענון שהתחיל עם סיום הרענון הקודם', () async {
    final tempDir = await Directory.systemTemp.createTemp('generation_cache');
    final cache = GenerationCache.instance;
    final provider = SqliteDataProvider.instance;
    final previousRegistry = AttachedLibraryRegistry.instance;
    final registry = AttachedLibraryRegistry(idleTimeout: null);
    AttachedLibraryRegistry.instance = registry;
    addTearDown(() async {
      cache.clear();
      AttachedLibraryRegistry.instance = previousRegistry;
      await registry.closeAll();
      await provider.dispose();
      DbReadWorker.disposeForTesting();
      await tempDir.delete(recursive: true);
    });

    final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
    const era = CommentaryEra.rishonim;
    final db = sqlite3.open(path);
    try {
      db.execute('UPDATE generation SET name = ?', [era.hebrewName]);
    } finally {
      db.close();
    }
    final attached = AttachedLibrary(
      slug: 'lib-a',
      displayName: 'Lib A',
      path: path,
      addedAt: DateTime(2026),
    );
    registry.update([attached]);
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue(SettingsRepository.keyDbEffectivePath, path);
    await provider.initialize();

    const bookId = SeforimFixtureIds.rashiId;
    final attachedSource = BookSource.attached(attached.slug);
    await cache.warmUp();
    expect(cache.getOrderForBook(bookId, BookSource.official), era.order);
    expect(cache.getOrderForBook(bookId, attachedSource), era.order);

    registry.update([]);
    final reattached = cache.reloadAttached().then((_) {
      registry.update([attached]);
      return cache.reloadAttached();
    });
    await cache.warmUp();
    final orderAtWarmUp = cache.getOrderForBook(bookId, attachedSource);

    await reattached;
    expect(orderAtWarmUp, era.order);
  });
}
