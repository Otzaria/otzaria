// בדיקת שטח לכל פלטפורמה: מנוע החיפוש נבנה בלי SQLite משלו ומקבל את זה של
// Dart. אם הרישום נכשל בפלטפורמה, האינדוקס נופל בשקט לטקסט באינדקס והמילון
// המורפולוגי לא נטען כלל — ולכן זה נבדק על הבינארי האמיתי, לא בטסט יחידה.
//
// הרצה: flutter test integration_test/external_line_text_test.dart -d <device>

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/data/data_providers/book_text_reader.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

const _bom = '﻿';
final _dataUri = 'data:image/png;base64,${'A' * 96}';

/// ספר אחד ב-seforim.db הזעיר: (id, lineIndex, content) לכל שורה.
typedef _Book = ({
  int id,
  String title,
  List<(int rowId, int lineIndex, String content)> rows,
});

// ספר נקי: BOM בשורה הראשונה נשמר, ו-lineIndex מדלג על 2.
final _plainBook = (
  id: 101,
  title: 'ספר נקי',
  rows: [
    (1, 0, '$_bomבראשית ברא אלהים את השמים'),
    (2, 1, 'והארץ היתה תהו ובהו'),
    (3, 3, 'ויאמר אלהים יהי אור'),
    (4, 4, 'וירא אלהים את האור כי טוב'),
  ],
);

// ספר עם data: — האפליקציה מפענחת אותו כמחרוזת, וה-BOM הראשון נשמט.
final _dataUriBook = (
  id: 202,
  title: 'ספר מצויר',
  rows: [
    (5, 0, '$_bomלך לך מארצך וממולדתך'),
    (6, 1, 'ויעש אברם <img src="$_dataUri"> כאשר דבר'),
    (7, 2, 'ויקח אברם את שרי אשתו'),
  ],
);

// שורה עם `\n`: מספר השורות לא יתאים לרשומות, והאפליקציה שומרת את הטקסט באינדקס.
final _newlineBook = (
  id: 303,
  title: 'ספר שבור',
  rows: [(8, 0, 'שמע ישראל\nאחד'), (9, 1, 'ואהבת את רעך כמוך')],
);

