import 'dart:io' as io;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  group('IndexingRepository.shouldSkipManualReindexCheck', () {
    test('מחזיר true עבור ספרייה ריקה - מונע דיאלוג איפוס בלי ספרים', () {
      expect(
        IndexingRepository.shouldSkipManualReindexCheck(
          Library(categories: []),
        ),
        isTrue,
      );
    });

    test('מחזיר true עבור ספרייה עם קטגוריות ריקות', () {
      final library = Library(categories: []);
      library.subCategories.add(
        Category(
          title: 'תנ"ך',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: [],
          books: [],
          parent: library,
        ),
      );
      expect(
        IndexingRepository.shouldSkipManualReindexCheck(library),
        isTrue,
      );
    });

    test('מחזיר false עבור ספרייה עם ספר אחד', () {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      expect(
        IndexingRepository.shouldSkipManualReindexCheck(library),
        isFalse,
      );
    });
  });

  group('IndexingRepository.areAllIndexableBooksIndexed', () {
    test('מחזיר true כשכל הספרים האינדקסביליים קיימים באינדקס', () {
      final library = _buildLibrary(
        bavliBooks: const [('שבת', 1)],
        additionalBooks: [
          PdfBook(
            title: 'קובץ PDF',
            path: r'C:\library\sample.pdf',
            categoryPath: 'ספרים אישיים',
          ),
          ExternalLibraryBook(
            title: 'ספר חיצוני',
            id: 900,
            link: 'https://example.com/book',
          ),
        ],
      );

      final indexedFilePaths = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.buildIndexedBookFilePath)
          .toSet();

      expect(
        IndexingRepository.areAllIndexableBooksIndexed(
          library.getAllBooks(),
          indexedFilePaths,
        ),
        isTrue,
      );
    });

    test('מחזיר false כשחסר ספר אינדקסבילי אחד', () {
      final library = _buildLibrary(
        bavliBooks: const [('שבת', 1)],
        additionalBooks: [
          DocxBook(
            title: 'מסמך',
            path: r'C:\library\doc.docx',
            categoryPath: 'ספרים אישיים',
          ),
        ],
      );

      final indexedFilePaths = {
        IndexingRepository.buildIndexedBookFilePath(
          library.getAllBooks().first,
        ),
      };

      expect(
        IndexingRepository.areAllIndexableBooksIndexed(
          library.getAllBooks(),
          indexedFilePaths,
        ),
        isFalse,
      );
    });

    test('מחזיר false כשאין כלל ספרים אינדקסביליים', () {
      final library = Library(categories: []);
      library.books.add(
        ExternalLibraryBook(
          title: 'ספר חיצוני',
          id: 901,
          link: 'https://example.com/ext',
        ),
      );

      expect(
        IndexingRepository.areAllIndexableBooksIndexed(
          library.getAllBooks(),
          const <String>{},
        ),
        isFalse,
      );
    });
  });

  group('IndexingRepository.hasPathKeyedIndexEntry', () {
    test('PdfBook תמיד מאונדקס לפי נתיב (גם עם id)', () {
      expect(
        IndexingRepository.hasPathKeyedIndexEntry(
          PdfBook(title: 'ברכות', path: r'C:\lib\ברכות.pdf'),
        ),
        isTrue,
      );
      expect(
        IndexingRepository.hasPathKeyedIndexEntry(
          PdfBook(title: 'ברכות', path: r'C:\lib\ברכות.pdf', id: 5),
        ),
        isTrue,
      );
    });

    test('DocxBook ללא id — לפי נתיב; עם id — שורד העברה', () {
      expect(
        IndexingRepository.hasPathKeyedIndexEntry(
          DocxBook(title: 'מסמך', path: r'C:\lib\doc.docx'),
        ),
        isTrue,
      );
      expect(
        IndexingRepository.hasPathKeyedIndexEntry(
          DocxBook(title: 'מסמך', path: r'C:\lib\doc.docx', id: 7),
        ),
        isFalse,
      );
    });

    test('TextBook מ-DB — לא לפי נתיב', () {
      expect(
        IndexingRepository.hasPathKeyedIndexEntry(TextBook(title: 'שבת')),
        isFalse,
      );
    });
  });

  group('IndexingRepository.dropRelocatedFileBookEntries', () {
    test('מוחק לפי מפתח ה-filePath המדויק ומבצע commit יחיד', () async {
      final engine = _RecordingSearchEngine();
      final repository = IndexingRepository(
        _RecordingTantivyDataProvider(engine),
      );

      await repository.dropRelocatedFileBookEntries([
        PdfBook(title: 'ברכות', path: r'C:\old\ברכות.pdf'),
        PdfBook(title: 'ברכות', path: r'C:\old\ברכות-עותק.pdf'),
        PdfBook(title: 'שבת', path: r'C:\old\שבת.pdf'),
      ]);

      expect(engine.removedFilePaths.toSet(), {
        r'C:\old\ברכות.pdf',
        r'C:\old\ברכות-עותק.pdf',
        r'C:\old\שבת.pdf',
      });
      expect(engine.commitCount, 1);
    });

    test('ללא ספרים — לא נוגע במנוע', () async {
      final engine = _RecordingSearchEngine();
      final repository = IndexingRepository(
        _RecordingTantivyDataProvider(engine),
      );

      await repository.dropRelocatedFileBookEntries(const []);

      expect(engine.removedFilePaths, isEmpty);
      expect(engine.commitCount, 0);
    });

    test('כשל ב-commit של המחיקה — rollback משליך את המחיקה הממתינה', () async {
      // רגרסיה: מחיקה שנשארה בחוצץ הייתה נחתמת ע"י commit מאוחר של מסלול
      // אחר, בעוד הספר עדיין רשום ב-indexedFilePaths — נעלם מהחיפוש ומדולג.
      final engine = _RecordingSearchEngine()..failCommit = true;
      final provider = _RecordingTantivyDataProvider(engine);
      final book = TextBook(id: 5, title: 'שבת');
      final key = IndexingRepository.buildIndexedBookFilePath(book);
      provider.indexedFilePaths.add(key);
      engine.committedFilePaths = [key];
      final repository = IndexingRepository(provider);

      final result = await repository.dropBookIndexEntries([book]);

      expect(result, isFalse);
      expect(engine.rollbackCount, 1);
      expect(provider.reopenCount, 1);
      // המעקב נשאר עקבי עם המצב החתום — הספר עדיין מאונדקס וזמין בחיפוש.
      expect(provider.indexedFilePaths, {key});
    });

    test(
      'commit נחתם בדיסק אך הקריאה זרקה (כשל reload) — המעקב מתעדכן',
      () async {
        // רגרסיה: קריאה מה-reader הישן החזירה את הספר ל-indexedFilePaths
        // למרות שמסמכיו נמחקו — נעלם מהחיפוש וגם דולג באינדוקס הבא.
        final engine = _RecordingSearchEngine()..failCommit = true;
        final provider = _RecordingTantivyDataProvider(engine);
        final book = TextBook(id: 5, title: 'שבת');
        final key = IndexingRepository.buildIndexedBookFilePath(book);
        provider.indexedFilePaths.add(key);
        // המחיקה כן נחתמה בדיסק — המצב החתום כבר בלי הספר.
        engine.committedFilePaths = [];
        final repository = IndexingRepository(provider);

        final result = await repository.dropBookIndexEntries([book]);

        expect(result, isFalse);
        expect(provider.reopenCount, 1);
        // פתיחה מאולצת — אחרת throttle של 5 שניות היה מדלג ומשאיר מצב מעופש.
        expect(provider.lastReopenForce, isTrue);
        // הספר אינו מסומן כמאונדקס — ינוסה שוב במקום להיעלם מהחיפוש לתמיד.
        expect(provider.indexedFilePaths, isEmpty);
      },
    );
  });

  group('IndexingRepository.dropBookIndexEntries', () {
    test('מסיר גם את מפתחות הספרים מ-indexedFilePaths', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final book = TextBook(id: 5, title: 'שבת');
      provider.indexedFilePaths.add(
        IndexingRepository.buildIndexedBookFilePath(book),
      );
      final repository = IndexingRepository(provider);

      await repository.dropBookIndexEntries([book]);

      expect(engine.removedFilePaths, ['id:5']);
      expect(provider.indexedFilePaths, isEmpty);
    });

    test('ספר אישי החולק כותרת עם ספר רשמי אינו נפגע ממחיקת הרשמי', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final official = TextBook(id: 5, title: 'שבת');
      final personal = TextBook(id: 5, title: 'שבת', isUserBook: true);
      provider.indexedFilePaths.addAll([
        IndexingRepository.buildIndexedBookFilePath(official),
        IndexingRepository.buildIndexedBookFilePath(personal),
      ]);
      final repository = IndexingRepository(provider);

      await repository.dropBookIndexEntries([official]);

      expect(engine.removedFilePaths, ['id:5']);
      expect(provider.indexedFilePaths, {'uid:5'});
    });
  });

  group('IndexingRepository.dropOrphanedIndexEntries', () {
    test('מסיר מפתחות uid: של ספרים שאינם עוד בספרייה', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final existing = TextBook(id: 1, title: 'שבת', isUserBook: true);
      final library = _buildLibrary(bavliBooks: const []);
      library.books.add(existing);

      provider.indexedFilePaths.addAll({
        IndexingRepository.buildIndexedBookFilePath(existing), // בספרייה
        'uid:99', // ספר אישי שנמחק
        'id:7', // רשמי חסר — לא נוגעים (טעינה חלקית אסור שתמחק)
        'ext:abc', // חיצוני חסר — לא נוגעים
      });
      final repository = IndexingRepository(provider);

      final removed = await repository.dropOrphanedIndexEntries(library);

      expect(removed, 1);
      expect(engine.removedFilePaths, ['uid:99']);
      expect(engine.commitCount, 1);
      expect(provider.indexedFilePaths, {
        IndexingRepository.buildIndexedBookFilePath(existing),
        'id:7',
        'ext:abc',
      });
    });

    test('מפתח נתיב-מוחלט נמחק רק כשהקובץ כבר לא קיים בדיסק', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);

      // קובץ שלא קיים — יתום אמיתי; Platform.script בטוח קיים — נשמר.
      final sep = io.Platform.pathSeparator;
      final missingPath =
          '${io.Directory.systemTemp.path}${sep}definitely-missing$sep'
          'ספר.pdf';
      final existingFilePath = io.Platform.resolvedExecutable;
      provider.indexedFilePaths.addAll({missingPath, existingFilePath});
      final repository = IndexingRepository(provider);

      final removed = await repository.dropOrphanedIndexEntries(library);

      expect(removed, 1);
      expect(engine.removedFilePaths, [missingPath]);
      expect(provider.indexedFilePaths, {existingFilePath});
    });

    test('ספרייה ריקה — לא נוגע באינדקס', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      provider.indexedFilePaths.add('uid:99');
      final repository = IndexingRepository(provider);

      final removed = await repository.dropOrphanedIndexEntries(
        Library(categories: []),
      );

      expect(removed, 0);
      expect(engine.removedFilePaths, isEmpty);
      expect(provider.indexedFilePaths, {'uid:99'});
    });

    test(
      'כשל commit בניקוי יתומים — שחזור מנוע ומחזיר 0 בלי לסמן כמנוקה',
      () async {
        // רגרסיה: המסלול הזה ביצע delete+commit ישיר; כשל commit היה נבלע,
        // המחיקה עלולה הייתה להיחתם מאוחר בעוד המפתח נשאר במעקב — קובץ שחזר
        // לספרייה היה מדולג כ"מאונדקס".
        final engine = _RecordingSearchEngine()..failCommit = true;
        final provider = _RecordingTantivyDataProvider(engine);
        final existing = TextBook(id: 1, title: 'שבת', isUserBook: true);
        final library = _buildLibrary(bavliBooks: const []);
        library.books.add(existing);
        final existingKey = IndexingRepository.buildIndexedBookFilePath(
          existing,
        );
        provider.indexedFilePaths.addAll({existingKey, 'uid:99'});
        // המחיקה לא נחתמה — המצב החתום בדיסק עדיין מכיל את שניהם.
        engine.committedFilePaths = [existingKey, 'uid:99'];
        final repository = IndexingRepository(provider);

        final removed = await repository.dropOrphanedIndexEntries(library);

        expect(removed, 0);
        expect(engine.rollbackCount, 1);
        expect(provider.reopenCount, 1);
        expect(provider.lastReopenForce, isTrue);
        // המעקב עקבי עם המצב החתום — היתום עדיין רשום, ינוקה בניסיון הבא.
        expect(provider.indexedFilePaths, {existingKey, 'uid:99'});
      },
    );
  });

  group('IndexingRepository.reindexChangedBooks', () {
    test(
      'מוחק ומאנדקס מחדש רק את הספרים שהשתנו — לא שכנים בעלי אותה כותרת',
      () async {
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final official = TextBook(id: 5, title: 'שבת');
        final personal = TextBook(id: 9, title: 'שבת', isUserBook: true);
        final other = TextBook(id: 6, title: 'עירובין');
        final library = _buildLibrary(bavliBooks: const []);
        library.books.addAll([official, personal, other]);
        for (final b in [official, personal, other]) {
          provider.indexedFilePaths.add(
            IndexingRepository.buildIndexedBookFilePath(b),
          );
        }
        final repository = _ReindexProbeRepository(provider);

        final result = await repository.reindexChangedBooks(
          [official],
          library,
          onProgress: (_, _) {},
        );

        expect(result, isTrue);
        // המחיקה לפי מפתח ה-filePath המדויק — הספר האישי 'שבת' (uid:9) נשאר.
        expect(engine.removedFilePaths, ['id:5']);
        expect(provider.indexedFilePaths, {
          IndexingRepository.buildIndexedBookFilePath(personal),
          IndexingRepository.buildIndexedBookFilePath(other),
        });
        expect(repository.indexedBooks!.single.title, 'שבת');
        expect(repository.indexedBooks!.single.isUserBook, isFalse);
      },
    );

    test('כשל במחיקת האינדקס הישן — מחזיר false בלי לאנדקס', () async {
      // רגרסיה: הכשל נבלע, indexBooks דילג על הספר (עדיין ב-indexedFilePaths)
      // והפונקציה החזירה true — האינדקס הישן נשאר ודווח כהצלחה.
      final engine = _RecordingSearchEngine()..failDeleteFilePaths = true;
      final provider = _RecordingTantivyDataProvider(engine);
      final changed = TextBook(id: 5, title: 'שבת');
      final library = _buildLibrary(bavliBooks: const []);
      library.books.add(changed);
      provider.indexedFilePaths.add(
        IndexingRepository.buildIndexedBookFilePath(changed),
      );
      // המחיקה לא יצאה לפועל — הספר עדיין חתום באינדקס שבדיסק.
      engine.committedFilePaths = [
        IndexingRepository.buildIndexedBookFilePath(changed),
      ];
      final repository = _ReindexProbeRepository(provider);

      final result = await repository.reindexChangedBooks(
        [changed],
        library,
        onProgress: (_, _) {},
      );

      expect(result, isFalse);
      expect(repository.indexedBooks, isNull);
      // המעקב המקומי לא השתנה — הספר עדיין מסומן וימתין לניסיון הבא.
      expect(provider.indexedFilePaths, {'id:5'});
    });

    test('רשימה ריקה — לא נוגע במנוע ולא מאנדקס', () async {
      final engine = _RecordingSearchEngine();
      final repository = _ReindexProbeRepository(
        _RecordingTantivyDataProvider(engine),
      );

      final result = await repository.reindexChangedBooks(
        const [],
        _buildLibrary(bavliBooks: const [('שבת', 1)]),
        onProgress: (_, _) {},
      );

      expect(result, isTrue);
      expect(engine.removedFilePaths, isEmpty);
      expect(repository.indexedBooks, isNull);
    });
  });

  group('IndexingRepository.reconcileIndexWithLibrary', () {
    TextBook book(int id, String title) => TextBook(id: id, title: title);

    test(
      'מזהה ספרים ששונו או בלתי-ניתנים-לאימות ומאנדקס רק אותם מחדש',
      () async {
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final unchanged = book(1, 'שבת');
        final changed = book(2, 'עירובין');
        final notIndexed = book(3, 'פסחים');
        final unverifiable = book(4, 'יומא');
        final unloadable = book(5, 'סוכה');
        final library = _buildLibrary(bavliBooks: const []);
        library.books.addAll([
          unchanged,
          changed,
          notIndexed,
          unverifiable,
          unloadable,
        ]);

        engine.fingerprints = {
          IndexingRepository.buildIndexedBookFilePath(unchanged): BigInt.from(
            11,
          ),
          IndexingRepository.buildIndexedBookFilePath(changed): BigInt.from(21),
          IndexingRepository.buildIndexedBookFilePath(unverifiable):
              BigInt.zero,
          IndexingRepository.buildIndexedBookFilePath(unloadable): BigInt.from(
            55,
          ),
          // notIndexed בכוונה חסר — ספר חדש שמטופל במסלול הרגיל.
        };
        for (final b in [unchanged, changed, unverifiable, unloadable]) {
          provider.indexedFilePaths.add(
            IndexingRepository.buildIndexedBookFilePath(b),
          );
        }

        final texts = {
          'שבת': 'אחד',
          'עירובין': 'שתיים-חדש',
          'יומא': 'שלוש',
          // 'סוכה' חסר — טעינה נכשלת.
        };
        final hashes = {
          'אחד': BigInt.from(11), // תואם לאינדקס — לא השתנה
          'שתיים-חדש': BigInt.from(22), // שונה מ-21 — השתנה
          'שלוש': BigInt.from(33),
        };

        final repository = _ReindexProbeRepository(provider);
        final scanCalls = <(int, int)>[];

        final result = await repository.reconcileIndexWithLibrary(
          library,
          onScanProgress: (p, t) => scanCalls.add((p, t)),
          onProgress: (_, _) {},
          loadText: (b) async => texts[b.title],
          fingerprintOf: (_, text) async => hashes[text]!,
        );

        expect(result, isTrue);
        expect(
          repository.indexedBooks!.map((b) => b.title).toSet(),
          {'עירובין', 'יומא'},
        );
        expect(engine.removedFilePaths.toSet(), {'id:2', 'id:4'});
        // הסריקה כיסתה את חמשת ספרי הטקסט שהוספנו ואת ברירת-המחדל ב"תנ"ך".
        expect(scanCalls.last, (6, 6));
        // isIndexing חוזר ל-false אחרי הסריקה (indexBooks מזויף בטסט).
        expect(provider.isIndexing.value, isFalse);
      },
    );

    test('כשהכל תואם — מסתיים בהצלחה בלי לגעת באינדקס', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final b = book(1, 'שבת');
      final library = _buildLibrary(bavliBooks: const []);
      library.books.add(b);
      engine.fingerprints = {
        IndexingRepository.buildIndexedBookFilePath(b): BigInt.from(7),
      };

      final repository = _ReindexProbeRepository(provider);
      final result = await repository.reconcileIndexWithLibrary(
        library,
        onProgress: (_, _) {},
        loadText: (_) async => 'טקסט',
        fingerprintOf: (_, _) async => BigInt.from(7),
      );

      expect(result, isTrue);
      expect(repository.indexedBooks, isNull);
      expect(engine.removedFilePaths, isEmpty);
    });

    test('ביטול באמצע הסריקה מחזיר false בלי לאנדקס', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const []);
      library.books.addAll([book(1, 'שבת'), book(2, 'עירובין')]);
      engine.fingerprints = {
        for (final b in library.books)
          IndexingRepository.buildIndexedBookFilePath(b): BigInt.from(9),
      };

      final repository = _ReindexProbeRepository(provider);
      final result = await repository.reconcileIndexWithLibrary(
        library,
        onProgress: (_, _) {},
        loadText: (b) async {
          // מדמה לחיצת ביטול של המשתמש בזמן הסריקה.
          provider.isIndexing.value = false;
          return 'טקסט';
        },
        fingerprintOf: (_, _) async => BigInt.one,
      );

      expect(result, isFalse);
      expect(repository.indexedBooks, isNull);
    });
  });

  group('IndexingRepository.indexAllBooks', () {
    test('fast path מחזיר מוקדם בלי להפעיל isolate ובלי callbacks', () async {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      final indexedFilePaths = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.buildIndexedBookFilePath)
          .toSet();
      final provider = FakeTantivyDataProvider(
        indexedFilePaths: indexedFilePaths,
        requiresManualReindexValue: false,
      );
      final repository = IndexingRepository(provider);

      var actualIndexingStarted = false;
      var progressCalls = 0;

      final result = await repository.indexAllBooks(
        library,
        onActualIndexingStarted: () {
          actualIndexingStarted = true;
        },
        onProgress: (_, _) {
          progressCalls++;
        },
      );

      expect(result, isTrue);
      expect(actualIndexingStarted, isFalse);
      expect(progressCalls, 0);
    });

    test('מנוע על אינדקס זמני (temp fallback) — האינדוקס מושהה', () async {
      // רגרסיה כפולה: כשל בפתיחת אינדקס הדיסק נפל בשקט לאינדקס זמני וכל
      // האינדוקס נזרק בהפעלה הבאה; והדגל נבדק לפני שהאתחול הסתיים — כאן
      // הדגל נדלק רק בהמתנה למנוע, כמו במציאות (אתחול שרץ ברקע).
      TestWidgetsFlutterBinding.ensureInitialized();
      final engine = _RecordingSearchEngine();
      final provider = _DelayedTempFallbackProvider(engine);
      final library = Library(categories: []);
      library.books.add(PdfBook(title: 'א', path: r'C:\missing\א.pdf'));
      final repository = IndexingRepository(provider);
      var progressCalls = 0;

      final fullRun = await repository.indexAllBooks(
        library,
        onProgress: (_, _) => progressCalls++,
      );
      final specificRun = await repository.indexBooks(
        library.books.cast<Book>(),
        library,
        onProgress: (_, _) => progressCalls++,
      );
      final reconcileRun = await repository.reconcileIndexWithLibrary(
        library,
        onProgress: (_, _) => progressCalls++,
      );

      expect(fullRun, isFalse);
      expect(specificRun, isFalse);
      expect(reconcileRun, isFalse);
      expect(progressCalls, 0);
      expect(engine.addedDocuments, isEmpty);
      expect(provider.isIndexing.value, isFalse);
    });

    test('לא מדלג ב-fast path כשנדרש manual reindex', () async {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      final indexedFilePaths = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(IndexingRepository.buildIndexedBookFilePath)
          .toSet();
      final provider = FakeTantivyDataProvider(
        indexedFilePaths: indexedFilePaths,
        requiresManualReindexValue: true,
      );
      final repository = IndexingRepository(provider);

      var actualIndexingStarted = false;
      var progressCalls = 0;

      final result = await repository.indexAllBooks(
        library,
        onActualIndexingStarted: () {
          actualIndexingStarted = true;
        },
        onProgress: (_, _) {
          progressCalls++;
        },
      );

      expect(result, isFalse);
      expect(actualIndexingStarted, isFalse);
      expect(progressCalls, 0);
    });

    test('מדווח את הספר הנוכחי בתחילת עיבודו, לפני הכתיבה למנוע', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      // ‏PDF שקבציהם חסרים — עוברים במסלול סמן-ריק, בלי pdfrx ובלי DB.
      library.books.addAll([
        PdfBook(title: 'א', path: r'C:\missing\א.pdf'),
        PdfBook(title: 'ב', path: r'C:\missing\ב.pdf'),
      ]);
      final repository = IndexingRepository(provider);
      final calls = <(int, int, int)>[];

      final result = await repository.indexAllBooks(
        library,
        onProgress: (p, t) => calls.add((p, t, engine.addedDocuments.length)),
      );

      expect(result, isTrue);
      // הדיווח הראשון הוא תחילת הספר הראשון — עוד לפני שנכתב מסמך כלשהו.
      expect(calls.first, (1, 2, 0));
      expect(calls.last.$1, 2);
    });

    test('כשל באמצע כתיבת ספר מוחק את מסמכיו החלקיים מהאינדקס', () async {
      // רגרסיה: בלי המחיקה, ה-commit הבא חתם כתיבה חלקית והספר נחשב
      // "מאונדקס" לתמיד — ספר חלקי קבוע בתוצאות החיפוש.
      final engine = _RecordingSearchEngine()..failAddForTitle = 'ב';
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      library.books.addAll([
        PdfBook(title: 'א', path: r'C:\missing\א.pdf'),
        PdfBook(title: 'ב', path: r'C:\missing\ב.pdf'),
      ]);
      final repository = IndexingRepository(provider);

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result, isTrue);
      // הכתיבה החלקית אכן נרשמה במנוע לפני הכשל — ורק אז נמחקה.
      expect(engine.addedDocuments.map((d) => d.title), contains('ב'));
      // רק הספר שכשל נוקה; שכנו שהצליח לא נמחק.
      expect(engine.removedFilePaths, [r'C:\missing\ב.pdf']);
      expect(provider.indexedFilePaths, {r'C:\missing\א.pdf'});
    });

    test('חילוץ PDF שהסתיים בזמן שלב הטקסטים מאונדקס מיד ולא פעמיים', () async {
      // רגרסיה: ה-prefetch היה חד-סלוטי בלי ניקוז — לאורך כל שלב הטקסטים
      // חולץ PDF אחד בלבד, והשאר חולצו סדרתית רק בסוף.
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      final indexedText1 = TextBook(id: 1, title: 'ט1');
      final indexedText2 = TextBook(id: 2, title: 'ט2');
      final pdf1 = PdfBook(title: 'א', path: r'C:\pdfs\א.pdf');
      final pdf2 = PdfBook(title: 'ב', path: r'C:\pdfs\ב.pdf');
      library.books.addAll([indexedText1, indexedText2, pdf1, pdf2]);
      // ספרי הטקסט כבר מאונדקסים — מדולגים, אך נותנים ללולאה "זמן טקסטים"
      // שבו חילוץ ה-prefetch מסתיים ומנוקז.
      provider.indexedFilePaths.addAll([
        IndexingRepository.buildIndexedBookFilePath(indexedText1),
        IndexingRepository.buildIndexedBookFilePath(indexedText2),
      ]);
      final repository = _FakeExtractionRepository(provider);

      // יומן אירועים משולב — מוכיח את *סדר* הכתיבות ביחס להתקדמות הלולאה.
      final events = <String>[];
      engine.onPdfAdded = (title) => events.add('pdf:$title');

      final result = await repository.indexAllBooks(
        library,
        onProgress: (p, _) => events.add('progress:$p'),
      );

      expect(result, isTrue);
      // 'א' (מיקום 3) נכתב בזמן שהלולאה עוד עמדה על ט2 (מיקום 2), ו-'ב'
      // (מיקום 4) נכתב בזמן שהלולאה עמדה על 'א' — הניקוז המוקדם; במימוש
      // הישן כל כתיבה הייתה קורית רק אחרי דיווח המיקום של אותו ספר עצמו.
      expect(events, [
        'progress:2',
        'pdf:א',
        'progress:3',
        'pdf:ב',
        'progress:4',
      ]);
      // כל PDF חולץ ואונדקס בדיוק פעם אחת — הניקוז המוקדם לא מכפיל.
      expect(repository.extractedTitles, ['א', 'ב']);
      expect(engine.addedPdfTitles, ['א', 'ב']);
      expect(
        provider.indexedFilePaths,
        containsAll([pdf1.path, pdf2.path]),
      );
    });

    test('כשל באינדוקס מוקדם של PDF — לא מנוסה שוב באותה ריצה', () async {
      final engine = _RecordingSearchEngine()..failPdfAddForTitle = 'א';
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      final indexedText1 = TextBook(id: 1, title: 'ט1');
      final indexedText2 = TextBook(id: 2, title: 'ט2');
      final pdf1 = PdfBook(title: 'א', path: r'C:\pdfs\א.pdf');
      final pdf2 = PdfBook(title: 'ב', path: r'C:\pdfs\ב.pdf');
      library.books.addAll([indexedText1, indexedText2, pdf1, pdf2]);
      provider.indexedFilePaths.addAll([
        IndexingRepository.buildIndexedBookFilePath(indexedText1),
        IndexingRepository.buildIndexedBookFilePath(indexedText2),
      ]);
      final repository = _FakeExtractionRepository(provider);

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result, isTrue);
      // 'א' נוסה פעם אחת (בניקוז המוקדם) ולא שוב כשהלולאה הגיעה אליו.
      expect(repository.extractedTitles, ['א', 'ב']);
      expect(engine.addedPdfTitles, ['א', 'ב']);
      // המסמכים החלקיים של 'א' נוקו; 'ב' אונדקס כרגיל.
      expect(engine.removedFilePaths, [pdf1.path]);
      expect(provider.indexedFilePaths, contains(pdf2.path));
      expect(provider.indexedFilePaths, isNot(contains(pdf1.path)));
    });

    test(
      'כשל גם בניקוי המסמכים החלקיים — עוצר בלי commit ומבצע rollback',
      () async {
        // רגרסיה: כשה-writer פגוע גם המחיקה נכשלת; המשך עד ה-commit הסופי
        // היה חותם את הכתיבה החלקית למרות הניקוי הכושל.
        final engine = _RecordingSearchEngine()
          ..failAddForTitle = 'ב'
          ..failDeleteFilePaths = true;
        final provider = _RecordingTantivyDataProvider(engine);
        final library = Library(categories: []);
        library.books.addAll([
          PdfBook(title: 'א', path: r'C:\missing\א.pdf'),
          PdfBook(title: 'ב', path: r'C:\missing\ב.pdf'),
          PdfBook(title: 'ג', path: r'C:\missing\ג.pdf'),
        ]);
        final repository = IndexingRepository(provider);
        var progressCalls = 0;

        final result = await repository.indexAllBooks(
          library,
          onProgress: (_, _) => progressCalls++,
        );

        expect(result, isFalse);
        expect(engine.commitCount, 0);
        expect(engine.rollbackCount, 1);
        // הספר השלישי לא עובד — הריצה נעצרה מיד אחרי הכשל.
        expect(engine.addedDocuments.map((d) => d.title), isNot(contains('ג')));
        // המעקב בזיכרון נטען מחדש מהמצב החתום (ריק) — 'א' הלא-חתום ינוסה שוב.
        expect(provider.indexedFilePaths, isEmpty);
        expect(progressCalls, greaterThan(0));
      },
    );
  });

  group('IndexingRepository.orderBooksForIndexing', () {
    test('ספרי PDF נדחפים לסוף, סדר שאר הספרים נשמר', () {
      final t1 = TextBook(title: 'א');
      final pdf1 = PdfBook(title: 'ב', path: r'C:\b.pdf');
      final t2 = TextBook(title: 'ג');
      final pdf2 = PdfBook(title: 'ד', path: r'C:\d.pdf');

      expect(
        IndexingRepository.orderBooksForIndexing([t1, pdf1, t2, pdf2]),
        [t1, t2, pdf1, pdf2],
      );
    });
  });

  group('IndexingRepository.chronologicalOrderForBook', () {
    test('ספר יסוד קודם לפירוש גם כשהפירוש שייך לדור מוקדם', () {
      final source = TextBook(
        title: 'שבת',
        categoryPath: 'משנה, סדר מועד',
      );
      final commentary = TextBook(
        title: 'פירוש המגן על שבת',
        categoryPath: 'משנה, ראשונים, ברטנורא, סדר מועד',
      );

      expect(
        IndexingRepository.chronologicalOrderForBook(source),
        lessThan(IndexingRepository.chronologicalOrderForBook(commentary)),
      );
    });

    test('פירוש תחת קטגוריית יסוד אינו מסווג כספר יסוד', () {
      final commentary = TextBook(
        title: 'הסולם על ספר הזהר',
        categoryPath: 'קבלה, זהר',
      );

      expect(IndexingRepository.foundationalTierForBook(commentary), isNull);
    });
  });

  group('IndexingRepository.buildCatalogueDocumentId', () {
    test('נותן עדיפות לסדר הספר לפני הסדר הפנימי בתוך הספר', () {
      final earlierBookLateSegment =
          IndexingRepository.buildCatalogueDocumentId(
            catalogueOrder: 0,
            ordinal: 500,
          );
      final laterBookFirstSegment = IndexingRepository.buildCatalogueDocumentId(
        catalogueOrder: 1,
        ordinal: 0,
      );

      expect(earlierBookLateSegment, lessThan(laterBookFirstSegment));
    });
  });

  group('IndexingRepository.catalogueOrderKey', () {
    test('מבדיל בין קבצי PDF עם אותו שם לפי הנתיב בפועל', () {
      final first = PdfBook(
        title: 'שבת',
        path: r'C:\books\a.pdf',
        categoryPath: 'תלמוד בבלי, סדר מועד',
      );
      final second = PdfBook(
        title: 'שבת',
        path: r'C:\books\b.pdf',
        categoryPath: 'תלמוד בבלי, סדר מועד',
      );

      expect(
        IndexingRepository.catalogueOrderKey(first),
        isNot(IndexingRepository.catalogueOrderKey(second)),
      );
    });

    test('מבדיל בין ספר רשמי לספר אישי עם אותו id (חפיפת AUTOINCREMENT)', () {
      // id טבעי זהה בשני ה-DB — בלי תיוג המקור הספר האישי מדולג באינדוקס.
      final official = TextBook(id: 5, title: 'שבת');
      final userBook = TextBook(id: 5, title: 'הערות אישיות', isUserBook: true);

      expect(IndexingRepository.catalogueOrderKey(official), 'id:5');
      expect(IndexingRepository.catalogueOrderKey(userBook), 'uid:5');
    });
  });

  group('IndexingRepository.buildIndexedBookFilePath', () {
    test('PdfBook ממופה לנתיב הקובץ, ספר טקסט למפתח הקטלוג', () {
      // המפתח הזה הוא שדה filePath של המסמכים באינדקס, ולכן הוא הבסיס
      // לשחזור מצב האינדוקס מהאינדקס עצמו (getIndexedFilePaths).
      final pdf = PdfBook(
        title: 'שבת',
        path: r'C:\books\a.pdf',
        categoryPath: 'תלמוד בבלי, סדר מועד',
      );
      final text = TextBook(title: 'בראשית');

      expect(IndexingRepository.buildIndexedBookFilePath(pdf), pdf.path);
      expect(
        IndexingRepository.buildIndexedBookFilePath(text),
        IndexingRepository.catalogueOrderKey(text),
      );
    });
  });

  group('IndexingRepository.isIndexableBook', () {
    test('DocxBook נכלל באינדוקס דרך מיפוי ל-TextBook', () {
      // רגרסיה: לפני התיקון `isIndexableBook` החזיר false ל-DocxBook,
      // אז `IndexingBloc` סינן אותו לפני indexAllBooks וקבצי DOCX לא נכנסו
      // לאינדקס הטנטיווי. עכשיו הוא ממופה ל-TextBook באמצעות `toTextBook()`
      // ו-`book.text` מחלץ את התוכן דרך docxToText ב-DatabaseLibraryProvider.
      final docx = DocxBook(
        id: 1,
        title: 'בדיקה',
        path: r'C:\library\בדיקה.docx',
        categoryId: 10,
      );
      expect(IndexingRepository.isIndexableBook(docx), isTrue);
    });

    test('TextBook ו-PdfBook נשארים אינדוקסיביליים', () {
      expect(
        IndexingRepository.isIndexableBook(TextBook(title: 'א')),
        isTrue,
      );
      expect(
        IndexingRepository.isIndexableBook(
          PdfBook(title: 'א', path: r'C:\a.pdf'),
        ),
        isTrue,
      );
    });

    test('ExternalLibraryBook לא אינדוקסיבילי', () {
      final external = ExternalLibraryBook(
        title: 'אוצר',
        id: 999,
        link: 'https://example.com',
      );
      expect(IndexingRepository.isIndexableBook(external), isFalse);
    });
  });

  group('DocxBook ↔ TextBook(wrap) — עקביות מפתח קטלוג', () {
    test('catalogueOrderKey זהה ל-DocxBook ול-TextBook העטוף עם id', () {
      // קריטי: שני המפתחות חייבים להיות זהים כדי שבדיקת isBookIndexed
      // (לפי filePath שנקרא מהאינדקס) תזהה אותו ספר בלי לכפול
      // את האינדוקס בהפעלות חוזרות.
      final docx = DocxBook(
        id: 42,
        title: 'בדיקה',
        path: r'C:\library\בדיקה.docx',
        categoryId: 7,
      );
      expect(
        IndexingRepository.catalogueOrderKey(docx),
        IndexingRepository.catalogueOrderKey(docx.toTextBook()),
      );
    });

    test(
      'catalogueOrderKey זהה גם ללא id (נופל ל-title|category|docx|path)',
      () {
        // FileBook משתמש ב-`book.path` ב-pathKey, ו-TextBook (לא FileBook)
        // משתמש ב-`book.filePath`. `toTextBook()` מעביר `filePath ?? path`,
        // כך שהמפתח נשאר עקבי גם בלי id.
        final docx = DocxBook(
          title: 'בדיקה ללא id',
          path: r'C:\library\בדיקה.docx',
          categoryPath: 'ספרים אישיים',
        );
        expect(
          IndexingRepository.catalogueOrderKey(docx),
          IndexingRepository.catalogueOrderKey(docx.toTextBook()),
        );
      },
    );
  });

  group('IndexingRepository.optimizeIndexBestEffort', () {
    test('מחזיר true כש-optimize מצליח', () async {
      var called = false;

      final completed = await IndexingRepository.optimizeIndexBestEffort(
        () async {
          called = true;
        },
      );

      expect(called, isTrue);
      expect(completed, isTrue);
    });

    test('מחזיר false ולא זורק כש-optimize נכשל אחרי commit', () async {
      Object? reportedError;

      final completed = await IndexingRepository.optimizeIndexBestEffort(
        () async {
          throw StateError('maintenance failed');
        },
        onFailure: (error, _) {
          reportedError = error;
        },
      );

      expect(completed, isFalse);
      expect(reportedError, isA<StateError>());
    });
  });
}

