import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';
import 'support/seeded_reference_library.dart';

typedef _Match = ({int bookId, String reference, double order});

/// צמצום התאמות ה-AltToc הגלובלי לפני שהן חוזרות לדירוג.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> prune(
    List<_Match> matches, {
    bool suppressDescendants = true,
    int cap = maxGlobalAltTocMatches,
  }) => [
    for (final m in pruneGlobalAltTocMatches<_Match>(
      matches,
      bookIdOf: (m) => m.bookId,
      referenceOf: (m) => m.reference,
      orderOf: (m) => m.order,
      suppressDescendants: suppressDescendants,
      cap: cap,
    ))
      '${m.bookId}:${m.reference}',
  ];

  test('צאצא של התאמה באותו ספר מוסר; ספר אחר וגבול מילה לא', () {
    expect(
      prune([
        (bookId: 1, reference: 'פרשת נח', order: 1),
        (bookId: 1, reference: 'פרשת נח עליה א', order: 1),
        (bookId: 1, reference: 'פרשת נחמו', order: 1),
        (bookId: 2, reference: 'פרשת נח עליה א', order: 2),
      ]),
      ['1:פרשת נח', '1:פרשת נחמו', '2:פרשת נח עליה א'],
    );
  });

  test('בלי סינון צאצאים (מסלול מילה אחת) כל ההתאמות נשמרות', () {
    expect(
      prune([
        (bookId: 1, reference: 'נח', order: 1),
        (bookId: 1, reference: 'נח א', order: 1),
      ], suppressDescendants: false),
      ['1:נח', '1:נח א'],
    );
  });

  test('מעבר לתקרה נשמרים הקודמים בסדר הספרייה, בסדר המקורי', () {
    expect(
      prune(
        [
          (bookId: 3, reference: 'א', order: 30),
          (bookId: 1, reference: 'ב', order: 10),
          (bookId: 4, reference: 'ג', order: 40),
          (bookId: 2, reference: 'ד', order: 20),
        ],
        cap: 2,
      ),
      ['1:ב', '2:ד'],
    );
  });

  test('הרשימה הסופית זהה עם צמצום ב-worker ובלעדיו', () async {
    addTearDown(resetSeededLibrary);
    seedLibrary(const [(id: 1, title: 'ספר אחר', acronyms: [])]);
    Map<String, dynamic> row(int bookId, String reference, int segment) => {
      'bookId': bookId,
      'bookTitle': 'ספר $bookId',
      'bookOrderIndex': bookId,
      'reference': reference,
      'segment': segment,
      'level': reference.split(' ').length,
      'dbLineId': segment,
    };
    final rows = [
      row(5, 'פרשת נח', 0),
      row(5, 'פרשת נח עליה א', 3),
      row(5, 'פרשת נח עליה ב', 7),
      row(6, 'פרשת נח עליה ג', 2),
    ];
    Future<List<String>> run(bool pruned) async {
      final repo = FindRefRepository(
        isReferenceBooksCacheLoaded: () => true,
        getTocEntriesForReference: (id, title, {queryTokens}) async => const [],
        getAltTocEntriesForReference: (id, title, {queryTokens}) async =>
            const [],
        searchAltTocFlatEntries: (tokens, {maxRefTokens}) async => pruned
            ? pruneGlobalAltTocMatches(
                rows,
                bookIdOf: (r) => r['bookId'] as int,
                referenceOf: (r) => r['reference'] as String,
                orderOf: (r) => (r['bookOrderIndex'] as num).toDouble(),
                suppressDescendants: maxRefTokens == null,
              )
            : rows,
        getCategoryPath: (_) async => 'ספרייה',
      );
      addTearDown(repo.dispose);
      return [
        for (final r in await repo.findRefs('פרשת נח'))
          '${r.bookId}|${r.reference}|${r.segment}',
      ];
    }

    final unpruned = await run(false);
    expect(unpruned, hasLength(2));
    expect(await run(true), unpruned);
  });

  group('ב-worker', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_alt_prune');
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // ב-Windows שחרור ה-handle של ה-worker אינו מיידי אחרי kill.
      }
    });

    test('חיפוש רב-מילי אינו מחזיר צאצאים של התאמה', () async {
      final dbPath = path.join(tempDir.path, 'seforim.db');
      final database = MyDatabase.withPath(dbPath);
      final db = await database.database;
      db.execute(
        "INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)",
      );
      db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
        "filePath, fileType) VALUES (1, 7, 1, 'בראשית', 1, '/b/a.txt', 'txt')",
      );
      db.execute(
        "INSERT INTO line (id, bookId, lineIndex, content) VALUES "
        "(100, 1, 0, 'שורה')",
      );
      db.execute(
        "INSERT INTO tocText (id, text) VALUES (1, 'פרשה נח'), "
        "(2, 'עליה א'), (3, 'פרשה נחמה')",
      );
      db.execute(
        "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (1, 1, 'p')",
      );
      db.execute(
        'INSERT INTO alt_toc_entry '
        '(id, structureId, parentId, textId, level, lineId) VALUES '
        '(900, 1, NULL, 1, 1, 100), (901, 1, 900, 2, 2, 100), '
        '(902, 1, NULL, 3, 1, 100)',
      );
      database.close();
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );

      final isolate = await FindRefDbIsolate.instance();
      addTearDown(isolate.disposeForTesting);

      List<String> refs(List<Map<String, dynamic>> rows) => [
        for (final row in rows) row['reference'] as String,
      ];
      final all = refs(
        await isolate.searchAltTocFlat(['פרשה'], maxRefTokens: 9),
      );
      expect(all, hasLength(3), reason: 'בלי סינון צאצאים: $all');
      expect(all.where((r) => r.startsWith('פרשה נח ')), isNotEmpty);

      final multiWord = refs(await isolate.searchAltTocFlat(['פרשה']));
      expect(multiWord, ['פרשה נח', 'פרשה נחמה']);
    });
  });
}
