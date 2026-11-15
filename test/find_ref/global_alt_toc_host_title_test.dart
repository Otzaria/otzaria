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
import 'package:otzaria/utils/text/ref_key.dart';
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

    test('הרחבה בכתיב חלופי בלי שם מארח שומרת על הדף הקרוב', () {
      final query = tokensOf('חידושי הרן ב:');
      for (final reference in [
        'דף ל: חדושי הר"ן',
        'דף ב: דף ל: חדושי הר"ן',
        'דף ב. חדושי הר"ן',
      ]) {
        expect(
          altTocFlatMatches(tokensOf(reference), query, variants: true),
          isFalse,
          reason: reference,
        );
      }
      expect(
        altTocFlatMatches(tokensOf('דף ב: חדושי הר"ן'), query, variants: true),
        isTrue,
      );
      expect(
        altTocFlatMatches(tokensOf('סעיף ב חדושי הר"ן'), query, variants: true),
        isTrue,
      );
    });

    test('מספר עברי תקין בלבד, ומילות מבנה אינן ציון דף', () {
      final reference = tokensOf('דף ל:');
      for (final unit in [
        'כלל',
        'מאמר',
        'פרק',
        'משנה',
        'מישנה',
        'הילכה',
        'פסוק',
        'הלכה',
        'דין',
        'אות',
        'פסקה',
        'ס"ק',
        'סעיף קטן',
        'סעיף',
        'סימן',
        'סי',
        'חלק',
        'שער',
        'כרך',
      ]) {
        expect(
          altTocExpandedDafMatches(
            reference,
            tokensOf('חידושי הרן פסחים $unit ב'),
          ),
          isTrue,
          reason: unit,
        );
        expect(
          altTocExpandedDafMatches(
            reference,
            tokensOf('חידושי הרן פסחים $unit א ב'),
          ),
          isTrue,
          reason: unit,
        );
      }
      expect(
        altTocExpandedDafMatches(reference, tokensOf('חידושי הרן פסחים הרן')),
        isTrue,
      );
      expect(
        altTocExpandedDafMatches(
          tokensOf('דף לט:'),
          tokensOf('חידושי הרן פסחים טל:'),
        ),
        isTrue,
      );
      expect(
        altTocExpandedDafMatches(
          tokensOf('דף ב ע"ב'),
          tokensOf('חידושי הרן פסחים ב:'),
        ),
        isTrue,
      );
      expect(
        altTocExpandedDafMatches(
          tokensOf('דף ב עמוד א'),
          tokensOf('חידושי הרן פסחים ב.'),
        ),
        isTrue,
      );
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
        (60, 2, 10, 1, 'דף ב:'),
        (61, 2, 60, 2, 'חדושי הר"ן'),
        (62, 2, 60, 2, 'רבינו דוד'),
        (63, 2, null, 0, 'דף ל:'),
        (64, 2, 63, 1, 'חדושי הר"ן'),
        (65, 2, 63, 1, 'רבינו דוד'),
        (66, 2, null, 0, 'דף מ:'),
        (67, 2, 66, 1, 'חדושי הר"ן'),
        (68, 2, 66, 1, 'רבינו דוד'),
        (69, 2, 10, 1, 'דף ב.'),
        (70, 2, 69, 2, 'חדושי הר"ן'),
        (71, 2, 69, 2, 'רבינו דוד'),
        (72, 2, 66, 1, 'רבינו דוד סעיף ב'),
        (73, 2, null, 0, 'דף עא.'),
        (74, 2, 73, 1, 'חדושי הר"ן'),
        (75, 2, null, 0, 'דף עב:'),
        (76, 2, 75, 1, 'חדושי הר"ן'),
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

    for (final author in ['רבינו דוד', 'חידושי הרן']) {
      test(
        '"$author פסחים ב:" שומר את מספר הדף לפני תקרת שתי תוצאות',
        () async {
          final spelling = author == 'חידושי הרן' ? 'חדושי הר"ן' : author;
          expect(await globalAltToc('$author פסחים ב:'), [
            'קובץ שיטות קמאי על פסחים אור לארבעה עשר דף ב: $spelling',
          ]);
        },
      );
    }

    test('עמוד א ודף ללא עמוד נשמרים, וגם סעיף תחת דף אחר', () async {
      const prefix = 'קובץ שיטות קמאי על פסחים אור לארבעה עשר';
      expect(await globalAltToc('רבינו דוד פסחים ב.'), [
        '$prefix דף ב. רבינו דוד',
      ]);
      expect(
        await globalAltToc('רבינו דוד פסחים ב'),
        unorderedEquals([
          '$prefix דף ב. רבינו דוד',
          '$prefix דף ב: רבינו דוד',
        ]),
      );
      expect(await globalAltToc('רבינו דוד פסחים סעיף ב'), [
        'קובץ שיטות קמאי על פסחים דף מ: רבינו דוד סעיף ב',
      ]);
    });

    for (final (citation, daf) in [
      ('עא', 'עא.'),
      ('עב', 'עב:'),
      ('עא.', 'עא.'),
      ('עב:', 'עב:'),
      ('דף עא ע"א', 'עא.'),
      ('דף עב ע"ב', 'עב:'),
      ('דף ע"א', 'עא.'),
    ]) {
      test('מספר דף וסימן עמוד נבדלים ב"$citation"', () async {
        expect(await globalAltToc('חידושי הרן פסחים $citation'), [
          'קובץ שיטות קמאי על פסחים דף $daf חדושי הר"ן',
        ]);
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
      (5, 2, null, 'דף ב:'),
      (6, 2, 5, 'חדושי הר"ן'),
      (7, 2, 5, 'רבינו דוד'),
      (8, 2, null, 'דף ב.'),
      (9, 2, 8, 'רבינו דוד'),
      (10, 2, null, 'דף ל:'),
      (11, 2, 10, 'חדושי הר"ן'),
      (12, 2, 10, 'רבינו דוד'),
      (13, 2, null, 'דף מ:'),
      (14, 2, 13, 'חדושי הר"ן'),
      (15, 2, 13, 'רבינו דוד סעיף ב'),
      (16, 2, null, 'דף עא.'),
      (17, 2, 16, 'חדושי הר"ן'),
      (18, 2, null, 'דף עב:'),
      (19, 2, 18, 'חדושי הר"ן'),
      (20, 2, 13, 'רבינו דוד כלל א ב'),
      (21, 2, 13, 'רבינו דוד מאמר א ב'),
      (22, 2, 13, 'רבינו דוד משנה א ב'),
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

    for (final (citation, expected) in [
      ('רבינו דוד פסחים ב:', ['דף ב: רבינו דוד']),
      ('רבינו דוד פסחים ב.', ['דף ב. רבינו דוד']),
      ('רבינו דוד פסחים ב', ['דף ב: רבינו דוד', 'דף ב. רבינו דוד']),
      ('רבינו דוד פסחים דף ב:', ['דף ב: רבינו דוד']),
      ('חידושי הרן פסחים ב:', ['דף ב: חדושי הר"ן']),
      ('חידושי הרן ב:', ['דף ב: חדושי הר"ן']),
      ('חידושי הרן פסחים עא', ['דף עא. חדושי הר"ן']),
      ('חידושי הרן פסחים עב', ['דף עב: חדושי הר"ן']),
      ('חידושי הרן פסחים דף עא ע"א', ['דף עא. חדושי הר"ן']),
      ('חידושי הרן פסחים דף עב ע"ב', ['דף עב: חדושי הר"ן']),
      ('חידושי הרן פסחים דף ע"א', ['דף עא. חדושי הר"ן']),
      ('רבינו דוד פסחים סעיף ב', ['דף מ: רבינו דוד סעיף ב']),
      ('רבינו דוד פסחים כלל א ב', ['דף מ: רבינו דוד כלל א ב']),
      ('רבינו דוד פסחים מאמר א ב', ['דף מ: רבינו דוד מאמר א ב']),
      ('רבינו דוד פסחים מישנה א ב', ['דף מ: רבינו דוד משנה א ב']),
    ]) {
      final query = tokensOf(expandQueryAmudMarks(citation));
      final local = altTocFlatMatchesAll(
        (variants) => [
          for (var i = 0; i < index.length; i++)
            if (altTocFlatMatches(
              index.refTokensOf(i),
              query,
              dafCitation: parseDafCitationFromDafToken(query),
              hostTitleWords: altTocHostTitleWords(
                query,
                tokensOf(index.bookOf(i).title),
                variants: variants,
              ),
              variants: variants,
            ))
              i,
        ],
      );
      final compact = matchAltTocFlatIndex(index, query);
      expect(compact, local, reason: citation);
      expect(
        [for (final i in compact) index.referenceOf(i)],
        expected,
        reason: citation,
      );
    }

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