class FakeTantivyDataProvider implements TantivyDataProvider {
  FakeTantivyDataProvider({
    required this.indexedFilePaths,
    required this._requiresManualReindexValue,
  });

  final bool _requiresManualReindexValue;

  @override
  bool isTempFallback = false;

  @override
  final Set<String> indexedFilePaths;

  @override
  bool get requiresManualReindex => _requiresManualReindexValue;

  @override
  Future<SearchEngine> get engine async => _FakeSearchEngine();

  @override
  set engine(Future<SearchEngine> value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

class _FakeSearchEngine implements SearchEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

/// ספק עם מנוע יציב המקליט קריאות — לבדיקת ניקוי רשומות אינדקס שהועברו.
class _RecordingTantivyDataProvider implements TantivyDataProvider {
  _RecordingTantivyDataProvider(this._engine);

  final _RecordingSearchEngine _engine;

  int reopenCount = 0;
  bool? lastReopenForce;

  @override
  bool isTempFallback = false;

  @override
  final Set<String> indexedFilePaths = {};

  /// כמו האמיתי: reader טרי + טעינת המעקב מחדש מהמצב החתום של האינדקס.
  @override
  Future<bool> reopenIndex({bool force = false}) async {
    reopenCount++;
    lastReopenForce = force;
    indexedFilePaths
      ..clear()
      ..addAll(await _engine.getIndexedFilePaths());
    return true;
  }

  @override
  final ValueNotifier<bool> isIndexing = ValueNotifier<bool>(false);

  @override
  bool get requiresManualReindex => false;

  @override
  Future<SearchEngine> get engine async => _engine;

  @override
  set engine(Future<SearchEngine> value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

/// מדמה אתחול מנוע שנופל ל-temp fallback: הדגל נדלק רק כשממתינים למנוע —
/// כמו במציאות, שבה האתחול רץ ברקע והכשל מתגלה רק בסיומו.
class _DelayedTempFallbackProvider extends _RecordingTantivyDataProvider {
  _DelayedTempFallbackProvider(super.engine);

  @override
  Future<SearchEngine> get engine async {
    await Future<void>.delayed(Duration.zero);
    isTempFallback = true;
    return super.engine;
  }
}

/// עוקף את indexBooks כדי לבדוק את reindexChangedBooks בבידוד: הרחבת
/// הכותרות והמחיקה אמיתיות, האינדוקס עצמו רק מוקלט.
class _ReindexProbeRepository extends IndexingRepository {
  _ReindexProbeRepository(super.provider);

  List<Book>? indexedBooks;

  @override
  Future<bool> indexBooks(
    List<Book> books,
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
  }) async {
    indexedBooks = books;
    return true;
  }
}

/// מחליף את חילוץ ה-PDF (pdfrx) בתוכן מזויף — לבדיקת צינור ה-prefetch
/// והניקוז המוקדם בלי קבצים אמיתיים.
class _FakeExtractionRepository extends IndexingRepository {
  _FakeExtractionRepository(super.provider);

  final extractedTitles = <String>[];

  @override
  Future<PdfExtraction> extractPdfPagesGuarded(PdfBook book) async {
    extractedTitles.add(book.title);
    final PdfExtraction extraction = (
      pages: [
        (reference: '${book.title}, עמוד 1', text: 'תוכן', pageIndex: 0),
      ],
      outline: const [],
      error: null,
      stackTrace: null,
      extractMs: 0,
    );
    return extraction;
  }
}

class _RecordingSearchEngine implements SearchEngine {
  final List<String> removedFilePaths = [];
  final List<DocumentInput> addedDocuments = [];
  final List<String> addedPdfTitles = [];
  int commitCount = 0;

  /// כתיבת PDF בעל כותרת זו נכשלת — לבדיקת מסלול הכשל בניקוז המוקדם.
  String? failPdfAddForTitle;

  /// נקרא בכל כתיבת PDF — ליומן אירועים משולב עם דיווחי ההתקדמות.
  void Function(String title)? onPdfAdded;

  @override
  Future<int> addPdfBook({
    required String title,
    required String topics,
    required String filePath,
    required int catalogueOrder,
    required int generationOrder,
    required List<PdfPageInput> pages,
    List<String>? extraFacets,
  }) async {
    addedPdfTitles.add(title);
    onPdfAdded?.call(title);
    if (title == failPdfAddForTitle) {
      throw StateError('engine pdf write failed');
    }
    return pages.length;
  }

  /// טביעות-אצבע פר-ספר שהמנוע "קרא מהאינדקס" — לבדיקות reconcile.
  Map<String, BigInt> fingerprints = {};

  /// כתיבת ספר בעל כותרת זו נכשלת אחרי שמסמכיו כבר נרשמו — מדמה כשל מנוע
  /// באמצע כתיבת ספר, שמשאיר מסמכים חלקיים בחוצץ.
  String? failAddForTitle;

  /// מדמה writer פגוע: גם מחיקת מסמכים נכשלת.
  bool failDeleteFilePaths = false;

  /// המחיקה מצליחה אך ה-commit שאחריה נכשל.
  bool failCommit = false;

  int rollbackCount = 0;

  /// המצב ה"חתום" של האינדקס — מה ש-getIndexedFilePaths מחזיר אחרי rollback.
  List<String> committedFilePaths = [];

  @override
  Future<void> addDocumentsBatch({required List<DocumentInput> docs}) async {
    addedDocuments.addAll(docs);
    if (failAddForTitle != null &&
        docs.any((d) => d.title == failAddForTitle)) {
      throw StateError('engine write failed');
    }
  }

  @override
  Future<void> rollback() async {
    rollbackCount++;
  }

  @override
  Future<List<String>> getIndexedFilePaths() async => committedFilePaths;

  @override
  Future<void> setBulkIndexing({required bool enabled}) async {}

  @override
  Future<void> optimize() async {}

  @override
  Future<void> deleteDocumentsByFilePaths({
    required List<String> filePaths,
  }) async {
    if (failDeleteFilePaths) {
      throw StateError('engine delete failed');
    }
    removedFilePaths.addAll(filePaths);
  }

  @override
  Future<void> commit() async {
    if (failCommit) {
      throw StateError('engine commit failed');
    }
    commitCount++;
  }

  @override
  Future<Map<String, BigInt>> getBookFingerprints() async => fingerprints;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

Library _buildLibrary({
  required List<(String, int)> bavliBooks,
  List<Book> additionalBooks = const [],
}) {
  final library = Library(categories: []);
  final tanakh = Category(
    title: 'תנ"ך',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: library,
  );
  final bavli = Category(
    title: 'תלמוד בבלי',
    description: '',
    shortDescription: '',
    order: 2,
    subCategories: [],
    books: [],
    parent: library,
  );
  library.subCategories.addAll([tanakh, bavli]);

  tanakh.books.add(
    TextBook(title: 'בראשית', order: 1, category: tanakh),
  );

  bavli.books.addAll(
    bavliBooks
        .map(
          (entry) => TextBook(
            title: entry.$1,
            order: entry.$2,
            category: bavli,
          ),
        )
        .toList(),
  );

  library.books.addAll(additionalBooks);

  return library;
}
