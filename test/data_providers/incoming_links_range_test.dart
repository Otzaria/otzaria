import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/models/book_source.dart';
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
    List<String>? connectionTypes,
    List<String>? titles,
    List<String>? prefixes,
    int? limit,
  }) async => [
    for (final l in await provider.getLinksForBookRange(
      'שבת',
      1,
      'txt',
      startLineIndex: start,
      endLineIndex: end,
      incoming: incoming,
      targetBookTitles: titles,
      incomingConnectionTypes: connectionTypes,
      incomingTitlePrefixes: prefixes,
      incomingLimit: limit,
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

  test('incoming מסנן את סוג החיבור לפני החלת התקרה', () async {
    expect(
      await load(start: 0, end: 9, incoming: true, limit: 1),
      ['6<-עירובין:4 MESORAT_HASHAS ref 23'],
    );
    expect(
      await load(
        start: 0,
        end: 9,
        incoming: true,
        connectionTypes: ['reference'],
        limit: 1,
      ),
      ['6<-שבת:2 REFERENCE ref 11'],
    );
  });

  test('incoming מסנן את הספר האחר בשאילתה, לפני התקרה', () async {
    expect(await load(start: 0, end: 9, incoming: true, titles: ['שבת']), [
      '6<-שבת:2 REFERENCE ref 11',
    ]);
    expect(
      await load(start: 0, end: 9, incoming: true, prefixes: ['רש']),
      ['6<-רש"י על שבת:1 COMMENTARY ref 30'],
    );
    expect(
      await load(
        start: 0,
        end: 9,
        incoming: true,
        titles: ['שבת'],
        prefixes: ['רש'],
        limit: 1,
      ),
      hasLength(1),
    );
    expect(
      await load(start: 0, end: 9, incoming: true, titles: const []),
      isEmpty,
    );
  });

  test('סינון נכנסים תומך ביותר מאלף תחיליות', () async {
    expect(
      await load(
        start: 0,
        end: 9,
        incoming: true,
        prefixes: [
          for (var i = 0; i < 1000; i++) 'לא תואם $i',
          'רש',
        ],
        limit: 1,
      ),
      ['6<-רש"י על שבת:1 COMMENTARY ref 30'],
    );
    expect(
      await load(start: 0, end: 9, incoming: true, titles: ['שבת'], limit: 1),
      ['6<-שבת:2 REFERENCE ref 11'],
    );
    expect(await load(start: 0, end: 9, incoming: true, limit: 1), [
      '6<-עירובין:4 MESORAT_HASHAS ref 23',
    ]);
  });

  test('incoming מזהה טווח ומקור במסד מצורף בלי קטגוריות', () async {
    final dbPath = path.join(tempDir.path, 'attached.db');
    final db = sqlite3.open(dbPath);
    db.execute("""
      CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT);
      CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, heRef TEXT);
      CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER,
        targetBookId INTEGER, targetLineId INTEGER, connectionTypeId INTEGER);
      CREATE INDEX idx_link_target ON link(targetBookId, targetLineId);
      CREATE TABLE link_range (linkId INTEGER, side INTEGER, endLineId INTEGER, endLineIndex INTEGER);
      CREATE TABLE link_coverage (lineId INTEGER, linkId INTEGER, side INTEGER);
      INSERT INTO book VALUES (1, 'שבת'), (2, 'עירובין');
      INSERT INTO line VALUES (15, 1, 5, 'שבת'), (16, 1, 6, 'שבת'),
        (23, 2, 3, 'עירובין'), (24, 2, 4, 'עירובין');
      INSERT INTO connection_type VALUES (1, 'mesorat-hashas');
      INSERT INTO link VALUES (1, 2, 23, 1, 15, 1);
      INSERT INTO link_range VALUES (1, 0, 24, 4), (1, 1, 16, 6);
      INSERT INTO link_coverage VALUES (24, 1, 0), (16, 1, 1);
    """);
    db.close();

    final registry = AttachedLibraryRegistry.instance;
    final original = registry.libraries;
    addTearDown(() => registry.update(original));
    registry.update([
      AttachedLibrary(
        slug: 'attached-test',
        displayName: 'מסד מצורף',
        path: dbPath,
        addedAt: DateTime(2026),
      ),
    ]);
    final source = BookSource.attached('attached-test');
    final links = await provider.getLinksForBookRange(
      'שבת',
      0,
      'txt',
      startLineIndex: 6,
      endLineIndex: 6,
      source: source,
      incoming: true,
      incomingConnectionTypes: ['MESORAT_HASHAS'],
      incomingLimit: 2,
    );

    final link = links.single;
    expect(link.targetSource, source);
    expect(link.targetCategoryId, 0);
    expect(link.path2, 'עירובין');
    expect(link.index1, 7);
    expect(link.index2, 4);
    expect(link.index2End, 5);
    expect(link.connectionType, 'mesorat-hashas');
  });

  test('סינון כותרות נכנסות שומר השוואת Dart ותקרה במסד מצורף', () async {
    final dbPath = path.join(tempDir.path, 'attached-titles.db');
    final db = sqlite3.open(dbPath);
    db.execute("""
      CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT COLLATE NOCASE);
      CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, heRef TEXT);
      CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, sourceLineId INTEGER,
        targetBookId INTEGER, targetLineId INTEGER, connectionTypeId INTEGER);
      INSERT INTO book VALUES (1, 'שבת'), (2, 'RASHI'), (3, 'Rashi'),
        (4, '😀 טקסט');
      INSERT INTO book VALUES (5, 'ha' || char(0) || 'bet');
      INSERT INTO line VALUES (11, 1, 0, NULL), (12, 1, 1, NULL),
        (21, 2, 0, NULL), (31, 3, 0, NULL), (41, 4, 0, NULL),
        (51, 5, 0, NULL);
      INSERT INTO connection_type VALUES (1, 'REFERENCE');
      INSERT INTO link VALUES (1, 2, 21, 1, 11, 1), (2, 3, 31, 1, 11, 1),
        (3, 5, 51, 1, 11, 1), (4, 4, 41, 1, 12, 1);
    """);
    db.close();

    final registry = AttachedLibraryRegistry.instance;
    final original = registry.libraries;
    addTearDown(() => registry.update(original));
    registry.update([
      AttachedLibrary(
        slug: 'attached-titles',
        displayName: 'מסד מצורף',
        path: dbPath,
        addedAt: DateTime(2026),
      ),
    ]);
    Future<List<String>> titles({
      List<String>? exact,
      List<String>? prefixes,
      required int limit,
    }) async => [
      for (final link in await provider.getLinksForBookRange(
        'שבת',
        0,
        'txt',
        startLineIndex: 0,
        endLineIndex: 1,
        source: BookSource.attached('attached-titles'),
        incoming: true,
        targetBookTitles: exact,
        incomingTitlePrefixes: prefixes,
        incomingLimit: limit,
      ))
        link.path2,
    ];

    expect(await titles(exact: ['Rashi'], limit: 1), ['Rashi']);
    expect(await titles(prefixes: ['ha\u0000b'], limit: 1), ['ha\u0000bet']);
    expect(
      await titles(
        exact: ['Rashi'],
        prefixes: ['ha\u0000b', String.fromCharCode(0xd83d)],
        limit: 2,
      ),
      ['Rashi', 'ha\u0000bet'],
    );
    expect(
      await titles(prefixes: [String.fromCharCode(0xd83d)], limit: 1),
      ['😀 טקסט'],
    );
    expect(await titles(limit: 2), ['RASHI', 'Rashi']);
  });

  test('ברירת המחדל לא השתנתה: מסורת הש"ס השמורה בצד השני אינה בה', () async {
    final outgoing = await load(start: 0, end: 9);
    expect(outgoing.where((l) => l.contains('MESORAT_HASHAS')), isEmpty);
    expect(outgoing, contains('6<-רש"י על שבת:1 SOURCE ref 30'));
  });
}
