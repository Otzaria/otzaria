import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:path/path.dart' as path;

class MockDataRepository extends Mock implements DataRepository {}

/// issue #4895: "חידושי הרן פסחים ט:" מגיע לקטע של הר"ן בדף ט: של "קובץ שיטות
/// קמאי על פסחים" — "פסחים" משם הספר המארח, והכתיב המלא שקול לחסר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> tokensOf(String text) => normalizeForFindRefMatch(
    text,
  ).split(' ').where((t) => t.isNotEmpty).toList();

  // tocText.text ייחודי: טקסט חוזר ("דף ט:") משתמש באותה שורה.
  int textIdOf(sqlite3.Database db, String text) {
    db.execute('INSERT OR IGNORE INTO tocText (text) VALUES (?)', [text]);
    return db.select('SELECT id FROM tocText WHERE text = ?', [
          text,
        ]).first['id']
        as int;
  }

  group('altTocFlatMatches', () {
    final ref = tokensOf('אור לארבעה עשר דף ט: חדושי הר"ן');
    final host = tokensOf('קובץ שיטות קמאי על פסחים');

    bool matches(String query, {int? maxRefTokens}) => altTocFlatMatches(
      ref,
      tokensOf(query),
      maxRefTokens: maxRefTokens,
      hostTitleWords: altTocHostTitleWords(
        tokensOf(query),
        host,
        variants: true,
      ),
      variants: true,
    );

    test('ו/י אחת בפנים המילה, בלי הכפלה — ורק כשהכתיב שבשאילתה לא נמצא', () {
      expect(AltTocQueryWord('חידושי').matches('חדושי'), isFalse);
      expect(altTocFlatMatchesAll((v) => v ? [2] : <int>[]), [2]);
      expect(altTocFlatMatchesAll((v) => v ? [2] : [1]), [1]);
      expect(
        AltTocQueryWord('חידושי', variants: true).matches('חדושי'),
        isTrue,
      );
      expect(
        AltTocQueryWord('חדושי', variants: true).matches('חידושי'),
        isTrue,
      );
      expect(AltTocQueryWord('רן', variants: true).matches('הרן'), isTrue);
      expect(
        AltTocQueryWord('דיינים', variants: true).matches('דינים'),
        isFalse,
      );
      expect(
        AltTocQueryWord('דינים', variants: true).matches('דיינים'),
        isFalse,
      );
    });

    test('מספר עברי אינו מילה שהערך מכסה', () {
      expect(AltTocQueryWord('קיט').isWord, isFalse);
      expect(AltTocQueryWord('רמב').isWord, isFalse);
      expect(AltTocQueryWord('פסחים').isWord, isTrue);
      expect(AltTocQueryWord('חדושי').isWord, isTrue);
      final query = tokensOf('פסחים קיט א');
      expect(
        altTocFlatMatches(
          tokensOf('דף קיט. ספר המצות לרמב"ם — לאוין קי"ט'),
          query,
          hostTitleWords: altTocHostTitleWords(query, host),
        ),
        isFalse,
      );
    });

    test('בדירוג רק מילים שאינן בנתיב הערך', () {
      const title = 'קובץ שיטות קמאי על נדה';
      expect(
        altTocSuppliedTitleWords({'נדה'}, title, '$title דף ב. הלכות נדה'),
        isEmpty,
      );
      expect(
        altTocSuppliedTitleWords({'נדה'}, title, '$title דף ב. רא"ה'),
        {'נדה'},
      );
    });

    test('כתיב מלא וה"א שלפני ראשי-תיבות', () {
      expect(matches('חידושי הרן ט:'), isTrue);
      expect(matches('חדושי ר"ן'), isTrue);
    });

    test('מילה משם הספר המארח משלימה את השאילתה', () {
      expect(matches('חידושי הר"ן פסחים ט:'), isTrue);
      expect(
        altTocFlatMatches(ref, tokensOf('חדושי הר"ן פסחים ט:')),
        isFalse,
      );
    });

    test('רק נושא הספר כולו ("בבא" אינו "בבא קמא")', () {
      final bavaKamma = tokensOf('קובץ שיטות קמאי על בבא קמא');
      expect(
        altTocHostTitleWords(tokensOf('ראש בבא בתרא'), bavaKamma),
        isEmpty,
      );
      expect(altTocHostTitleWords(tokensOf('ראש בבא קמא'), bavaKamma), {
        'בבא',
        'קמא',
      });
      expect(altTocHostTitleWords(tokensOf('חדושי הרן פסחים'), host), {
        'פסחים',
      });
    });

    test('שם הספר אינו מספיק בלי שתי מילים מהערך עצמו', () {
      expect(matches('חדושי פסחים'), isFalse);
      expect(matches('ט: פסחים'), isFalse);
      expect(matches('חדושי הר"ן פסחים', maxRefTokens: 9), isFalse);
    });
  });

  group('findRefs', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_host_title');
      dbPath = path.join(tempDir.path, 'seforim.db');
      final database = MyDatabase.withPath(dbPath);
      final db = await database.database;
      db.execute("INSERT INTO category (id, title, level) VALUES (7, 'ש', 0)");
      db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
      // בכורות מוקדם בסדר, כך שרק שם הספר המארח מקדים את פסחים.
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
        "filePath, fileType) VALUES "
        "(1, 7, 1, 'קובץ שיטות קמאי על בכורות', 1, '/b/1.txt', 'txt'), "
        "(2, 7, 1, 'קובץ שיטות קמאי על פסחים', 2, '/b/2.txt', 'txt'), "
        "(3, 7, 1, 'קובץ שיטות קמאי על נדה', 3, '/b/3.txt', 'txt'), "
        "(4, 7, 1, 'טור יורה דעה', 0, '/b/4.txt', 'txt'), "
        "(5, 7, 1, 'שולחן ערוך אורח חיים', 0, '/b/5.txt', 'txt'), "
        "(6, 7, 1, 'שולחן ערוך חושן משפט', 6, '/b/6.txt', 'txt')",
      );
      db.execute(
        'INSERT INTO alt_toc_structure (id, bookId, key) VALUES '
        "(1, 1, 'Chapters'), (2, 2, 'Chapters'), (3, 3, 'Chapters'), "
        "(4, 4, 'Topics'), (5, 5, 'Topics'), (6, 6, 'Topics')",
      );
      const entries = [
        (20, 3, null, 0, 'דף ב.'),
        (21, 3, 20, 1, 'הלכות נדה לרא"ה'),
        (30, 4, null, 0, 'הלכות נדה'),
        (40, 5, null, 0, 'הלכות שבת'),
        (41, 5, 40, 1, 'דינים השייכים לערב שבת'),
        (50, 6, null, 0, 'הלכות דיינים'),
        // (id, structureId, parentId, level, text)
        (1, 1, null, 0, 'הלוקח עובר חמורו'),
        (2, 1, 1, 1, 'דף ט:'),
        (3, 1, 2, 2, 'חדושי הר"ן — פסחים'),
        (10, 2, null, 0, 'אור לארבעה עשר'),
        (11, 2, 10, 1, 'דף ט:'),
        (12, 2, 11, 2, 'תוספות הרא"ש'),
        (13, 2, 11, 2, 'חדושי הר"ן'),
        (14, 2, 10, 1, 'דף י.'),
        (15, 2, 14, 2, 'חדושי הר"ן'),
      ];
      for (final (id, structureId, parentId, level, text) in entries) {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content) '
          "VALUES (?, ?, ?, 'x')",
          [id, structureId, id],
        );
        db.execute(
          'INSERT INTO alt_toc_entry '
          '(id, structureId, parentId, textId, level, lineId) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [id, structureId, parentId, textIdOf(db, text), level, id],
        );
      }
      database.close();
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // ב-Windows ה-handle משתחרר באיחור.
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
      addTearDown(repo.disposeForTesting);
      return [
        for (final r in await repo.findRefs(query))
          if (r.isAltToc) r.reference,
      ];
    }

    const pesachim = 'קובץ שיטות קמאי על פסחים אור לארבעה עשר דף ט: חדושי הר"ן';
    const bechorot =
        'קובץ שיטות קמאי על בכורות הלוקח עובר חמורו דף ט: חדושי הר"ן — פסחים';

    for (final query in ['חדושי הר"ן פסחים ט:', 'חידושי הרן פסחים ט:']) {
      test('"$query" — דף ט: של פסחים לפני ההפניה מבכורות', () async {
        expect(await globalAltToc(query), [pesachim, bechorot]);
      });
    }

    test('"דיינים" אינו "דינים"', () async {
      expect(await globalAltToc('הלכות דיינים'), [
        'שולחן ערוך חושן משפט הלכות דיינים',
      ]);
    });

    test('שם הספר שגם בנתיב הערך אינו מקדם את הספר המארח', () async {
      expect(await globalAltToc('הלכות נדה'), [
        'טור יורה דעה הלכות נדה',
        'קובץ שיטות קמאי על נדה דף ב. הלכות נדה לרא"ה',
      ]);
    });

    test('שם הספר המארח לבדו אינו מוסיף ערכים', () async {
      expect(await globalAltToc('הר"ן פסחים'), [bechorot]);
    });
  });

  test('ב-worker: אותה התאמה ואותו דירוג', () async {
    final tempDir = await Directory.systemTemp.createTemp('otzaria_host_w');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // ב-Windows ה-handle משתחרר באיחור.
      }
    });
    final database = MyDatabase.withPath(path.join(tempDir.path, 'w.db'));
    addTearDown(database.close);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'ש', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    db.execute(
      'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
      "filePath, fileType) VALUES "
      "(1, 7, 1, 'קובץ שיטות קמאי על בכורות', 1, '/b/1.txt', 'txt'), "
      "(2, 7, 1, 'קובץ שיטות קמאי על פסחים', 2, '/b/2.txt', 'txt')",
    );
    db.execute(
      'INSERT INTO alt_toc_structure (id, bookId, key) VALUES '
      "(1, 1, 'Chapters'), (2, 2, 'Chapters')",
    );
    for (final (id, structure, parent, text) in const [
      (1, 1, null, 'דף ט:'),
      (2, 1, 1, 'חדושי הר"ן — פסחים'),
      (3, 2, null, 'דף ט:'),
      (4, 2, 3, 'חדושי הר"ן'),
    ]) {
      db.execute(
        'INSERT INTO alt_toc_entry (id, structureId, parentId, textId, level) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, structure, parent, textIdOf(db, text), parent == null ? 0 : 1],
      );
    }
    final build = repository.beginAltTocFlatIndex(
      rowsPerStep: 10,
      textsPerStep: 10,
      linesPerStep: 10,
    );
    while (!await build.step()) {}
    final index = build.index;

    final query = tokensOf('חידושי הרן פסחים ט:');
    const rank = (foundationalTier: null, eraOrder: 0);
    final request = GlobalAltTocRequest(
      queryTokens: query,
      bookRanks: {
        1: (title: 'קובץ שיטות קמאי על בכורות', rank: rank),
        2: (title: 'קובץ שיטות קמאי על פסחים', rank: rank),
      },
    );
    final references = AltTocQualifiedReferences(index);
    final selected = selectGlobalAltTocMatches(
      matchAltTocFlatIndex(index, query),
      request: request,
      bookIdOf: (i) => index.bookOf(i).id,
      bookTitleOf: (i) => index.bookOf(i).title,
      orderIndexOf: (i) => index.bookOf(i).orderIndex,
      segmentOf: index.segmentOf,
      referenceOf: references.of,
    );
    expect(
      [for (final i in selected) references.of(i)],
      [
        'קובץ שיטות קמאי על פסחים דף ט: חדושי הר"ן',
        'קובץ שיטות קמאי על בכורות דף ט: חדושי הר"ן — פסחים',
      ],
    );
  });
}
