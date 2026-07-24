// Integration tests for DatabaseGenerator.createAndProcessBook.
//
// Covers the exact production path that crashed in the logs:
//  a file-backed book that transitions to DB-backed when the txt file
//  starts with a prefix line before its first <h1>.
//
// Tests:
//  1. First insert with insertContent=true succeeds even when the file has
//     a prefix line before the first heading (covers the rebuildLineTocForBook fix).
//  2. Second call (update path) emits exactly one progress message containing
//     "עודכן ספר" and ZERO messages containing "מדלג על כפילות".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';
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
    tempDir.path,
    repository,
    onProgress: (_, msg) => log.add(msg),
  );

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

  group('detectHeaderLevel', () {
    test('כותרת רגילה מזוהה, כותרת עם סימון ההדרה — לא', () {
      expect(detectHeaderLevel('<h2>פרק א</h2>'), 2);
      expect(detectHeaderLevel('<h2 class="x">פרק א</h2>'), 2);
      expect(detectHeaderLevel('<h3 data-toc="none">עיצובית</h3>'), 0);
      expect(detectHeaderLevel('טקסט רגיל'), 0);
    });
  });
}
