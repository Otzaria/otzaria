import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

/// fixture של קטלוג פרויקט השו"ת, בסכמה שהגשר בונה.
String _createCatalog(Directory directory) {
  final file = path.join(directory.path, 'responsa_catalog.db');
  final db = sqlite3.open(file);
  db.execute('''
    CREATE TABLE books (
      book_pk        INTEGER PRIMARY KEY,
      external_key   TEXT NOT NULL UNIQUE,
      title          TEXT NOT NULL,
      norm_title     TEXT NOT NULL,
      ref_path       TEXT NOT NULL,
      open_ref       TEXT NOT NULL,
      volume         TEXT,
      category       TEXT,
      topics         TEXT,
      tree_param     INTEGER,
      source_version INTEGER NOT NULL
    )
  ''');
  db.execute(
    'CREATE TABLE db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );
  db.execute(
    'INSERT INTO books(external_key, title, norm_title, ref_path, open_ref,'
    ' category, topics, tree_param, source_version)'
    " VALUES('1524', 'יבמות', 'יבמות',"
    " 'מפרשים ופוסקים על הבבלי > רא\"ש > יבמות', 'רא\"ש יבמות',"
    " 'מפרשים ופוסקים על הבבלי', '', 12345, 25)",
  );
  db.execute(
    'INSERT INTO books(external_key, title, norm_title, ref_path, open_ref,'
    ' category, topics, tree_param, source_version)'
    " VALUES('7', 'משנה ברורה', 'משנה ברורה', 'משנה ברורה',"
    " 'משנה ברורה', 'טור, שולחן ערוך', '', 999, 25)",
  );
  for (final entry in {
    'responsa_version': '25',
    'install_path': r'C:\Program Files (x86)\ResponsaCD25',
    'exe_version': '25.0.0.0',
    'catalog_schema_version': '1',
    'catalog_build_time': '2026-09-18T03:03:35',
  }.entries) {
    db.execute('INSERT INTO db_meta(key, value) VALUES(?, ?)', [
      entry.key,
      entry.value,
    ]);
  }
  db.close();
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ResponsaCatalogRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria-responsa-');
    repository = ResponsaCatalogRepository()
      ..databasePathOverride = _createCatalog(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('טעינת ספרים', () {
    test('שורת DB הופכת ל-ExternalLibraryBook עם כל השדות', () async {
      final books = await repository.loadBooks();
      final yevamot = books.firstWhere((b) => b.title == 'יבמות');

      expect(yevamot.id, 1524);
      expect(yevamot.externalLibraryId, 'rp:1524');
      expect(yevamot.heCategories, 'מפרשים ופוסקים על הבבלי');
      // ההקשר הוא הנתיב בלי שם הספר — בלעדיו "יבמות" חסר משמעות.
      expect(yevamot.categoryPath, 'מפרשים ופוסקים על הבבלי/רא"ש');
    });

    test('link הוא null — אין לפרויקט השו"ת אתר', () async {
      final books = await repository.loadBooks();
      expect(books.every((b) => b.link == null), isTrue);
    });

    /// קטלוג בסכמה 1 אינו מכיר את עמודות המטא-דאטה כלל. הוא עדיין
    /// נקרא — שדרוג קוד אסור לו למחוק את הספרייה מהמסך — והשדות
    /// נשארים ריקים עד לרענון.
    test('קטלוג ישן בלי עמודות מטא-דאטה נקרא, והשדות ריקים', () async {
      final books = await repository.loadBooks();
      // בלי זה, קריאה שנשברה והחזירה רשימה ריקה — בדיוק מה שהבדיקה
      // נועדה למנוע — הייתה עוברת עם לולאה ריקה.
      expect(books, isNotEmpty);
      for (final book in books) {
        expect(book.author, isNull);
        expect(book.pubDate, isNull);
        expect(book.pubPlace, isNull);
      }
    });

    test('מחבר, מקום ושנת הדפסה עוברים מהקטלוג לספר', () {
      final book = ResponsaCatalogRepository.mapRow({
        'external_key': '5',
        'title': 'שו"ת אבני נזר',
        'ref_path': 'שו"ת > אבני נזר',
        'author': 'רבי אברהם בורנשטיין (פולין המאה ה- 19)',
        'pub_place': 'ירושלים',
        'pub_date': 'תשס"ו',
      });

      expect(book.author, 'רבי אברהם בורנשטיין (פולין המאה ה- 19)');
      expect(book.pubPlace, 'ירושלים');
      expect(book.pubDate, 'תשס"ו');
    });

    /// מחרוזת ריקה אינה "מידע ריק" אלא מידע שגוי: הממשק מחליט לפי
    /// `author != null` אם להציג שורת מחבר, ומחרוזת ריקה הייתה מייצרת
    /// שורה ריקה מתחת לכל ספר שאין לו מחבר.
    test('ערך ריק בקטלוג מגיע כ-null ולא כמחרוזת ריקה', () {
      final book = ResponsaCatalogRepository.mapRow({
        'external_key': '5',
        'title': 'ספר',
        'ref_path': 'ספר',
        'author': '   ',
        'pub_place': '',
      });

      expect(book.author, isNull);
      expect(book.pubPlace, isNull);
    });
  });

  group('open_ref', () {
    test('נשמר בנפרד מהכותרת', () async {
      // `openBook("יבמות")` היה פותח ספר אחר; ההקשר הוא כל ההבדל.
      expect(await repository.openRefFor('1524'), 'רא"ש יבמות');
    });

    test('מפתח שאינו קיים מחזיר null', () async {
      expect(await repository.openRefFor('99999'), isNull);
    });
  });

  group('מצב הקטלוג', () {
    test('info מחזיר ספירה וטביעת אצבע', () async {
      final info = await repository.info();
      expect(info.exists, isTrue);
      expect(info.bookCount, 2);
      expect(info.sourceVersion, 25);
      expect(info.schemaVersion, 1);
      expect(info.installPath, r'C:\Program Files (x86)\ResponsaCD25');
      expect(info.isUsable, isTrue);
    });

    test('קטלוג חסר אינו זורק — מחזיר מצב ריק', () async {
      final missing = ResponsaCatalogRepository()
        ..databasePathOverride = path.join(tempDir.path, 'nope.db');

      expect(await missing.exists(), isFalse);
      expect((await missing.info()).exists, isFalse);
      expect(await missing.loadBooks(), isEmpty);
      expect(await missing.openRefFor('1'), isNull);
    });

    test('קטלוג פגום אינו מפיל את החיפוש', () async {
      final corrupt = path.join(tempDir.path, 'corrupt.db');
      await File(corrupt).writeAsString('this is not a database');
      final repo = ResponsaCatalogRepository()..databasePathOverride = corrupt;

      expect(await repo.loadBooks(), isEmpty);
      expect((await repo.info()).exists, isFalse);
    });
  });

  group('contextPathOf', () {
    test('מסיר את שם הספר ומשאיר את ההקשר', () {
      expect(
        ResponsaCatalogRepository.contextPathOf('ספרות חז"ל > משנה > יבמות'),
        'ספרות חז"ל/משנה',
      );
    });

    test('ספר בשורש מקבל הקשר ריק', () {
      expect(ResponsaCatalogRepository.contextPathOf('משנה ברורה'), '');
      expect(ResponsaCatalogRepository.contextPathOf(''), '');
    });
  });
}
