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

/// צמצום התאמות ה-AltToc הגלובלי לפני שהן חוזרות לדירוג: הרשימה הסופית
/// חייבת להיות זהה לזו שבלי הצמצום.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AltTocResultKey key(int bookId, String reference, {int segment = 0}) => (
    bookId: bookId,
    title: 'ספר $bookId',
    segment: segment,
    reference: reference,
  );

  List<String> prune(
    List<AltTocResultKey> matches, {
    bool suppressDescendants = true,
    List<AltTocResultKey> occupied = const [],
    List<String> queryTokens = const ['פרשת'],
    int perBookCap = maxGlobalAltTocMatchesPerBook,
  }) => [
    for (final m in pruneGlobalAltTocMatches<AltTocResultKey>(
      matches,
      keyOf: (m) => m,
      queryTokens: queryTokens,
      suppressDescendants: suppressDescendants,
      occupied: occupied,
      perBookCap: perBookCap,
    ))
      '${m.bookId}:${m.reference}',
  ];

  test('צאצא של התאמה באותו ספר מוסר; ספר אחר וגבול מילה לא', () {
    expect(
      prune([
        key(1, 'פרשת נח', segment: 1),
        key(1, 'פרשת נח עליה א', segment: 2),
        key(1, 'פרשת נחמו', segment: 3),
        key(2, 'פרשת נח עליה א', segment: 1),
      ]),
      ['1:פרשת נח', '1:פרשת נחמו', '2:פרשת נח עליה א'],
    );
  });

  test('בלי סינון צאצאים (מסלול מילה אחת) כל ההתאמות נשמרות', () {
    expect(
      prune([
        key(1, 'נח', segment: 1),
        key(1, 'נח א', segment: 2),
      ], suppressDescendants: false),
      ['1:נח', '1:נח א'],
    );
  });

  test('אב שנזרק ככפילות אינו מסתיר את צאצאיו', () {
    // האב חולק שורה עם תוצאה שכבר נאספה (TOC באותו ספר) — הדירוג זורק אותו.
    expect(
      prune(
        [
          key(1, 'פרשת נח', segment: 10),
          key(1, 'פרשת נח עליה א', segment: 11),
        ],
        occupied: [key(1, 'ספר 1 פרק ו', segment: 10)],
      ),
      ['1:פרשת נח עליה א'],
    );
    // וכך גם מול התאמה גלובלית קודמת באותה שורה.
    expect(
      prune([
        key(1, 'הפטרה', segment: 5),
        key(1, 'פרשת נח', segment: 5),
        key(1, 'פרשת נח עליה א', segment: 6),
      ]),
      ['1:הפטרה', '1:פרשת נח עליה א'],
    );
  });

  test('תקרה פר-ספר לפי סדר הדירוג בתוך הספר, בלי לגעת בספר אחר', () {
    expect(
      prune(
        [
          key(1, 'סעיף א ארוך מאוד', segment: 1),
          key(1, 'סעיף א דף ב', segment: 9),
          key(1, 'סעיף א', segment: 5),
          key(1, 'סעיף א', segment: 3),
          key(2, 'סעיף א ארוך מאוד', segment: 1),
        ],
        queryTokens: const ['סעיף', 'א'],
        suppressDescendants: false,
        perBookCap: 2,
      ),
      ['1:סעיף א דף ב', '1:סעיף א', '2:סעיף א ארוך מאוד'],
      reason: 'הכפילות נזרקת, שתי הקצרות נשמרות, והפלט בסדר המקורי',
    );
    expect(
      prune(
        [
          key(1, 'עא ארוך', segment: 1),
          key(1, 'דף עא', segment: 2),
          key(1, 'עא', segment: 3),
        ],
        queryTokens: const ['שבת', 'עא', 'ב'],
        suppressDescendants: false,
        perBookCap: 1,
      ),
      ['1:דף עא'],
      reason: 'בציון דף, ערך עם "דף" קודם גם כשהוא ארוך יותר',
    );
  });

  group('הרשימה הסופית זהה עם צמצום ב-worker ובלעדיו', () {
    tearDown(resetSeededLibrary);

    Map<String, dynamic> row(
      int bookId,
      String reference,
      int segment, {
      double? order,
      String? title,
    }) => {
      'bookId': bookId,
      'bookTitle': title ?? 'ספר $bookId',
      'bookOrderIndex': order ?? bookId.toDouble(),
      'reference': reference,
      'segment': segment,
      'level': reference.split(' ').length,
      'dbLineId': segment,
    };

    Future<List<String>> run(
      String query,
      List<Map<String, dynamic>> rows, {
      required bool pruned,
      Map<int, List<Map<String, dynamic>>> tocByBookId = const {},
    }) async {
      final repo = FindRefRepository(
        isReferenceBooksCacheLoaded: () => true,
        getAltStructureBookIds: () async => const [],
        getTocEntriesForReference: (id, title, {queryTokens}) async =>
            tocByBookId[id] ?? const [],
        getAltTocEntriesForReference: (id, title, {queryTokens}) async =>
            const [],
        searchAltTocFlatEntries:
            (tokens, {maxRefTokens, occupied = const []}) async => pruned
            ? pruneGlobalAltTocMatches(
                rows,
                keyOf: altTocRowKey,
                queryTokens: tokens,
                suppressDescendants: maxRefTokens == null,
                occupied: occupied,
              )
            : rows,
        getCategoryPath: (_) async => 'ספרייה',
      );
      addTearDown(repo.dispose);
      return [
        for (final r in await repo.findRefs(query))
          '${r.bookId}|${r.reference}|${r.segment}',
      ];
    }

    test('צאצאים באותו ספר ובספר אחר', () async {
      seedLibrary(const [(id: 1, title: 'ספר אחר', acronyms: [])]);
      final rows = [
        row(5, 'פרשת נח', 0),
        row(5, 'פרשת נח עליה א', 3),
        row(5, 'פרשת נח עליה ב', 7),
        row(6, 'פרשת נח עליה ג', 2),
      ];
      final unpruned = await run('פרשת נח', rows, pruned: false);
      expect(unpruned, hasLength(2));
      expect(await run('פרשת נח', rows, pruned: true), unpruned);
    });

    test('אב שהתנגש בשורת TOC של אותו ספר — צאצאיו נשארים', () async {
      // כמו "לך לך": הספר עצמו תואם, ה-TOC שלו ברמה 1 חולק שורה עם האב.
      seedLibrary(const [(id: 5, title: 'פרשת השבוע', acronyms: [])]);
      final toc = {
        5: [
          {'reference': 'פרשת השבוע נח', 'segment': 10, 'level': 1},
        ],
      };
      final rows = [
        row(5, 'פרשת נח', 10, title: 'פרשת השבוע'),
        row(5, 'פרשת נח עליה א', 11, title: 'פרשת השבוע'),
        row(5, 'פרשת נח עליה ב', 12, title: 'פרשת השבוע'),
      ];
      final unpruned = await run(
        'פרשת נח',
        rows,
        pruned: false,
        tocByBookId: toc,
      );
      expect(unpruned, contains('5|פרשת השבוע פרשת נח עליה א|11'));
      expect(
        await run('פרשת נח', rows, pruned: true, tocByBookId: toc),
        unpruned,
      );
    });

    test('ספר מאוחר בסדר אך ספר-יסוד אינו נחתך בגלל ספרים קודמים', () async {
      // כמו "סעיף א": ספר מוקדם עם מאות התאמות, וספר יסוד מאוחר שמדורג ראשון.
      seedLibrary(
        const [
          (id: 1, title: 'ספר אחר', acronyms: []),
          (id: 6, title: 'ספר שישי', acronyms: []),
          (id: 7, title: 'ספר שביעי', acronyms: []),
        ],
        categoryPaths: {7: 'תנ"ך, תורה'},
      );
      final rows = [
        for (var i = 0; i < 600; i++) row(6, 'סימן $i סעיף א', i, order: 1),
        for (var i = 0; i < 50; i++) row(7, 'פרק $i סעיף א', i, order: 900),
      ];
      final unpruned = await run('סעיף א', rows, pruned: false);
      expect(unpruned.first, startsWith('7|'));
      expect(await run('סעיף א', rows, pruned: true), unpruned);
    });
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
        "(100, 1, 0, 'שורה'), (101, 1, 1, 'שורה'), (102, 1, 2, 'שורה')",
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
        '(900, 1, NULL, 1, 1, 100), (901, 1, 900, 2, 2, 101), '
        '(902, 1, NULL, 3, 1, 102)',
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
