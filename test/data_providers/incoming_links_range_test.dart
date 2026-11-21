import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// קישורים נכנסים לתוספים (issue #5271): הקישורים שספרים אחרים שומרים אל
/// חלון בספר, כפי שנשמרו — במסד שבו הקישור נשמר רק בכיוון אחד.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  final provider = DatabaseLibraryProvider.instance;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_incoming_links');
    database = MyDatabase.withPath(
      path.join(tempDir.path, DatabaseConstants.databaseFileName),
    );
    final repository = SeforimRepository(database);
    await provider.sqliteProvider.dispose();
    provider.clearCache();
    await repository.ensureInitialized();
    final sourceId = await repository.insertSource('local', -10);
    final catId = await repository.insertCategory(
      const migration_models.Category(title: 'כללי', parentId: null, level: 0),
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      tempDir.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
    await provider.initialize();

    final db = await database.database;
    db.execute(
      "INSERT OR IGNORE INTO connection_type (name) VALUES ('MESORAT_HASHAS'), ('COMMENTARY'), ('REFERENCE')",
    );
    int type(String name) =>
        db.select('SELECT id FROM connection_type WHERE name = ?', [
              name,
            ]).first['id']
            as int;
    for (final (id, title) in [
      (1, 'שבת'),
      (2, 'עירובין'),
      (3, 'רש"י על שבת'),
    ]) {
      db.execute(
        "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines, filePath, fileType) VALUES ($id, $catId, $sourceId, '${title.replaceAll("'", "''")}', $id, 10, '/tmp/$id.txt', 'txt')",
      );
    }
    // (lineId, bookId, lineIndex)
    for (final (id, bookId, index) in [
      (15, 1, 5),
      (11, 1, 1),
      (23, 2, 3),
      (30, 3, 0),
    ]) {
      db.execute(
        "INSERT INTO line (id, bookId, lineIndex, content, heRef) VALUES ($id, $bookId, $index, 'x', 'ref $id')",
      );
    }
    void link(int sb, int sl, int tb, int tl, String t) => db.execute(
      'INSERT INTO link (sourceBookId, sourceLineId, targetBookId, targetLineId, connectionTypeId) VALUES ($sb, $sl, $tb, $tl, ${type(t)})',
    );
    link(2, 23, 1, 15, 'MESORAT_HASHAS'); // עירובין 3 → שבת 5
    link(3, 30, 1, 15, 'COMMENTARY'); // רש"י 0 → שבת 5
    link(1, 11, 1, 15, 'REFERENCE'); // שבת 1 → שבת 5
  });

  tearDown(() async {
    await provider.sqliteProvider.dispose();
    provider.clearCache();
    database.close();
    await tempDir.delete(recursive: true);
  });

  Future<List<String>> load({
    required int start,
    required int end,
    bool incoming = false,
  }) async => [
    for (final l in await provider.getLinksForBookRange(
      'שבת',
      1,
      'txt',
      startLineIndex: start,
      endLineIndex: end,
      incoming: incoming,
    ))
      '${l.index1}<-${l.path2}:${l.index2} ${l.connectionType} ${l.heRef}',
  ];

  test(
    'incoming מחזיר כל קישור שנשמר אל החלון, בסוג המקורי ובכיוון השמור',
    () async {
      expect(
        await load(start: 0, end: 9, incoming: true),
        unorderedEquals([
          '6<-עירובין:4 MESORAT_HASHAS ref 23',
          '6<-רש"י על שבת:1 COMMENTARY ref 30',
          '6<-שבת:2 REFERENCE ref 11',
        ]),
      );
    },
  );

  test('incoming מוגבל לחלון בצד היעד', () async {
    expect(await load(start: 6, end: 9, incoming: true), isEmpty);
    expect(await load(start: 1, end: 1, incoming: true), isEmpty);
  });

  test('ברירת המחדל לא השתנתה: מסורת הש"ס השמורה בצד השני אינה בה', () async {
    final outgoing = await load(start: 0, end: 9);
    expect(outgoing.where((l) => l.contains('MESORAT_HASHAS')), isEmpty);
    expect(outgoing, contains('6<-רש"י על שבת:1 SOURCE ref 30'));
  });
}
