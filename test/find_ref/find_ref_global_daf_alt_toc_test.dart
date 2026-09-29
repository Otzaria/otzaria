import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

class MockDataRepository extends Mock implements DataRepository {}

/// ציטוט דף בלי שם ספר עובר ב-AltToc הגלובלי: "ב" של "דף יב" / של כותרת-משנה
/// או של הלכה בירושלמי אינו דף ב — ההתאמה נבדקת מול כותרת הדף הקרובה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  Future<void> seed(String dbFile) async {
    final database = MyDatabase.withPath(dbFile);
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'ש', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
      "filePath, fileType) VALUES "
      "(1, 7, 1, 'ברכות', 1, '/b/1.txt', 'txt'), "
      "(2, 7, 1, 'ירושלמי ברכות', 2, '/b/2.txt', 'txt'), "
      "(3, 7, 1, 'בראשית', 3, '/b/3.txt', 'txt'), "
      "(4, 7, 1, 'קרן אורה על חולין', 4, '/b/4.txt', 'txt'), "
      "(5, 7, 1, 'ראשון לציון על סוכה', 5, '/b/5.txt', 'txt')",
    );
    db.execute(
      'INSERT INTO alt_toc_structure (id, bookId, key) VALUES '
      "(1, 1, 'Chapters'), (2, 2, 'Daf'), (3, 3, 'Parasha'), (4, 4, 'Chapters'), "
      "(5, 5, 'Chapters')",
    );
    const entries = [
      // (id, structureId, parentId, level, text)
      (1, 1, null, 0, 'מאימתי'),
      (2, 1, 1, 1, 'דף ב.'),
      (3, 1, 1, 1, 'דף ב:'),
      (4, 1, 1, 1, 'דף ה.'),
      (5, 1, 1, 1, 'דף ה:'),
      (6, 1, 1, 1, 'דף יב.'),
      (7, 1, 6, 2, 'ב'),
      (10, 2, null, 0, 'דף ה'),
      (11, 2, 10, 1, 'הלכה ב'),
      (12, 2, null, 0, 'דף ב'),
      (13, 2, 12, 1, 'הלכה א'),
      (20, 3, null, 0, 'נח'),
      (21, 3, 20, 1, 'עליה ב'),
      (30, 4, null, 0, 'אלו טרפות'),
      (31, 4, 30, 1, 'דף מג עמוד א'),
      (32, 4, 30, 1, 'דף מג עמוד ב'),
      (40, 5, null, 0, 'פרק א'),
      (41, 5, 40, 1, 'דף ב ע"ב'),
    ];
    for (final (id, structureId, parentId, level, text) in entries) {
      // שורה נפרדת לכל ערך — אחרת ה-dedupe לפי segment מאחד אותם.
      db.execute(
        "INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, ?, ?, 'x')",
        [id, structureId, id],
      );
      db.execute('INSERT INTO tocText (id, text) VALUES (?, ?)', [id, text]);
      db.execute(
        'INSERT INTO alt_toc_entry '
        '(id, structureId, parentId, textId, level, lineId) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [id, structureId, parentId, id, level, id],
      );
    }
    database.close();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_global_daf');
    dbPath = path.join(tempDir.path, 'seforim.db');
    await seed(dbPath);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ב-Windows ה-handle של ה-worker משתחרר באיחור.
    }
  });

  Future<List<String>> globalAltToc(String query) async {
    final database = MyDatabase.withPath(dbPath, readOnly: true);
    addTearDown(database.close);
    final seforim = SeforimRepository(database);
    await seforim.ensureInitialized();
    final repo = FindRefRepository(
      dataRepository: MockDataRepository(),
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      searchReferenceBooks: (query, {int limit = 50}) =>
          const <ReferenceBookHit>[],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllAltTocFlatEntries: seforim.getAllAltTocFlatEntries,
    );
    final results = await repo.findRefs(query);
    return [
      for (final r in results)
        if (r.isAltToc) r.reference,
    ]..sort();
  }

  group('AltToc גלובלי — ציטוט דף בלי שם ספר', () {
    test('"דף ב." אינו תופס את "דף יב." ותת-כותרתו או הלכה בירושלמי', () async {
      expect(await globalAltToc('דף ב.'), equals(['ברכות מאימתי דף ב.']));
    });

    test('"דף ה:" מחזיר רק את דף ה עמוד ב', () async {
      expect(await globalAltToc('דף ה:'), equals(['ברכות מאימתי דף ה:']));
    });

    test('"מאימתי דף ב" — שם לפני "דף" לא מבטל את ההתאמה המיקומית', () async {
      expect(
        await globalAltToc('מאימתי דף ב'),
        equals(['ברכות מאימתי דף ב.', 'ברכות מאימתי דף ב:']),
      );
    });

    test('כותרת "דף מג עמוד א" תואמת ל-"דף מג."', () async {
      expect(
        await globalAltToc('דף מג.'),
        equals(['קרן אורה על חולין אלו טרפות דף מג עמוד א']),
      );
    });

    test('כותרת "דף ב ע"ב" תואמת ל-"דף ב:"', () async {
      expect(
        await globalAltToc('דף ב:'),
        equals(['ברכות מאימתי דף ב:', 'ראשון לציון על סוכה פרק א דף ב ע"ב']),
      );
    });

    test('"נח ב" (בלי "דף") נשאר התאמת טוקנים רגילה', () async {
      expect(await globalAltToc('נח ב'), equals(['בראשית נח עליה ב']));
    });

    test('ה-worker מסנן באותה סמנטיקה', () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      final isolate = await FindRefDbIsolate.instance();
      addTearDown(isolate.disposeForTesting);

      final rows = await isolate.searchAltTocFlat(const ['דף', 'ב', 'א']);
      expect(rows.map((r) => r['reference']), equals(['מאימתי דף ב.']));
    });
  });

  test(
    'AltToc של ספר: "<פרק> דף ב" מחזיר רק את דף ב, לא כל עמודי ב בפרק',
    () async {
      final database = MyDatabase.withPath(dbPath, readOnly: true);
      addTearDown(database.close);
      final seforim = SeforimRepository(database);
      await seforim.ensureInitialized();

      final rows = await seforim.getAltTocEntriesForReference(
        1,
        'ברכות',
        queryTokens: const ['מאימתי', 'דף', 'ב'],
      );
      expect(
        rows.map((r) => r['reference']).toList()..sort(),
        equals(['מאימתי דף ב.', 'מאימתי דף ב:']),
      );
    },
  );

  test('AltToc של ספר: כותרת "דף מג עמוד א" תואמת לציון עמוד', () async {
    final database = MyDatabase.withPath(dbPath, readOnly: true);
    addTearDown(database.close);
    final seforim = SeforimRepository(database);
    await seforim.ensureInitialized();

    Future<List<Object?>> refs(List<String> tokens) async => [
      for (final r in await seforim.getAltTocEntriesForReference(
        4,
        'קרן אורה על חולין',
        queryTokens: tokens,
      ))
        r['reference'],
    ];

    const amudA = ['אלו טרפות דף מג עמוד א'];
    expect(await refs(const ['אלו', 'טרפות', 'דף', 'מג', 'א']), amudA);
    expect(await refs(const ['דף', 'מג', 'עמוד', 'א']), amudA);
  });
}