final _libraryBooks = [_plainBook, _dataUriBook];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final engines = <SearchEngine>[];

  setUpAll(() async {
    await RustLib.init();
    tmp = await Directory.systemTemp.createTemp('external_line_text_it_');
  });

  tearDownAll(() async {
    for (final engine in engines) {
      engine.dispose();
    }
    await LibraryLineSource.closeNow();
    // Windows אינו מוחק קובץ פתוח; תיקייה זמנית שנשארה אינה כשל של הבדיקה.
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // נמחקת עם תיקיית הזמניים של המערכת.
    }
  });

  Future<SearchEngine> newEngine(String name) async {
    final dir = await Directory(p.join(tmp.path, name)).create();
    final engine = await SearchEngine.newInstance(path: dir.path);
    engines.add(engine);
    return engine;
  }

  String? lexicalDbPath;

  // אותה סכמה שה-MagicDictionary של המנוע מאמת בפתיחה.
  String buildLexicalDb() {
    if (lexicalDbPath case final path?) return path;
    final path = lexicalDbPath = p.join(tmp.path, 'lexical.db');
    final db = sqlite3.sqlite3.open(path);
    try {
      db.execute('''
        CREATE TABLE base (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL UNIQUE);
        CREATE TABLE surface (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL UNIQUE, base_id INTEGER NOT NULL REFERENCES base(id), notes TEXT);
        CREATE TABLE variant (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL UNIQUE);
        CREATE TABLE surface_variant (surface_id INTEGER NOT NULL REFERENCES surface(id), variant_id INTEGER NOT NULL REFERENCES variant(id), PRIMARY KEY (surface_id, variant_id));
        INSERT INTO base (id, value) VALUES (1, 'הלכ');
        INSERT INTO surface (id, value, base_id) VALUES (1, 'הלכתי', 1), (2, 'הולכ', 1);
      ''');
    } finally {
      db.close();
    }
    return path;
  }

  /// seforim.db מינימלי: מה שהמנוע קורא (line + idx_line_book_index) ומה
  /// שקורא הספרים של האפליקציה מאמת (book). [split] — סכמה 6, line_content.
  String buildLibraryDb(String name, {required bool split}) {
    final path = p.join(tmp.path, name);
    final db = sqlite3.sqlite3.open(path);
    try {
      db.execute('''
        CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
        CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL,
                           lineIndex INTEGER NOT NULL${split ? '' : ', content TEXT'});
        CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
        ${split ? 'CREATE TABLE line_content (id INTEGER PRIMARY KEY, content TEXT);' : ''}
      ''');
      for (final book in [..._libraryBooks, _newlineBook]) {
        db.execute('INSERT INTO book (id, title) VALUES (?, ?)', [
          book.id,
          book.title,
        ]);
        for (final (rowId, lineIndex, content) in book.rows) {
          if (split) {
            db.execute(
              'INSERT INTO line (id, bookId, lineIndex) VALUES (?, ?, ?)',
              [rowId, book.id, lineIndex],
            );
            db.execute('INSERT INTO line_content (id, content) VALUES (?, ?)', [
              rowId,
              content,
            ]);
          } else {
            db.execute(
              'INSERT INTO line (id, bookId, lineIndex, content) '
              'VALUES (?, ?, ?, ?)',
              [rowId, book.id, lineIndex, content],
            );
          }
        }
      }
    } finally {
      db.close();
    }
    return path;
  }

  /// מאנדקס את [book] בשלבים של IndexingRepository._indexTextBook: בייטים
  /// גולמיים מהמסד, ניקוי data:, והחלטת ה-TextStorage של האפליקציה.
  Future<TextStorage> indexLikeTheApp(
    SearchEngine engine,
    String dbPath,
    _Book book, {
    TextStorage? override,
  }) async {
    final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    final BookContentBytes read;
    try {
      read = (await readBookContentBytes(db, (
        id: book.id,
        title: book.title,
      )))!;
    } finally {
      db.close();
    }
    final cleaned = await IndexingRepository.cleanDataUrisOffFrame(read.bytes);
    final filePath = IndexingRepository.officialBookKey(book.id);
    final storage =
        override ??
        IndexingRepository.textStorageFor(
          filePath: filePath,
          libraryDbBookId: read.rowHasNewline ? null : book.id,
          hostApiReady: LibraryLineSource.hostApiReady,
        );
    final bytes = cleaned.bytes;
    final added = bytes != null
        ? await engine.addTextBookBytes(
            title: book.title,
            topics: '/it',
            filePath: filePath,
            catalogueOrder: book.id,
            generationOrder: 0,
            text: bytes,
            textStorage: storage,
          )
        : await engine.addTextBook(
            title: book.title,
            topics: '/it',
            filePath: filePath,
            catalogueOrder: book.id,
            generationOrder: 0,
            text: cleaned.text!,
            textStorage: storage,
          );
    expect(added, greaterThan(0), reason: book.title);
    return storage;
  }

  Future<List<SearchResult>> exact(SearchEngine engine, String query) =>
      engine.searchExact(
        query: query,
        facets: const [],
        limit: 10,
        offset: 0,
        order: ResultsOrder.catalogue,
        matchNikud: false,
        matchTaamim: false,
      );

  Future<SearchResult> single(SearchEngine engine, String query) async {
    final results = await exact(engine, query);
    expect(results, hasLength(1), reason: query);
    return results.single;
  }

  String withoutHighlight(String text) =>
      text.replaceAll('<font color=red>', '').replaceAll('</font>', '');

  group('SQLite של Dart במנוע', () {
    test('לפני הרישום אין למנוע SQLite, והמילון אינו נטען', () async {
      expect(
        sqliteHostEntryAddress(),
        isNot(BigInt.zero),
        reason: 'בניית האפליקציה חייבת להיות sqlite-host, בלי SQLite משלה',
      );
      expect((await lineSourceStatus()).hostApiReady, isFalse);

      final engine = await newEngine('before_registration');
      expect(engine.setMagicDictionaryPath(path: buildLexicalDb()), isFalse);
      expect(engine.hasMagicDictionary(), isFalse);
    });

    test('ensureHostSqlite של האפליקציה מוסר למנוע את SQLite', () async {
      expect(await LibraryLineSource.ensureHostSqlite(), isTrue);
      expect(LibraryLineSource.hostApiReady, isTrue);
      expect((await lineSourceStatus()).hostApiReady, isTrue);
      expect(await LibraryLineSource.ensureHostSqlite(), isTrue);
    });

    test('המילון המורפולוגי נטען ומרחיב את החיפוש המקורב', () async {
      final engine = await newEngine('magic');
      await engine.addDocument(
        id: BigInt.one,
        title: 'a',
        reference: 'a',
        topics: '/it',
        text: 'הלכתי',
        segment: BigInt.zero,
        isPdf: false,
        filePath: '/books/a.txt',
      );
      await engine.commit();
      Future<List<SearchResult>> fuzzy() => engine.searchFuzzy(
        query: 'הלך',
        facets: const [],
        limit: 10,
        offset: 0,
        maxDistance: 2,
        order: ResultsOrder.relevance,
        matchNikud: false,
        matchTaamim: false,
      );

      // "הלך"→"הלכתי" רחוק 3 עריכות: רק ההרחבה מהמילון מגיעה אליו.
      expect(await fuzzy(), isEmpty);
      expect(engine.setMagicDictionaryPath(path: buildLexicalDb()), isTrue);
      expect(engine.hasMagicDictionary(), isTrue);
      final results = await fuzzy();
      expect(results.map((r) => withoutHighlight(r.text)), contains('הלכתי'));
    });
  });

  for (final split in [false, true]) {
    final layout = split ? 'line_content (סכמה 6)' : 'line.content (סכמה 5)';

    test('טקסט השורות נקרא מ-seforim.db — $layout', () async {
      expect(
        LibraryLineSource.hostApiReady,
        isTrue,
        reason: 'הרישום נבדק בקבוצה הקודמת',
      );
      final suffix = split ? 'split' : 'inline';
      final dbPath = buildLibraryDb('seforim_$suffix.db', split: split);
      await LibraryLineSource.configure(dbPath);

      final library = await newEngine('library_$suffix');
      final stored = await newEngine('stored_$suffix');
      for (final book in _libraryBooks) {
        expect(
          await indexLikeTheApp(library, dbPath, book),
          TextStorage.libraryDb,
          reason: book.title,
        );
        await indexLikeTheApp(
          stored,
          dbPath,
          book,
          override: TextStorage.inIndex,
        );
      }
      expect(
        await indexLikeTheApp(library, dbPath, _newlineBook),
        TextStorage.inIndex,
      );
      await library.commit();
      await stored.commit();
      expect((await lineSourceStatus()).libraryFallbacks, BigInt.zero);

      // (שאילתה, מיקום השורה בסדר lineIndex, הטקסט המוצג). ה-BOM נכלל בבדיקת
      // השורה (ok רק אם המנוע נהג בו כמו האינדוקס), אבל לא בטקסט המוצג.
      final cases = [
        ('בראשית', 0, 'בראשית ברא אלהים את השמים'),
        ('תהו', 1, 'והארץ היתה תהו ובהו'),
        // אחרי הפער: lineIndex 3 הוא המיקום השלישי, ו-lineIndex 4 הרביעי.
        ('יהי אור', 2, 'ויאמר אלהים יהי אור'),
        ('כי טוב', 3, 'וירא אלהים את האור כי טוב'),
        ('מארצך', 0, 'לך לך מארצך וממולדתך'),
        // ה-data: הוסר לפני הבדיקה; תגיות ה-HTML אינן חלק מהקטע המוצג.
        ('כאשר דבר', 1, 'ויעש אברם כאשר דבר'),
        ('שרי אשתו', 2, 'ויקח אברם את שרי אשתו'),
      ];
      for (final (query, ordinal, expected) in cases) {
        final result = await single(library, query);
        expect(result.textStatus, TextStatus.ok, reason: query);
        expect(result.segment, BigInt.from(ordinal), reason: query);
        expect(withoutHighlight(result.text), expected, reason: query);
        expect(result.text, (await single(stored, query)).text, reason: query);
      }
      expect((await lineSourceStatus()).libraryFallbacks, BigInt.zero);

      // בזמן השעיה הטקסט אינו באינדקס כלל; הספר שנשמר באינדקס אינו מושפע.
      await LibraryLineSource.holdForExternalWrite();
      final suspended = await lineSourceStatus();
      expect(suspended.suspendDepth, 1);
      expect(suspended.open, isFalse);
      for (final (query, _, _) in cases) {
        final result = await single(library, query);
        expect(result.textStatus, TextStatus.unavailable, reason: query);
        expect(result.text, isEmpty, reason: query);
      }
      final kept = await single(library, 'כמוך');
      expect(kept.textStatus, TextStatus.ok);
      expect(withoutHighlight(kept.text), 'ואהבת את רעך כמוך');

      await LibraryLineSource.releaseExternalWriteHold();
      expect((await lineSourceStatus()).suspendDepth, 0);
      for (final (query, _, expected) in cases) {
        final result = await single(library, query);
        expect(result.textStatus, TextStatus.ok, reason: query);
        expect(withoutHighlight(result.text), expected, reason: query);
      }
      expect((await lineSourceStatus()).libraryFallbacks, BigInt.zero);
    });
  }
}
