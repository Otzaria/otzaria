// בדיקות למסלול יצירה ועדכון של ספר אישי במסד.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/migration/generator/generator.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'generator-create-and-process-book-test-',
    );
    database = MyDatabase.withPath(p.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<int> createCategory() => repository.insertCategory(
    const Category(title: 'ספרים אישיים', parentId: null, level: 0),
  );

  /// כותב קובץ txt עם שורה ריקה לפני heading ראשון ומחזיר את הנתיב.
  Future<String> writeTxtWithPrefix(String title) async {
    final file = File(p.join(tempDir.path, '$title.txt'));
    await file.writeAsString(
      '\n<h1>פרק א</h1>\nתוכן השורה הראשונה\n<h1>פרק ב</h1>\nתוכן השורה השנייה',
      flush: true,
    );
    return file.path;
  }

  DatabaseGenerator buildGenerator(List<String> log) => DatabaseGenerator(
    repository,
    onProgress: (_, msg) => log.add(msg),
  );

  Future<void> failLineRefInsertForBook(int bookId) async {
    final db = await database.database;
    db.execute('''
      CREATE TRIGGER fail_line_ref_insert
      BEFORE INSERT ON line_ref
      WHEN NEW.bookId = $bookId
      BEGIN SELECT RAISE(FAIL, 'injected line_ref failure'); END
    ''');
  }

  Future<void> removeLineRefInsertFailure() async {
    final db = await database.database;
    db.execute('DROP TRIGGER fail_line_ref_insert');
  }

  // ── tests ─────────────────────────────────────────────────────────────────

  test(
    '1. הכנסה ראשונה של ספר עם שורה לפני h1 לא קורסת',
    () async {
      final catId = await createCategory();
      final bookPath = await writeTxtWithPrefix('ספר בדיקה');
      final log = <String>[];
      final generator = buildGenerator(log);

      // await directly — if it throws the test fails; no need for returnsNormally
      // because the inner Future has actual await points that returnsNormally doesn't await.
      await generator.createAndProcessBook(
        bookPath,
        catId,
        insertContent: true,
      );
    },
  );

  test(
    'כשל בבניית line_ref מסיר ייבוא חדש כדי שהסריקה הבאה תנסה שוב',
    () async {
      final catId = await createCategory();
      final file = File(p.join(tempDir.path, 'ספר חדש.txt'));
      await file.writeAsString(
        '<h1>ספר חדש</h1>\n<h2>בראשית א, א</h2>\nתוכן',
        flush: true,
      );
      final db = await database.database;
      db.execute(
        'INSERT INTO db_meta (key, value) VALUES (?, ?)',
        [
          'line_ref_index_version',
          SeforimRepository.lineRefIndexVersion.toString(),
        ],
      );
      await failLineRefInsertForBook(1);

      await expectLater(
        buildGenerator(<String>[]).createAndProcessBook(
          file.path,
          catId,
          insertContent: true,
        ),
        throwsA(anything),
      );

      expect(
        db.select("SELECT 1 FROM book WHERE title = 'ספר חדש'"),
        isEmpty,
      );
      expect(db.select('SELECT 1 FROM line'), isEmpty);

      await removeLineRefInsertFailure();
      await buildGenerator(<String>[]).createAndProcessBook(
        file.path,
        catId,
        insertContent: true,
      );
      expect(db.select('SELECT 1 FROM line_ref'), isNotEmpty);
    },
  );

  test('כשל בעדכון תוכן אינו שומר מקור חדש לפני ניסיון הסריקה הבא', () async {
    final catId = await createCategory();
    final file = File(p.join(tempDir.path, 'ספר קיים.txt'));
    await file.writeAsString(
      '<h1>ספר קיים</h1>\n<h2>בראשית א, א</h2>\nתוכן',
      flush: true,
    );
    await buildGenerator(<String>[]).createAndProcessBook(
      file.path,
      catId,
      insertContent: true,
      sourceName: 'מקור ישן',
    );
    final book = (await repository.checkBookExistsInCategoryWithFileType(
      'ספר קיים',
      catId,
      'txt',
    ))!;
    final oldSourceId = book.sourceId;
    await failLineRefInsertForBook(book.id);

    await expectLater(
      buildGenerator(<String>[]).createAndProcessBook(
        file.path,
        catId,
        insertContent: true,
        sourceName: 'מקור חדש',
      ),
      throwsA(anything),
    );

    final afterFailure = await repository.checkBookExistsInCategoryWithFileType(
      'ספר קיים',
      catId,
      'txt',
    );
    expect(afterFailure!.sourceId, oldSourceId);
    expect(afterFailure.totalLines, 0);
    expect((await repository.getSourceById(oldSourceId))!.name, 'מקור ישן');
    final db = await database.database;
    expect(
      db.select('SELECT 1 FROM line WHERE bookId = ?', [book.id]),
      isEmpty,
    );
    expect(
      db.select('SELECT 1 FROM line_ref WHERE bookId = ?', [book.id]),
      isEmpty,
    );

    await expectLater(
      buildGenerator(<String>[]).createAndProcessBook(
        file.path,
        catId,
        insertContent: true,
        sourceName: 'מקור חדש',
      ),
      throwsA(anything),
    );
    expect(
      db.select('SELECT 1 FROM line WHERE bookId = ?', [book.id]),
      isEmpty,
      reason: 'כשל חוזר אינו משאיר שורות חלקיות בספר',
    );
    expect(
      db.select('SELECT 1 FROM line_ref WHERE bookId = ?', [book.id]),
      isEmpty,
      reason: 'כשל חוזר אינו משאיר מפתחות line_ref ישנים',
    );

    await removeLineRefInsertFailure();
    await buildGenerator(<String>[]).createAndProcessBook(
      file.path,
      catId,
      insertContent: true,
      sourceName: 'מקור חדש',
    );
    final afterRetry = await repository.checkBookExistsInCategoryWithFileType(
      'ספר קיים',
      catId,
      'txt',
    );
    expect(
      (await repository.getSourceById(afterRetry!.sourceId))!.name,
      'מקור חדש',
    );
    expect(
      db.select('SELECT 1 FROM line_ref WHERE bookId = ?', [book.id]),
      isNotEmpty,
    );
  });

  test(
    '2. קריאה שנייה מפיקה רק "עודכן ספר" — ללא "מדלג על כפילות"',
    () async {
      final catId = await createCategory();
      final bookPath = await writeTxtWithPrefix('ספר בדיקה');

      // הכנסה ראשונה (ספר חדש)
      final log1 = <String>[];
      await buildGenerator(
        log1,
      ).createAndProcessBook(bookPath, catId, insertContent: true);

      // הכנסה שנייה (ספר קיים → update path)
      final log2 = <String>[];
      await buildGenerator(
        log2,
      ).createAndProcessBook(bookPath, catId, insertContent: true);

      final updateMessages = log2
          .where((m) => m.contains('עודכן ספר'))
          .toList();
      final duplicateMessages = log2
          .where((m) => m.contains('מדלג על כפילות'))
          .toList();

      expect(
        updateMessages,
        hasLength(1),
        reason: 'צריכה להיות בדיוק הודעת "עודכן ספר" אחת',
      );
      expect(
        duplicateMessages,
        isEmpty,
        reason: 'לא צריכה להיות הודעת "מדלג על כפילות" אחרי update',
      );
    },
  );

  test(
    '3. המרת ספר file-backed ל-DB-backed: אין crash, רק "עודכן ספר", filePath הופך null',
    () async {
      // מדמה את מצב ה-production המדויק: ספר שנרשם כ-file-backed
      // (filePath ≠ null, totalLines = 0) לפני שהמשתמש הפעיל "הכנס תוכן לDB".
      final catId = await createCategory();
      final bookPath = await writeTxtWithPrefix('ספר המרה');

      final file = File(bookPath);
      final stat = await file.stat();

      // הכנסת ספר file-backed ישירות ל-DB, ממש כמו שה-sync הראשון עושה.
      await repository.insertExternalContentBook(
        categoryId: catId,
        title: 'ספר המרה',
        filePath: bookPath,
        fileType: 'txt',
        fileSize: stat.size,
        lastModified: stat.modified.millisecondsSinceEpoch,
        isPersonal: true,
      );

      // וידוא שהספר אכן file-backed לפני ההמרה
      final before = await repository.checkBookExistsInCategoryWithFileType(
        'ספר המרה',
        catId,
        'txt',
      );
      expect(before, isNotNull);
      expect(
        before!.isFileBacked,
        isTrue,
        reason: 'הספר צריך להיות file-backed לפני ההמרה',
      );

      // מפעיל את ה-createAndProcessBook עם insertContent=true —
      // מסלול ה-update כפי שה-generator מבצע אותו בפועל.
      final log = <String>[];
      await buildGenerator(
        log,
      ).createAndProcessBook(bookPath, catId, insertContent: true);

      // (א) הודעת progress: רק "עודכן ספר", ללא "מדלג על כפילות"
      expect(
        log.where((m) => m.contains('עודכן ספר')),
        hasLength(1),
        reason: 'צריכה להיות הודעת עדכון אחת בדיוק',
      );
      expect(
        log.where((m) => m.contains('מדלג על כפילות')),
        isEmpty,
        reason: 'לא צריכה להיות הודעת כפילות',
      );

      // (ב) הספר הפך DB-backed: filePath → null
      final after = await repository.checkBookExistsInCategoryWithFileType(
        'ספר המרה',
        catId,
        'txt',
      );
      expect(after, isNotNull);
      expect(
        after!.isFileBacked,
        isFalse,
        reason: 'לאחר insertContent=true ה-filePath צריך להיות null',
      );
    },
  );
  test('4. מעבר לרמת כותרת גבוהה סוגר הורים עמוקים ישנים', () async {
    final catId = await createCategory();
    final file = File(p.join(tempDir.path, 'עץ כותרות.txt'));
    await file.writeAsString(
      '<h1>א</h1>\n<h2>ב</h2>\n<h3>ג</h3>\n<h2>ד</h2>\n<h4>ה</h4>',
      flush: true,
    );

    await buildGenerator(<String>[]).createAndProcessBook(
      file.path,
      catId,
      insertContent: true,
    );

    final book = await repository.checkBookExistsInCategoryWithFileType(
      'עץ כותרות',
      catId,
      'txt',
    );
    expect(book, isNotNull);
    final db = await database.database;
    final row = db
        .select(
          '''
      SELECT parentText.text AS parentText
      FROM tocEntry child
      JOIN tocText childText ON childText.id = child.textId
      LEFT JOIN tocEntry parent ON parent.id = child.parentId
      LEFT JOIN tocText parentText ON parentText.id = parent.textId
      WHERE child.bookId = ? AND childText.text = ?
      ''',
          [book!.id, 'ה'],
        )
        .toMapList()
        .single;

    expect(
      row['parentText'],
      'ד',
      reason: 'h4 שאחרי h2 חדש חייב להשתייך ל-h2, לא ל-h3 מהענף הקודם',
    );
  });

  for (final body in ['גוף ההערה', 'הערה <i>מקוננת</i> זנב']) {
    test('הערה בכותרת אינה נכנסת לתוכן העניינים במסד: $body', () async {
      final catId = await createCategory();
      final file = File(p.join(tempDir.path, 'הערה בכותרת.txt'));
      await file.writeAsString(
        '<h1>הערה בכותרת</h1>\n'
        '<h2>פרק ראשון<sup class="footnote-marker">1</sup>'
        '<i class="footnote">$body</i></h2>\n'
        'תוכן',
        flush: true,
      );

      await buildGenerator(<String>[]).createAndProcessBook(
        file.path,
        catId,
        insertContent: true,
      );

      final book = await repository.checkBookExistsInCategoryWithFileType(
        'הערה בכותרת',
        catId,
        'txt',
      );
      final db = await database.database;
      final texts = db
          .select(
            'SELECT t.text FROM tocEntry e JOIN tocText t ON t.id = e.textId '
            'WHERE e.bookId = ? ORDER BY e.lineIndex',
            [book!.id],
          )
          .map((row) => row['text'])
          .toList();

      expect(texts, ['הערה בכותרת', 'פרק ראשון']);
    });
  }

  group('detectHeaderLevel', () {
    test('כותרת רגילה מזוהה, כותרת עם סימון ההדרה — לא', () {
      expect(detectHeaderLevel('<h2>פרק א</h2>'), 2);
      expect(detectHeaderLevel('<h2 class="x">פרק א</h2>'), 2);
      expect(detectHeaderLevel('<h3 data-toc="none">עיצובית</h3>'), 0);
      expect(detectHeaderLevel('טקסט רגיל'), 0);
    });

    test('אותיות גדולות, רווח מוביל ושורות קצרות — כמו הורדת אותיות מלאה', () {
      const cases = {
        '<H2>פרק</H2>': 2,
        '<h6>ו</h6>': 6,
        '<h2 DATA-TOC="NONE">עיצובית</h2>': 0,
        '<h7>לא</h7>': 0,
        ' <h2>רווח</h2>': 0,
        '<b>מודגש</b>': 0,
        'İ<h2>': 0,
        '<h': 0,
        '<': 0,
        '': 0,
      };
      cases.forEach((line, level) {
        expect(detectHeaderLevel(line), level, reason: line);
      });
    });

    test('שורת טקסט ארוכה אינה מועתקת לאותיות קטנות', () {
      final lines = List.filled(
        200,
        'ואמר רבי יוחנן <b>משום</b> רשב"י ' * 2000,
      );
      int elapsed(void Function(String) work) {
        final sw = Stopwatch()..start();
        lines.forEach(work);
        return sw.elapsedMicroseconds;
      }

      // סף יחסי: המסלול הישן עושה לפחות את העבודה של toLowerCase.
      final lowercase = elapsed((l) => l.toLowerCase());
      final detect = elapsed(detectHeaderLevel);
      expect(detect, lessThan(lowercase ~/ 5));
    });
  });
}
