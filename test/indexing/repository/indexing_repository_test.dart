import 'package:otzaria/data/book_identity.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart' show MaterialApp, SizedBox;
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../support/fake_line_source_engine.dart';

import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/models/index_check_scope.dart';
import 'package:otzaria/indexing/models/index_commit_policy.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'package:otzaria/indexing/utils/pdf_extraction_prefetcher.dart';
import 'package:otzaria/indexing/utils/pending_reindex_store.dart';
import 'package:otzaria/indexing/utils/book_source_hashes.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/utils/refresh_indexing_plan.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    IndexingCrashCanary.writeLog = (_) {};
    IndexingRepository.contentFingerprint = _fakeContentFingerprint;
  });
  tearDown(() {
    IndexingCrashCanary.writeLog = ErrorLogFile.appendText;
    IndexingRepository.contentFingerprint = computeContentFingerprintBytes;
  });
  group('הסתרות ואינדקס מלא', () {
    test('סטטוס כולל מהדורה גלויה מחוץ לעץ ומחריג קטגוריה מוסתרת', () async {
      final library = Library(categories: []);
      final hidden = TextBook(id: 1, title: 'מוסתר');
      final version = TextBook(id: 2, title: 'גרסה', source: BookSource.user);
      final category = Category(
        title: 'סגור',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [hidden],
        parent: library,
      );
      library.subCategories.add(category);
      library.offTreeBooks = [version];
      final provider = _RecordingTantivyDataProvider(_RecordingSearchEngine());
      final repository = IndexingRepository(
        provider,
        hiddenStore: _FixedHiddenStore(
          HiddenLibrarySelection(categoryPaths: {category.path}),
        ),
      );

      expect(await repository.hasUnindexedBooks(library), isTrue);
      provider.indexedFilePaths.add(
        BookIdentity.indexedFilePath(version),
      );
      expect(await repository.hasUnindexedBooks(library), isFalse);
    });

    test('אינדוקס נקודתי ואינדוקס מחדש אינם כותבים קטגוריה מוסתרת', () async {
      final library = Library(categories: []);
      final hidden = TextBook(id: 1, title: 'מוסתר');
      final visible = TextBook(id: 2, title: 'גלוי', source: BookSource.user);
      final category = Category(
        title: 'סגור',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [hidden],
        parent: library,
      );
      library.subCategories.add(category);
      library.books.add(visible);
      final store = _FixedHiddenStore(
        HiddenLibrarySelection(categoryPaths: {category.path}),
      );
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(
        provider,
        hiddenStore: store,
      );

      await repository.runIndexing(
        library,
        books: [hidden, visible],
        onProgress: (_, _) {},
      );
      expect(engine.committedCounts.keys, {
        BookIdentity.indexedFilePath(visible),
      });

      final probe = _ReindexProbeRepository(provider, hiddenStore: store);
      await _reindex(
        probe,
        [hidden, visible],
        library,
        onProgress: (_, _) {},
      );
      expect(probe.indexedBooks, [visible]);
      expect(engine.removedFilePaths, [
        BookIdentity.indexedFilePath(visible),
      ]);
    });

    test('ניקוי מוסתרים נוגע רק ברשומות קיימות ושומר ספר אישי גלוי', () async {
      final library = Library(categories: []);
      final hidden = TextBook(id: 5, title: 'שבת');
      final visible = TextBook(id: 5, title: 'שבת', source: BookSource.user);
      library.books.addAll([hidden, visible]);
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      provider.indexedFilePaths.addAll([
        BookIdentity.indexedFilePath(hidden),
        BookIdentity.indexedFilePath(visible),
      ]);
      final store = _FixedHiddenStore(
        HiddenLibrarySelection(
          bookKeys: {PerBookSettings.bookKey(hidden)},
        ),
      );
      final repository = IndexingRepository(provider, hiddenStore: store);

      expect(await repository.dropHiddenIndexEntries(library), isTrue);
      expect(engine.removedFilePaths, ['id:5']);
      expect(provider.indexedFilePaths, {'uid:5'});
      expect(await repository.dropHiddenIndexEntries(library), isTrue);
      expect(engine.removedFilePaths, ['id:5']);
    });

    test('כשל מחיקת ספר מוסתר מוחזר ללא ניקוי המעקב', () async {
      final book = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.add(book);
      final engine = _RecordingSearchEngine()..failCommit = true;
      final provider = _RecordingTantivyDataProvider(engine);
      provider.indexedFilePaths.add('id:5');
      engine.committedFilePaths = ['id:5'];
      final repository = IndexingRepository(
        provider,
        hiddenStore: _FixedHiddenStore(
          HiddenLibrarySelection(
            bookKeys: {PerBookSettings.bookKey(book)},
          ),
        ),
      );

      expect(await repository.dropHiddenIndexEntries(library), isFalse);
      expect(provider.indexedFilePaths, {'id:5'});
    });
  });

  group('IndexingRepository.shouldCommitCancelledRun', () {
    test('ביטול רגיל — הספרים שכבר נכתבו נחתמים', () {
      // רגרסיה: בלי commit בביטול, כל ריצה שנקטעה התחילה מה-commit
      // האחרון ואינדקסה מאפס עד מאות ספרים.
      expect(
        IndexingRepository.shouldCommitCancelledRun(
          pendingBooks: 42,
          writeBufferDiscarded: false,
        ),
        isTrue,
      );
    });

    test('כשל כתיבה — החוצץ הושלך ואסור לחתום מצב חלקי', () {
      expect(
        IndexingRepository.shouldCommitCancelledRun(
          pendingBooks: 42,
          writeBufferDiscarded: true,
        ),
        isFalse,
      );
    });

    test('אין מה לחתום — לא נוגעים במנוע', () {
      expect(
        IndexingRepository.shouldCommitCancelledRun(
          pendingBooks: 0,
          writeBufferDiscarded: false,
        ),
        isFalse,
      );
    });
  });

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

  group('IndexingRepository.hasUnindexedBooks', () {
    test(
      'מחזיר false כשכל הספרים מאונדקסים - מונע אינדוקס מלא בכל עלייה',
      () async {
        final provider = _RecordingTantivyDataProvider(
          _RecordingSearchEngine(),
        );
        final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
        provider.indexedFilePaths.addAll(
          library
              .getAllBooks()
              .where(IndexingRepository.isIndexableBook)
              .map(BookIdentity.indexedFilePath),
        );

        expect(
          await IndexingRepository(provider).hasUnindexedBooks(library),
          isFalse,
        );
      },
    );

    test('מחזיר true כשספר אינדקסבילי חסר מהאינדקס', () async {
      final provider = _RecordingTantivyDataProvider(_RecordingSearchEngine());
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);

      expect(
        await IndexingRepository(provider).hasUnindexedBooks(library),
        isTrue,
      );
    });

    test('מחזיר false בספרייה ריקה - אין עבודה להריץ', () async {
      final provider = _RecordingTantivyDataProvider(_RecordingSearchEngine());

      expect(
        await IndexingRepository(
          provider,
        ).hasUnindexedBooks(Library(categories: [])),
        isFalse,
      );
    });

    test('ספר שאינו בר-אינדוקס אינו נספר כחסר', () async {
      final provider = _RecordingTantivyDataProvider(_RecordingSearchEngine());
      final library = Library(categories: []);
      library.books.add(
        ExternalLibraryBook(
          title: 'ספר חיצוני',
          id: 902,
          link: 'https://example.com/ext',
        ),
      );

      expect(
        await IndexingRepository(provider).hasUnindexedBooks(library),
        isFalse,
      );
    });
  });

  group('BookIdentity.hasPathKeyedIndexEntry', () {
    test('PdfBook בלי מזהה חיצוני מאונדקס לפי נתיב (גם עם id)', () {
      expect(
        BookIdentity.hasPathKeyedIndexEntry(
          PdfBook(title: 'ברכות', path: r'C:\lib\ברכות.pdf'),
        ),
        isTrue,
      );
      expect(
        BookIdentity.hasPathKeyedIndexEntry(
          PdfBook(title: 'ברכות', path: r'C:\lib\ברכות.pdf', id: 5),
        ),
        isTrue,
        reason: 'id של PDF תלמוד שאול מספר הטקסט — אינו זהות משלו',
      );
    });

    test('PdfBook עם מזהה חיצוני שורד העברה', () {
      expect(
        BookIdentity.hasPathKeyedIndexEntry(
          PdfBook(
            title: 'שער המלך',
            path: r'C:\lib\external\שער המלך.pdf',
            externalLibraryId: 'hb:14127',
          ),
        ),
        isFalse,
      );
    });

    test('DocxBook ללא id — לפי נתיב; עם id — שורד העברה', () {
      expect(
        BookIdentity.hasPathKeyedIndexEntry(
          DocxBook(title: 'מסמך', path: r'C:\lib\doc.docx'),
        ),
        isTrue,
      );
      expect(
        BookIdentity.hasPathKeyedIndexEntry(
          DocxBook(title: 'מסמך', path: r'C:\lib\doc.docx', id: 7),
        ),
        isFalse,
      );
    });

    test('TextBook מ-DB — לא לפי נתיב', () {
      expect(
        BookIdentity.hasPathKeyedIndexEntry(TextBook(title: 'שבת')),
        isFalse,
      );
    });
  });

  group('BookIdentity.indexedFilePath', () {
    test('ספר עם מזהה חיצוני מאונדקס לפי המזהה ולא לפי הנתיב', () {
      final onBuildMachine = PdfBook(
        title: 'שער המלך',
        path: r'D:\build\library\שער המלך.pdf',
        externalLibraryId: 'hb:14127',
      );
      final afterInstall = PdfBook(
        title: 'שער המלך',
        path: r'C:\Users\dovid\otzaria\library\שער המלך.pdf',
        externalLibraryId: 'hb:14127',
      );

      expect(
        BookIdentity.indexedFilePath(onBuildMachine),
        'ext:hb:14127',
      );
      expect(
        BookIdentity.indexedFilePath(afterInstall),
        BookIdentity.indexedFilePath(onBuildMachine),
        reason: 'אינדקס בנוי מראש חייב להתאים גם כשנתיב ההתקנה שונה',
      );
    });

    test('‏PDF של תלמוד אינו מתנגש בספר הטקסט ששאל ממנו את ה-id', () {
      final pdf = PdfBook(id: 42, title: 'ברכות', path: r'C:\lib\ברכות.pdf');
      final text = TextBook(id: 42, title: 'ברכות');

      expect(BookIdentity.indexedFilePath(pdf), pdf.path);
      expect(BookIdentity.indexedFilePath(text), 'id:42');
    });

    test('מסכת PDF מהתיקייה המצורפת שורדת נתיב התקנה אחר', () {
      PdfBook masechet(String path) => PdfBook(
        id: 42,
        title: 'ברכות',
        path: path,
        externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
          'ברכות',
        ),
      );

      expect(
        BookIdentity.indexedFilePath(
          masechet(r'D:\build\library\תלמוד בבלי\ברכות.pdf'),
        ),
        'ext:talmud-pdf:ברכות',
      );
      expect(
        BookIdentity.indexedFilePath(
          masechet(r'C:\Users\dovid\otzaria\תלמוד בבלי\ברכות.pdf'),
        ),
        'ext:talmud-pdf:ברכות',
      );
      expect(
        BookIdentity.indexedFilePath(
          TextBook(id: 42, title: 'ברכות'),
        ),
        'id:42',
        reason: 'ה-id שאול מספר הטקסט — שני הספרים חייבים מפתחות נפרדים',
      );
    });

    test('indexedPdfFilePath מסכים עם buildIndexedBookFilePath', () {
      final withExternalId = PdfBook(
        id: 42,
        title: 'ברכות',
        path: r'C:\otzaria\תלמוד בבלי\ברכות.pdf',
        externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
          'ברכות',
        ),
      );
      final pathKeyed = PdfBook(
        title: 'ספר סרוק',
        path: r'C:\otzaria\אישי\ספר סרוק.pdf',
      );

      for (final book in [withExternalId, pathKeyed]) {
        expect(
          BookIdentity.indexedPdfFilePath(
            externalLibraryId: book.externalLibraryId,
            filePath: book.path,
          ),
          BookIdentity.indexedFilePath(book),
          reason: 'שני המפתחות מפצלים את הספר לשתי זהויות אם הם נפרדים',
        );
      }
    });

    test('ספר DOCX עם מזהה חיצוני מאונדקס לפי המזהה', () {
      expect(
        BookIdentity.indexedFilePath(
          DocxBook(
            title: 'אבן הבורר',
            path: r'D:\build\library\אבן הבורר.docx',
            externalLibraryId: 'hb:20553',
          ),
        ),
        'ext:hb:20553',
      );
    });
  });

  group('אינדקס בנוי מראש אחרי התקנה', () {
    List<Book> shippedLibraryAt(String root) => [
      TextBook(id: 7, title: 'בראשית'),
      TextBook(id: 8, title: 'שמות'),
      PdfBook(
        id: 42,
        title: 'ברכות',
        path: '$root/תלמוד בבלי/ברכות.pdf',
        externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
          'ברכות',
        ),
      ),
      PdfBook(
        id: 43,
        title: 'שבת',
        path: '$root/תלמוד בבלי/שבת.pdf',
        externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
          'שבת',
        ),
      ),
    ];

    Set<String> keysOf(List<Book> books) => {
      for (final book in books)
        if (IndexingRepository.isIndexableBook(book))
          BookIdentity.indexedFilePath(book),
    };

    test('כל ספר בחבילה מאונדקס, ולכן אין אינדוקס אצל המשתמש', () {
      // אינדקס שנבנה במכונת ה-CI, ואותה ספרייה בנתיב שהמשתמש בחר.
      expect(
        keysOf(shippedLibraryAt(r'D:\אוצריא\books')),
        keysOf(shippedLibraryAt('/ci/full_installer/books')),
        reason: 'מפתח שתלוי בנתיב ההתקנה מחזיר את המשתמש לאינדוקס מלא',
      );
    });

    test('ספר PDF שנוסף אחרי הבנייה כן דורש אינדוקס', () {
      final added = PdfBook(
        title: 'ספר שהמשתמש הוסיף',
        path: r'D:\אוצריא\books\א.pdf',
      );
      expect(
        keysOf(shippedLibraryAt('/ci/full_installer/books')),
        isNot(contains(BookIdentity.indexedFilePath(added))),
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
      final key = BookIdentity.indexedFilePath(book);
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
        final key = BookIdentity.indexedFilePath(book);
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
        BookIdentity.indexedFilePath(book),
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
      final personal = TextBook(id: 5, title: 'שבת', source: BookSource.user);
      provider.indexedFilePaths.addAll([
        BookIdentity.indexedFilePath(official),
        BookIdentity.indexedFilePath(personal),
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
      final existing = TextBook(id: 1, title: 'שבת', source: BookSource.user);
      final library = _buildLibrary(bavliBooks: const []);
      library.books.add(existing);

      provider.indexedFilePaths.addAll({
        BookIdentity.indexedFilePath(existing), // בספרייה
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
        BookIdentity.indexedFilePath(existing),
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

    test('מפתח תחת תיקייה אישית שאינה נגישה — לא נמחק', () async {
      // רגרסיה (issue #1295): כונן חיצוני מנותק ⇒ הקובץ לא קיים והספר אינו
      // בספרייה, והמפתח נמחק — כל חיבור גרר אינדוקס מחדש.
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);

      final sep = io.Platform.pathSeparator;
      final detachedRoot =
          '${io.Directory.systemTemp.path}${sep}detached-drive';
      final detachedKey =
          '$detachedRoot$sep'
          'ספר.pdf';
      final missingKey =
          '${io.Directory.systemTemp.path}${sep}definitely-missing$sep'
          'אחר.pdf';
      provider.indexedFilePaths.addAll({detachedKey, missingKey});
      final repository = IndexingRepository(provider);

      final removed = await repository.dropOrphanedIndexEntries(
        library,
        customFolders: [
          CustomFolder(path: detachedRoot, addedAt: DateTime(2026)),
        ],
      );

      expect(removed, 1);
      expect(engine.removedFilePaths, [missingKey]);
      expect(provider.indexedFilePaths, {detachedKey});
    });

    test('קובץ שנמחק בתוך תיקייה אישית קיימת — נמחק כרגיל', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);

      final root = await io.Directory.systemTemp.createTemp('otzaria-folder');
      addTearDown(() => root.delete(recursive: true));
      final deletedKey = p.join(root.path, 'נמחק.pdf');
      provider.indexedFilePaths.add(deletedKey);
      final repository = IndexingRepository(provider);

      final removed = await repository.dropOrphanedIndexEntries(
        library,
        customFolders: [CustomFolder(path: root.path, addedAt: DateTime(2026))],
      );

      expect(removed, 1);
      expect(engine.removedFilePaths, [deletedKey]);
      expect(provider.indexedFilePaths, isEmpty);
    });

    test('תיקייה אישית מוסתרת — נשמרים רק מפתחותיה', () async {
      // ספרי תיקייה מוסתרת מדולגים בבניית העץ ולכן נראים יתומים; מחיקתם
      // הייתה גוררת אינדוקס מלא בהחזרת התיקייה. ספר שנמחק מתיקייה גלויה
      // אינו שייך לתיקייה המוסתרת וחייב להימחק גם באותו מצב.
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);

      final root = await io.Directory.systemTemp.createTemp('otzaria-hidden');
      addTearDown(() => root.delete(recursive: true));
      provider.indexedFilePaths.addAll({'uid:99', 'uid:100'});
      final repository = IndexingRepository(provider);

      final removed = await repository.dropOrphanedIndexEntries(
        library,
        customFolders: [
          CustomFolder(path: root.path, hidden: true, addedAt: DateTime(2026)),
        ],
        preservedHiddenUserBookKeys: {'uid:99'},
      );

      expect(removed, 1);
      expect(engine.removedFilePaths, ['uid:100']);
      expect(provider.indexedFilePaths, {'uid:99'});
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
        final existing = TextBook(id: 1, title: 'שבת', source: BookSource.user);
        final library = _buildLibrary(bavliBooks: const []);
        library.books.add(existing);
        final existingKey = BookIdentity.indexedFilePath(
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

  group('IndexingRepository.runIndexing — החלפת ספרים שהשתנו', () {
    late io.Directory indexDir;

    setUp(() async {
      PendingReindexStore.resetMemoryForTesting();
      indexDir = await io.Directory.systemTemp.createTemp('otzaria_replace');
    });

    tearDown(() async {
      PendingReindexStore.resetMemoryForTesting();
      await indexDir.delete(recursive: true);
    });

    String keyOf(Book book) => BookIdentity.indexedFilePath(book);

    _RecordingTantivyDataProvider providerWith(
      _CancellationRecordingEngine engine,
      List<Book> committed,
    ) {
      final provider = _RecordingTantivyDataProvider(engine)
        ..activeIndexPath = indexDir.path;
      for (final book in committed) {
        provider.indexedFilePaths.add(keyOf(book));
        engine.committedCounts[keyOf(book)] = 1;
      }
      engine.committedFilePaths = provider.indexedFilePaths.toList();
      return provider;
    }

    Future<Set<String>> storedPending() =>
        PendingReindexStore.forIndex(indexDir.path)!.load();

    io.File pendingFile() =>
        io.File(p.join(indexDir.path, PendingReindexStore.fileName));

    test(
      'בדיקה מלאה שנדחתה נשארת בחיווי אחרי שחזור ספר מהסתרה',
      () async {
        await Settings.init(cacheProvider: MemoryCacheProvider());
        const hiddenStore = HiddenLibraryStore();
        await hiddenStore.resetRuntimeStateForAppRestart();
        addTearDown(() async {
          await hiddenStore.resetRuntimeStateForAppRestart();
          await Settings.clearCache();
        });
        final engine = _CancellationRecordingEngine();
        final stale = TextBook(id: 5, title: 'שבת');
        final newlyVisible = TextBook(id: 6, title: 'עירובין');
        final library = Library(categories: [])
          ..books.addAll([stale, newlyVisible]);
        final provider = providerWith(engine, [stale]);
        final repository = _ReindexProbeRepository(provider);
        final bloc = IndexingBloc(repository);
        addTearDown(bloc.close);
        final states = <IndexingState>[];
        final subscription = bloc.stream.listen(states.add);
        addTearDown(subscription.cancel);

        for (final event in buildRefreshIndexingPlan(
          library: library,
          newBooks: const [],
          changedBooks: const [],
          indexWholeLibrary: true,
          reconcile: true,
          indexUpdateMode: IndexUpdateMode.off,
        )) {
          bloc.add(event);
        }
        final deferred = Completer<void>();
        bloc.add(IndexingWorkBarrier(onSettled: deferred.complete));
        await deferred.future.timeout(const Duration(seconds: 2));
        expect(bloc.state, isA<IndexingInitial>());

        final revision = await hiddenStore.beginVisibilityIndexUpdate();
        final completions = <bool>[];
        bloc.add(
          ApplyHiddenIndexDelta(
            library,
            newlyHidden: const [],
            newlyVisible: [newlyVisible],
            visibilityRevision: revision,
            onCompleted: completions.add,
          ),
        );
        final settled = Completer<void>();
        bloc.add(IndexingWorkBarrier(onSettled: settled.complete));
        await settled.future.timeout(const Duration(seconds: 2));

        expect(
          await PendingReindexStore.forIndex(
            indexDir.path,
          )!.checkLibraryPending(),
          isTrue,
        );
        expect(await repository.hasUnindexedBooks(library), isTrue);
        expect(repository.indexedBooks, [newlyVisible]);
        expect(completions, [true]);
        expect(hiddenStore.hasPendingVisibilityIndex, isFalse);
        expect(bloc.state, isA<IndexingInitial>());
        expect(states.whereType<IndexingComplete>(), isEmpty);
      },
    );

    test(
      'רענון כשהאינדוקס כבוי שומר שינויים להפעלה הבאה ומעדכן את החיווי',
      () async {
        final engine = _CancellationRecordingEngine();
        final changed = TextBook(id: 5, title: 'שבת');
        final unchanged = TextBook(id: 6, title: 'עירובין');
        final library = Library(categories: [])
          ..books.addAll([changed, unchanged]);
        final provider = providerWith(engine, [changed, unchanged]);
        final repository = _ReindexProbeRepository(provider);
        final bloc = IndexingBloc(repository);
        addTearDown(bloc.close);

        final ready = bloc.stream.firstWhere((s) => s is IndexingComplete);
        bloc.add(CheckIndexStatus(library));
        await ready.timeout(const Duration(seconds: 2));

        for (final event in buildRefreshIndexingPlan(
          library: library,
          newBooks: const [],
          changedBooks: [changed],
          indexWholeLibrary: true,
          reconcile: false,
          indexUpdateMode: IndexUpdateMode.off,
        )) {
          bloc.add(event);
        }
        final deferred = Completer<void>();
        bloc.add(IndexingWorkBarrier(onSettled: deferred.complete));
        await deferred.future.timeout(const Duration(seconds: 2));

        expect(bloc.state, isA<IndexingInitial>());
        expect(repository.indexedBooks, isNull);
        expect(engine.removedFilePaths, isEmpty);
        expect(engine.commitCount, 0);
        expect(await storedPending(), {'id:5'});
        await bloc.close();

        // הזיכרון מתאפס; ההפעלה הבאה קוראת את השינויים מהדיסק.
        PendingReindexStore.resetMemoryForTesting();
        await provider.reopenIndex(force: true);
        final resumedRepository = _ReindexProbeRepository(provider);
        expect(await resumedRepository.hasUnindexedBooks(library), isTrue);
        final resumedBloc = IndexingBloc(resumedRepository);
        addTearDown(resumedBloc.close);
        for (final event in indexUpdateModeChangePlan(
          library,
          previous: IndexUpdateMode.off,
          current: IndexUpdateMode.all,
        )) {
          resumedBloc.add(event);
        }
        final settled = Completer<void>();
        resumedBloc.add(IndexingWorkBarrier(onSettled: settled.complete));
        await settled.future.timeout(const Duration(seconds: 2));

        expect(resumedBloc.state, const IndexingComplete());
        expect(resumedRepository.indexedBooks, [changed]);
        expect(engine.removedFilePaths, ['id:5']);
        expect(engine.commitCount, 1);
        expect(engine.committedCounts, {'id:5': 1, 'id:6': 1});
        expect(pendingFile().existsSync(), isFalse);
      },
    );

    test(
      'מחליף רק את הספרים שהשתנו — לא שכנים בעלי אותה כותרת, ובאותו commit',
      () async {
        final engine = _CancellationRecordingEngine();
        final official = TextBook(id: 5, title: 'שבת');
        final personal = TextBook(id: 9, title: 'שבת', source: BookSource.user);
        final other = TextBook(id: 6, title: 'עירובין');
        final library = _buildLibrary(bavliBooks: const []);
        library.books.addAll([official, personal, other]);
        final provider = providerWith(engine, [official, personal, other]);
        final repository = _ReindexProbeRepository(provider);

        final result = await _reindex(
          repository,
          [official],
          library,
          onProgress: (_, _) {},
        );

        expect(result.completed, isTrue);
        // המחיקה לפי מפתח ה-filePath המדויק — הספר האישי 'שבת' (uid:9) נשאר.
        expect(engine.removedFilePaths, ['id:5']);
        expect(repository.indexedBooks!.single.title, 'שבת');
        expect(repository.indexedBooks!.single.isUserBook, isFalse);
        // מחיקה וכתיבה באותו commit: הספר לא נעלם מהחיפוש בין השתיים.
        expect(engine.commitCount, 1);
        expect(engine.committedCounts, {'id:5': 1, 'uid:9': 1, 'id:6': 1});
        expect(provider.indexedFilePaths, {'id:5', 'uid:9', 'id:6'});
        expect(pendingFile().existsSync(), isFalse);
      },
    );

    test('מאחד בסוף — המסמכים שנמחקו אינם נשארים בדיסק', () async {
      final engine = _CancellationRecordingEngine();
      final changed = TextBook(id: 5, title: 'שבת');
      final library = _buildLibrary(bavliBooks: const []);
      library.books.add(changed);
      final provider = providerWith(engine, [changed]);
      var finalizing = 0;

      await _reindex(
        _ReindexProbeRepository(provider),
        [changed],
        library,
        onProgress: (_, _) {},
        onFinalizing: () => finalizing++,
      );

      expect(engine.optimizeCount, 1);
      expect(finalizing, 1);
    });

    test(
      'ספרים חדשים ושהשתנו נכתבים בריצה אחת, ההתקדמות לפי רשימת העבודה',
      () async {
        final engine = _CancellationRecordingEngine();
        final changed = TextBook(id: 5, title: 'שבת');
        final unchanged = TextBook(id: 6, title: 'עירובין');
        final fresh = TextBook(id: 7, title: 'פסחים');
        final library = Library(categories: [])
          ..books.addAll([changed, unchanged, fresh]);
        final provider = providerWith(engine, [changed, unchanged]);
        final repository = _ReindexProbeRepository(provider);
        final totals = <int>[];
        final progress = <(int, int)>[];

        final result = await repository.runIndexing(
          library,
          changedBooks: [changed],
          onWorkListReady: totals.add,
          onProgress: (p, t) => progress.add((p, t)),
        );

        expect(result.completed, isTrue);
        expect(totals, [2]);
        expect(progress.last, (2, 2));
        expect(repository.indexedBooks!.map((b) => b.title), ['שבת', 'פסחים']);
        expect(engine.commitCount, 1);
        expect(engine.optimizeCount, 1);
        expect(engine.committedCounts, {'id:5': 1, 'id:6': 1, 'id:7': 1});
      },
    );

    test('אין עבודה — לא נוגע במנוע ואינו מדווח רשימת עבודה', () async {
      final engine = _CancellationRecordingEngine();
      final book = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.add(book);
      final provider = providerWith(engine, [book]);
      final totals = <int>[];

      final result = await _ReindexProbeRepository(provider).runIndexing(
        library,
        onWorkListReady: totals.add,
        onProgress: (_, _) => fail('אין התקדמות בלי עבודה'),
      );

      expect(result.completed, isTrue);
      expect(totals, isEmpty);
      expect(engine.commitCount, 0);
      expect(provider.isIndexing.value, isFalse);
    });

    test(
      'כשל במחיקת המסמכים הישנים — נעצר בלי commit ושומר את הסימון',
      () async {
        // רגרסיה: הכשל נבלע והספר הישן נשאר באינדקס, מדווח כהצלחה.
        final engine = _CancellationRecordingEngine()
          ..failDeleteFilePaths = true;
        final changed = TextBook(id: 5, title: 'שבת');
        final library = _buildLibrary(bavliBooks: const []);
        library.books.add(changed);
        final provider = providerWith(engine, [changed]);
        final repository = _ReindexProbeRepository(provider);

        final result = await _reindex(
          repository,
          [changed],
          library,
          onProgress: (_, _) {},
        );

        expect(result.completed, isFalse);
        expect(repository.indexedBooks, isNull);
        expect(engine.commitCount, 0);
        // המעקב נטען מחדש מהאינדקס החתום, והסימון ממתין לניסיון הבא.
        expect(provider.indexedFilePaths, {'id:5'});
        expect(await storedPending(), {'id:5'});
      },
    );

    test(
      'ביטול לפני כתיבת הספר שהשתנה — הריצה הבאה אחרי הפעלה מחדש מחליפה אותו',
      () async {
        final engine = _CancellationRecordingEngine();
        final fresh = TextBook(id: 7, title: 'פסחים');
        final changed = TextBook(id: 5, title: 'שבת');
        final library = Library(categories: [])..books.addAll([fresh, changed]);
        final provider = providerWith(engine, [changed]);
        engine.onTextAdded = (title) {
          if (title == fresh.title) provider.isIndexing.value = false;
        };

        final cancelled = await _ReindexProbeRepository(provider).runIndexing(
          library,
          changedBooks: [changed],
          onProgress: (_, _) {},
        );
        expect(cancelled.completed, isFalse);
        // התוכן הישן נשאר חתום ובר-חיפוש; הסימון נשמר לצד האינדקס.
        expect(engine.committedCounts, {'id:5': 1});
        expect(pendingFile().existsSync(), isTrue);

        // הפעלה מחדש: הזיכרון מתאפס והמעקב נקרא מהאינדקס החתום.
        PendingReindexStore.resetMemoryForTesting();
        engine.onTextAdded = null;
        await provider.reopenIndex(force: true);
        expect(provider.indexedFilePaths, {'id:5'});
        final repository = _ReindexProbeRepository(provider);
        expect(await repository.hasUnindexedBooks(library), isTrue);

        final resumed = await repository.runIndexing(
          library,
          onProgress: (_, _) {},
        );
        expect(resumed.completed, isTrue);
        expect(repository.indexedBooks!.map((b) => b.title), ['פסחים', 'שבת']);
        expect(engine.committedCounts, {'id:5': 1, 'id:7': 1});
        expect(pendingFile().existsSync(), isFalse);
      },
    );

    test('ביטול אחרי שהספר שהשתנה נכתב — נחתם מוחלף ויוצא מהסימון', () async {
      final engine = _CancellationRecordingEngine();
      final changed = TextBook(id: 5, title: 'שבת');
      final fresh = TextBook(id: 7, title: 'פסחים');
      final library = Library(categories: [])..books.addAll([changed, fresh]);
      final provider = providerWith(engine, [changed]);
      engine.onTextAdded = (title) {
        if (title == fresh.title) provider.isIndexing.value = false;
      };

      final result = await _ReindexProbeRepository(provider).runIndexing(
        library,
        changedBooks: [changed],
        onProgress: (_, _) {},
      );

      expect(result.completed, isFalse);
      expect(engine.commitCount, 1);
      expect(engine.committedCounts, {'id:5': 1});
      expect(provider.indexedFilePaths, {'id:5'});
      expect(pendingFile().existsSync(), isFalse);
    });

    test('ספר שזוהה כשונה בבדיקה נשמר בסימון כבר לפני הלולאה', () async {
      final engine = _CancellationRecordingEngine()
        ..fingerprints = {'id:5': BigInt.from(1)};
      final fresh = TextBook(id: 7, title: 'פסחים');
      final changed = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.addAll([fresh, changed]);
      final provider = providerWith(engine, [changed]);
      engine.onTextAdded = (_) => provider.isIndexing.value = false;
      final repository = _ReindexProbeRepository(provider);
      repository.changeDetector = _textDetector(
        repository,
        loadText: (_) async => 'חדש',
        fingerprintOf: (_, _) async => BigInt.from(2),
      );

      final result = await repository.runIndexing(
        library,
        check: IndexCheckScope.library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isFalse);
      expect(await storedPending(), {'id:5'});
    });

    test('ריצה שבוטלה בתור שומרת את הספרים שהשתנו בסימון', () async {
      final engine = _CancellationRecordingEngine();
      final changed = TextBook(id: 5, title: 'שבת');
      final provider = providerWith(engine, [changed]);

      await _ReindexProbeRepository(provider).rememberChangedBooks([changed]);

      expect(await storedPending(), {'id:5'});
      expect(
        await _ReindexProbeRepository(
          provider,
        ).hasUnindexedBooks(Library(categories: [])..books.add(changed)),
        isTrue,
      );
    });

    test('ספר שחזר למעקב באמצע הריצה אינו נמחק ונשאר בסימון', () async {
      // רענון ספרייה טוען מחדש את המעקב מהדיסק בלי להמתין לאינדוקס.
      final engine = _CancellationRecordingEngine();
      final fresh = TextBook(id: 7, title: 'פסחים');
      final changed = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.addAll([fresh, changed]);
      final provider = providerWith(engine, [changed]);
      engine.onTextAdded = (title) {
        if (title == fresh.title) provider.indexedFilePaths.add('id:5');
      };

      final result = await _ReindexProbeRepository(provider).runIndexing(
        library,
        changedBooks: [changed],
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(engine.removedFilePaths, isNot(contains('id:5')));
      expect(engine.committedCounts, {'id:5': 1, 'id:7': 1});
      expect(await storedPending(), {'id:5'});
    });

    test(
      'ביטול לפני כתיבת ספר שהשתנה מחזיר אותו למעקב — הסתרה תסיר אותו',
      () async {
        final engine = _CancellationRecordingEngine();
        final fresh = TextBook(id: 7, title: 'פסחים');
        final changed = TextBook(id: 5, title: 'שבת');
        final library = Library(categories: [])..books.addAll([fresh, changed]);
        final provider = providerWith(engine, [changed]);
        engine.onTextAdded = (title) {
          if (title == fresh.title) provider.isIndexing.value = false;
        };

        await _ReindexProbeRepository(provider).runIndexing(
          library,
          changedBooks: [changed],
          onProgress: (_, _) {},
        );
        expect(provider.indexedFilePaths, contains('id:5'));

        final hiding = _ReindexProbeRepository(
          provider,
          hiddenStore: _FixedHiddenStore(
            HiddenLibrarySelection(
              bookKeys: {PerBookSettings.bookKey(changed)},
            ),
          ),
        );
        expect(await hiding.dropHiddenIndexEntries(library), isTrue);
        expect(engine.removedFilePaths, contains('id:5'));
      },
    );

    test('בדיקה מלאה שנדחתה רצה בריצה הבאה על כל הספרייה, ואז מתנקה', () async {
      final engine = _CancellationRecordingEngine()
        ..fingerprints = {'id:5': BigInt.from(1)};
      final book = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.add(book);
      final provider = providerWith(engine, [book]);
      final repository = _ReindexProbeRepository(provider);
      var checked = 0;
      repository.changeDetector = _textDetector(
        repository,
        loadText: (_) async {
          checked++;
          return 'טקסט';
        },
        fingerprintOf: (_, _) async => BigInt.from(1),
      );

      await repository.rememberChangedBooks(const [], checkLibrary: true);
      expect(await repository.hasUnindexedBooks(library), isTrue);

      final result = await repository.runIndexing(
        library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(checked, 1);
      expect(
        await PendingReindexStore.forIndex(
          indexDir.path,
        )!.checkLibraryPending(),
        isFalse,
      );
      expect(await repository.hasUnindexedBooks(library), isFalse);
    });

    test('בדיקה מלאה שבוטלה באמצע נשמרת לריצה הבאה', () async {
      final engine = _CancellationRecordingEngine()
        ..fingerprints = {'id:5': BigInt.from(1)};
      final book = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.add(book);
      final provider = providerWith(engine, [book]);
      final repository = _ReindexProbeRepository(provider);
      repository.changeDetector = _textDetector(
        repository,
        loadText: (_) async {
          provider.isIndexing.value = false;
          return 'טקסט';
        },
        fingerprintOf: (_, _) async => BigInt.from(1),
      );

      final result = await repository.runIndexing(
        library,
        books: const [],
        check: IndexCheckScope.library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isFalse);
      expect(
        await PendingReindexStore.forIndex(
          indexDir.path,
        )!.checkLibraryPending(),
        isTrue,
      );
    });

    test('commit ביניים מוציא מהסימון רק ספרים שהוחלפו ונחתמו', () async {
      final engine = _CancellationRecordingEngine();
      final first = TextBook(id: 5, title: 'שבת');
      final second = TextBook(id: 6, title: 'עירובין');
      final library = Library(categories: [])..books.addAll([first, second]);
      final provider = providerWith(engine, [first, second]);
      IndexingRepository.newCommitPolicy = () => IndexCommitPolicy(maxDocs: 1);
      addTearDown(
        () => IndexingRepository.newCommitPolicy = IndexCommitPolicy.new,
      );
      Set<String>? pendingDuringSecond;
      engine.onTextAdded = (title) {
        if (title != second.title) return;
        pendingDuringSecond = jsonDecode(
          pendingFile().readAsStringSync(),
        )['keys'].cast<String>().toSet();
        provider.isIndexing.value = false;
      };

      final result = await _ReindexProbeRepository(provider).runIndexing(
        library,
        changedBooks: [first, second],
        onProgress: (_, _) {},
      );

      expect(result.completed, isFalse);
      expect(pendingDuringSecond, {'id:6'});
      // השני נמחק ונכתב בחוצץ, ובביטול נזרק: התוכן הישן נשאר חתום עד הריצה הבאה.
      expect(engine.committedCounts, {'id:5': 1, 'id:6': 1});
      expect(await storedPending(), {'id:6'});
    });

    test('PDF שהשתנה ונוקז מוקדם — מסמכיו הישנים נמחקים לפני כתיבתו', () async {
      final engine = _CancellationRecordingEngine();
      final text1 = TextBook(id: 1, title: 'ט1');
      final text2 = TextBook(id: 2, title: 'ט2');
      final pdf = PdfBook(id: 3, title: 'א', path: r'C:\pdfs\א.pdf');
      final library = Library(categories: [])
        ..books.addAll([text1, text2, pdf]);
      final provider = providerWith(engine, [pdf]);
      final pdfKey = keyOf(pdf);
      final events = <String>[];
      engine.onTextAdded = (title) => events.add('text:$title');
      engine.onPdfAdded = (title) {
        events.add('pdf:$title');
        expect(engine.removedFilePaths, [pdfKey]);
      };

      final result = await _FakeExtractionRepository(provider).runIndexing(
        library,
        changedBooks: [pdf],
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      // נוקז מוקדם: נכתב לפני הספר שהלולאה עמדה עליו.
      expect(events, ['text:ט1', 'pdf:א', 'text:ט2']);
      expect(engine.commitCount, 1);
      expect(engine.committedCounts[pdfKey], 1);
    });

    test(
      'ביטול בזמן כתיבת ספר שהשתנה — נשאר בסימון ונכתב בריצת רענון הבאה',
      () async {
        final engine = _CancellationRecordingEngine();
        final fresh = TextBook(id: 7, title: 'פסחים');
        final changed = TextBook(id: 5, title: 'שבת');
        final later = TextBook(id: 8, title: 'סוכה');
        final library = Library(categories: [])
          ..books.addAll([fresh, changed, later]);
        final provider = providerWith(engine, [changed]);
        engine.onTextAdded = (title) {
          if (title == changed.title) provider.isIndexing.value = false;
        };

        final cancelled = await _ReindexProbeRepository(provider).runIndexing(
          library,
          books: [fresh],
          changedBooks: [changed],
          onProgress: (_, _) {},
        );
        expect(cancelled.completed, isFalse);
        // הישן נמחק עם ה-commit של מה שנכתב לפניו, והחדש לא נכתב.
        expect(engine.committedCounts, {'id:7': 1});
        expect(await storedPending(), {'id:5'});
        final repository = _ReindexProbeRepository(provider);
        expect(await repository.hasUnindexedBooks(library), isTrue);

        engine.onTextAdded = null;
        final resumed = await repository.runIndexing(
          library,
          books: [later],
          onProgress: (_, _) {},
        );
        expect(resumed.completed, isTrue);
        expect(engine.committedCounts, {'id:5': 1, 'id:7': 1, 'id:8': 1});
        expect(pendingFile().existsSync(), isFalse);
      },
    );

    test('כשל חולף אחרי מחיקת הגרסה הישנה — הספר נשאר בסימון', () async {
      final engine = _CancellationRecordingEngine();
      final changed = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.add(changed);
      final provider = providerWith(engine, [changed]);
      final repository = _ReindexProbeRepository(provider)
        ..textFailureByTitle['שבת'] = StateError('קריאה נכשלה');

      final result = await repository.runIndexing(
        library,
        changedBooks: [changed],
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(result.failures.single.isRetryable, isTrue);
      expect(engine.committedCounts, isEmpty);
      expect(await storedPending(), {'id:5'});
      expect(await repository.hasUnindexedBooks(library), isTrue);
    });

    test('בדיקת ספרים מסוימים שבוטלה באמצע נשמרת ונעשית בריצה הבאה', () async {
      final engine = _CancellationRecordingEngine()
        ..fingerprints = {'db:lib:5': BigInt.one};
      final attached = TextBook(
        id: 5,
        title: 'מצורף',
        source: BookSource.attached('lib'),
      );
      final fresh = TextBook(id: 7, title: 'פסחים');
      final library = Library(categories: [])..books.addAll([attached, fresh]);
      final provider = providerWith(engine, [attached]);
      final repository = _ReindexProbeRepository(provider);
      var checked = 0;
      repository.changeDetector = _textDetector(
        repository,
        loadText: (_) async {
          checked++;
          if (checked == 1) provider.isIndexing.value = false;
          return 'טקסט';
        },
        fingerprintOf: (_, _) async => BigInt.from(2),
      );

      final cancelled = await repository.runIndexing(
        library,
        books: const [],
        check: IndexCheckScope.books([attached]),
        onProgress: (_, _) {},
      );
      expect(cancelled.completed, isFalse);
      expect(
        (await PendingReindexStore.forIndex(indexDir.path)!.read()).checkKeys,
        {'db:lib:5'},
      );
      expect(await repository.hasUnindexedBooks(library), isTrue);

      // ריצת רענון רגילה, בלי בדיקה — הבדיקה שנדחתה רצה בה.
      final resumed = await repository.runIndexing(
        library,
        books: [fresh],
        onProgress: (_, _) {},
      );
      expect(resumed.completed, isTrue);
      expect(checked, 2);
      expect(engine.committedCounts.keys, containsAll(['db:lib:5', 'id:7']));
      expect(pendingFile().existsSync(), isFalse);
    });

    test('סימון של ספר שכבר אינו בספרייה נזרק', () async {
      final engine = _CancellationRecordingEngine();
      final book = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.add(book);
      final provider = providerWith(engine, [book]);
      await PendingReindexStore.forIndex(indexDir.path)!.save({'id:99'});

      final result = await _ReindexProbeRepository(provider).runIndexing(
        library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(engine.commitCount, 0);
      expect(pendingFile().existsSync(), isFalse);
    });

    test('השהיה נכבדת גם בשלב הבדיקה', () async {
      final engine = _CancellationRecordingEngine()
        ..fingerprints = {'id:5': BigInt.from(1)};
      final book = TextBook(id: 5, title: 'שבת');
      final library = Library(categories: [])..books.add(book);
      final provider = providerWith(engine, [book]);
      final repository = _ReindexProbeRepository(provider);
      var loads = 0;
      repository.changeDetector = _textDetector(
        repository,
        loadText: (_) async {
          loads++;
          return 'טקסט';
        },
        fingerprintOf: (_, _) async => BigInt.from(1),
      );
      repository.pauseIndexing();

      final run = repository.runIndexing(
        library,
        books: const [],
        check: IndexCheckScope.library,
        onProgress: (_, _) {},
      );
      while (!provider.isIndexing.value) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await pumpEventQueue();
      expect(loads, 0);

      repository.resumeIndexing();
      expect((await run).completed, isTrue);
      expect(loads, 1);
    });

    test('רשימה ריקה — לא נוגע במנוע ולא מאנדקס', () async {
      final engine = _RecordingSearchEngine();
      final repository = _ReindexProbeRepository(
        _RecordingTantivyDataProvider(engine),
      );

      final result = await _reindex(
        repository,
        const [],
        _buildLibrary(bavliBooks: const [('שבת', 1)]),
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(engine.removedFilePaths, isEmpty);
      expect(repository.indexedBooks, isNull);
    });
  });

  group('StampChangeDetector — בדיקה לפי חותמות', () {
    Future<String?> noTextRead(TextBook book) =>
        fail('לא אמורה להיקרא טביעת טקסט: ${book.title}');

    Future<List<String>> detect(
      _RecordingSearchEngine engine,
      List<Book> books, {
      Future<String?> Function(TextBook book)? loadText,
      BookSourceHashes? sourceHashes,
      BigInt Function(String title)? metadataOf,
    }) async {
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = IndexingRepository(provider);
      final detector = _textDetector(
        repository,
        loadText: loadText ?? noTextRead,
        fingerprintOf: (_, _) async => BigInt.from(2),
        sourceHashes: sourceHashes,
        metadataOf: metadataOf,
      );
      final changed = await detector.detectChanged(
        books,
        library: Library(categories: [])..books.addAll(books),
        isCancelled: () => false,
        waitWhilePaused: () async {},
      );
      return [for (final book in changed!) book.title];
    }

    test('שינוי metadata מזוהה בלי לקרוא טקסט', () async {
      final engine = _RecordingSearchEngine()
        ..fingerprints = {'id:5': BigInt.one, 'id:6': BigInt.one}
        ..sourceHashes.addAll({'id:5': BigInt.one, 'id:6': BigInt.one});
      final books = [
        TextBook(id: 5, title: 'שבת'),
        TextBook(id: 6, title: 'יומא'),
      ];

      final changed = await detect(
        engine,
        books,
        sourceHashes: BookSourceHashes({5: BigInt.one, 6: BigInt.one}, {}),
        metadataOf: (title) => title == 'שבת' ? BigInt.from(88) : _metadata,
      );

      expect(changed, ['שבת']);
    });

    test('חותם המסד מכריע בלי טביעת טקסט', () async {
      final engine = _RecordingSearchEngine()
        ..fingerprints = {'id:5': BigInt.one, 'id:6': BigInt.one}
        ..sourceHashes.addAll({
          'id:5': BigInt.from(11),
          'id:6': BigInt.from(20),
        });
      final books = [
        TextBook(id: 5, title: 'שבת'),
        TextBook(id: 6, title: 'יומא'),
      ];

      final changed = await detect(
        engine,
        books,
        sourceHashes: BookSourceHashes({
          5: BigInt.from(10),
          6: BigInt.from(20),
        }, {}),
      );

      expect(changed, ['שבת']);
    });

    test('חותם חסר במסד או באינדקס — נופל לטביעת הטקסט', () async {
      final engine = _RecordingSearchEngine()
        ..fingerprints = {'id:5': BigInt.one, 'id:6': BigInt.from(2)}
        ..sourceHashes.addAll({'id:6': BigInt.from(20)});
      final books = [
        TextBook(id: 5, title: 'שבת'),
        TextBook(id: 6, title: 'יומא'),
      ];
      final read = <String>[];

      final changed = await detect(
        engine,
        books,
        // לשבת אין חותם באינדקס; ליומא אין חותם במסד.
        sourceHashes: BookSourceHashes({5: BigInt.from(10)}, {}),
        loadText: (book) async {
          read.add(book.title);
          return 'טקסט';
        },
      );

      expect(read, ['שבת', 'יומא']);
      // טביעת הטקסט החדשה (2) שונה מ-1 של שבת ושווה לזו של יומא.
      expect(changed, ['שבת']);
    });

    test('ספר מסד מצורף נבדק לפי חותם המסד שלו', () async {
      final engine = _RecordingSearchEngine()
        ..fingerprints = {'db:lib:5': BigInt.one}
        ..sourceHashes.addAll({'db:lib:5': BigInt.from(3)});
      final book = TextBook(
        id: 5,
        title: 'מצורף',
        source: BookSource.attached('lib'),
      );

      final changed = await detect(
        engine,
        [book],
        sourceHashes: BookSourceHashes({}, {
          'lib': {5: BigInt.from(4)},
        }),
      );

      expect(changed, ['מצורף']);
    });

    test('ספר אישי ו-PDF — רק metadata, בלי קריאת טקסט', () async {
      final personal = TextBook(id: 9, title: 'אישי', source: BookSource.user);
      final pdf = PdfBook(title: 'סרוק', path: r'C:\pdfs\a.pdf');
      final engine = _RecordingSearchEngine()
        ..fingerprints = {
          BookIdentity.indexedFilePath(personal): BigInt.one,
          BookIdentity.indexedFilePath(pdf): BigInt.zero,
        };

      expect(await detect(engine, [personal, pdf]), isEmpty);
    });

    test('ספר שאינו באינדקס אינו נבדק', () async {
      final engine = _RecordingSearchEngine();

      expect(await detect(engine, [TextBook(id: 5, title: 'שבת')]), isEmpty);
    });
  });

  group('כתיבה עם חותם המסד', () {
    tearDown(
      () => IndexingRepository.loadSourceHashes = BookSourceHashes.load,
    );

    test('ספר רשמי וסמן ריק נכתבים עם book.contentHash של המסד', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final withText = TextBook(id: 5, title: 'שבת');
      final empty = TextBook(id: 6, title: 'ריק');
      final personal = TextBook(id: 7, title: 'אישי', source: BookSource.user);
      IndexingRepository.loadSourceHashes =
          ({attachedSlugs = const []}) async =>
              BookSourceHashes({5: BigInt.from(50), 6: BigInt.from(60)}, {});
      final repository = _FakeExtractionRepository(provider)
        ..textFailureByTitle.clear();
      final library = Library(categories: [])
        ..books.addAll([withText, empty, personal]);
      engine.onTextAdded = null;
      repository.emptyTextTitles.add('ריק');

      await repository.indexAllBooks(library, onProgress: (_, _) {});

      expect(engine.sourceHashByFilePath['id:5'], BigInt.from(50));
      expect(engine.sourceHashByFilePath['uid:7'], isNull);
      final marker = engine.addedDocuments.singleWhere(
        (doc) => doc.filePath == 'id:6',
      );
      expect(marker.sourceHash, BigInt.from(60));
    });
  });

  group('מיפוי הסדר', () {
    test('נדחף לפני האינדוקס, מהעץ המלא כולל ספר מוסתר', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final visible = TextBook(id: 5, title: 'גלוי');
      final hidden = TextBook(id: 6, title: 'מוסתר');
      final library = Library(categories: [])..books.addAll([visible, hidden]);
      final repository = _FakeExtractionRepository(
        provider,
        hiddenStore: _FixedHiddenStore(
          HiddenLibrarySelection(bookKeys: {PerBookSettings.bookKey(hidden)}),
        ),
      );
      engine.onTextAdded = (_) =>
          expect(engine.pushedOrders, hasLength(1), reason: 'לפני הכתיבה');

      await repository.indexAllBooks(library, onProgress: (_, _) {});

      expect(engine.pushedOrders.single.map((entry) => entry.filePath), [
        'id:5',
        'id:6',
      ]);
      expect(engine.bytesByFilePath.keys, ['id:5']);
    });
  });

  group('IndexingRepository.runIndexing — שלב הבדיקה', () {
    TextBook book(int id, String title) => TextBook(id: id, title: title);

    group('מסד שהתרוקן', () {
      late io.Directory tempDir;
      late AttachedLibraryRegistry previousRegistry;

      setUp(() async {
        tempDir = await io.Directory.systemTemp.createTemp(
          'otzaria_reconcile_empty',
        );
        await Settings.init(cacheProvider: MemoryCacheProvider());
        AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data'));
        final dbPath = p.join(tempDir.path, 'seforim.db');
        final database = MyDatabase.withPath(dbPath);
        final dbRepository = SeforimRepository(database);
        await dbRepository.ensureInitialized();
        final db = await database.database;
        db.execute(
          "INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)",
        );
        db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
        db.execute(
          "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines) VALUES (7, 7, 1, 'ספר שהתרוקן', 7, 0)",
        );
        db.execute(
          "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines) VALUES (8, 7, 1, 'שורה שהתרוקנה', 8, 1)",
        );
        db.execute(
          "INSERT INTO line (bookId, lineIndex, content) VALUES (8, 0, '')",
        );
        database.close();
        await UserBooksDatabaseHolder.instance.close();
        await Settings.setValue<String>(
          SettingsRepository.keyDbEffectivePath,
          dbPath,
        );
        await SqliteDataProvider.instance.dispose();
        await SqliteDataProvider.instance.initialize();
        previousRegistry = AttachedLibraryRegistry.instance;
        AttachedLibraryRegistry.instance =
            AttachedLibraryRegistry(idleTimeout: null)..update([
              AttachedLibrary(
                slug: 'empty-db',
                displayName: 'מסד ריק',
                path: dbPath,
                addedAt: DateTime(2026),
              ),
            ]);
      });

      tearDown(() async {
        await AttachedLibraryRegistry.instance.closeAll();
        AttachedLibraryRegistry.instance = previousRegistry;
        await SqliteDataProvider.instance.dispose();
        await UserBooksDatabaseHolder.instance.close();
        DbReadWorker.disposeForTesting();
        AppPaths.debugOverrideDataRootPath(null);
        await tempDir.delete(recursive: true);
      });

      for (final source in [
        BookSource.attached('empty-db'),
        BookSource.official,
      ]) {
        for (final (id, title) in [(7, 'ספר שהתרוקן'), (8, 'שורה שהתרוקנה')]) {
          test('$title מסיר תוכן ישן וכותב סמן ריק ($source)', () async {
            final engine = _RecordingSearchEngine();
            final provider = _RecordingTantivyDataProvider(engine);
            final emptied = TextBook(
              id: id,
              title: title,
              categoryId: 7,
              source: source,
            );
            final key = BookIdentity.indexedFilePath(emptied);
            final library = Library(categories: [])..books.add(emptied);
            engine.fingerprints = {key: BigInt.from(42)};
            provider.indexedFilePaths.add(key);
            final repository = IndexingRepository(provider);

            final result = await _reconcile(
              repository,
              library,
              onlyBooks: [emptied],
              onProgress: (_, _) {},
            );

            expect(result.completed, isTrue);
            expect(result.indexedBooks, 1);
            expect(engine.removedFilePaths, [key]);
            expect(engine.addedDocuments, hasLength(1));
            expect(engine.addedDocuments.single.filePath, key);
            expect(engine.addedDocuments.single.text, isEmpty);
            expect(engine.addedDocuments.single.segment, BigInt.zero);
            // הסמן נושא את טביעת הטקסט הריק, ולכן ספר שנשאר ריק לא יוחלף שוב.
            expect(
              engine.addedDocuments.single.textHash,
              await _fakeContentFingerprint(text: const []),
            );
            expect(provider.indexedFilePaths, {key});
          });
        }
      }

      test('ספר שנשאר ריק אינו מוחלף שוב בבדיקה הבאה', () async {
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final emptied = TextBook(id: 7, title: 'ספר שהתרוקן', categoryId: 7);
        final key = BookIdentity.indexedFilePath(emptied);
        // הסמן שנכתב בהחלפה הקודמת: טביעת הטקסט הריק.
        engine.fingerprints = {
          key: await _fakeContentFingerprint(text: const []),
        };
        provider.indexedFilePaths.add(key);

        final result = await _reconcile(
          IndexingRepository(provider),
          Library(categories: [])..books.add(emptied),
          onlyBooks: [emptied],
          onProgress: (_, _) {},
        );

        expect(result.completed, isTrue);
        expect(engine.removedFilePaths, isEmpty);
        expect(engine.addedDocuments, isEmpty);
      });

      for (final (id, title) in [(7, 'ספר שהתרוקן'), (8, 'שורה שהתרוקנה')]) {
        test('ספר ריק ממקור אחר אינו מוחק תוכן אישי: $title', () async {
          final engine = _RecordingSearchEngine();
          final provider = _RecordingTantivyDataProvider(engine);
          final missing = TextBook(
            id: id,
            title: title,
            categoryId: 7,
            source: BookSource.user,
          );
          final key = BookIdentity.indexedFilePath(missing);
          final library = Library(categories: [])..books.add(missing);
          engine.fingerprints = {key: BigInt.from(42)};
          provider.indexedFilePaths.add(key);
          final result = await _reconcile(
            IndexingRepository(provider),
            library,
            onlyBooks: [missing],
            onProgress: (_, _) {},
            fingerprintOf: (_, _) async =>
                throw StateError('הספר במקור המבוקש חסר'),
          );
          expect(result.completed, isTrue);
          expect(engine.removedFilePaths, isEmpty);
          expect(engine.addedDocuments, isEmpty);
          expect(provider.indexedFilePaths, {key});
        });
      }

      test('ספר שלא נמצא במסד אינו מוחלף בסמן ריק', () async {
        final engine = _CancellationRecordingEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final missing = _ReconcileTextBook(
          source: BookSource.attached('missing-db'),
        );
        final key = BookIdentity.indexedFilePath(missing);
        final library = Library(categories: [])..books.add(missing);
        engine.fingerprints = {key: BigInt.from(42)};
        provider.indexedFilePaths.add(key);
        final repository = IndexingRepository(provider);
        final result = await _reconcile(
          repository,
          library,
          onlyBooks: [missing],
          onProgress: (_, _) {},
        );
        expect(result.completed, isTrue);
        expect(engine.removedFilePaths, isEmpty);
        expect(engine.addedDocuments, isEmpty);
        expect(provider.indexedFilePaths, {key});
      });
    });

    test('כשל קריאת ספר שומר את התוכן המאונדקס הקיים', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final unreadable = _ReconcileTextBook(
        source: BookSource.attached('unreadable-db'),
        failure: const CorruptedDocumentException(),
      );
      final key = BookIdentity.indexedFilePath(unreadable);
      final library = Library(categories: [])..books.add(unreadable);
      engine.fingerprints = {key: BigInt.from(42)};
      provider.indexedFilePaths.add(key);
      final repository = IndexingRepository(provider);

      final result = await _reconcile(
        repository,
        library,
        onlyBooks: [unreadable],
        onProgress: (_, _) {},
        fingerprintOf: (_, _) async => throw StateError('אין תוכן לאימות'),
      );

      expect(result.completed, isTrue);
      expect(engine.removedFilePaths, isEmpty);
      expect(engine.addedDocuments, isEmpty);
      expect(provider.indexedFilePaths, {key});
    });

    test(
      'מזהה ספרים ששונו או בלתי-ניתנים-לאימות ומאנדקס רק אותם מחדש',
      () async {
        final engine = _CancellationRecordingEngine();
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
          BookIdentity.indexedFilePath(unchanged): BigInt.from(
            11,
          ),
          BookIdentity.indexedFilePath(changed): BigInt.from(21),
          BookIdentity.indexedFilePath(unverifiable): BigInt.zero,
          BookIdentity.indexedFilePath(unloadable): BigInt.from(
            55,
          ),
          // notIndexed בכוונה חסר — ספר חדש שמטופל במסלול הרגיל.
        };
        for (final b in [unchanged, changed, unverifiable, unloadable]) {
          provider.indexedFilePaths.add(
            BookIdentity.indexedFilePath(b),
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

        final result = await _reconcile(
          repository,
          library,
          onScanProgress: (p, t) => scanCalls.add((p, t)),
          onProgress: (_, _) {},
          loadText: (b) async => texts[b.title],
          fingerprintOf: (_, text) async => hashes[text]!,
        );

        expect(result.completed, isTrue);
        expect(
          repository.indexedBooks!.map((b) => b.title).toSet(),
          {'עירובין', 'יומא'},
        );
        expect(engine.removedFilePaths.toSet(), {'id:2', 'id:4'});
        // הבדיקה עוברת רק על ספרים שיש להם חותמות באינדקס.
        expect(scanCalls.first, (0, 4));
        expect(scanCalls.last, (4, 4));
        expect(provider.isIndexing.value, isFalse);
      },
    );

    test('onlyBooks מגביל את הסריקה ואינו נוגע בספרים אחרים ששונו', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final scanned = book(1, 'שבת');
      final skipped = book(2, 'עירובין');
      final library = _buildLibrary(bavliBooks: const []);
      library.books.addAll([scanned, skipped]);
      engine.fingerprints = {
        BookIdentity.indexedFilePath(scanned): BigInt.from(1),
        BookIdentity.indexedFilePath(skipped): BigInt.from(2),
      };

      final repository = _ReindexProbeRepository(provider);
      final loaded = <String>[];
      final result = await _reconcile(
        repository,
        library,
        onlyBooks: [scanned],
        onProgress: (_, _) {},
        loadText: (b) async {
          loaded.add(b.title);
          return 'טקסט';
        },
        fingerprintOf: (_, _) async => BigInt.from(99),
      );

      expect(result.completed, isTrue);
      expect(loaded, ['שבת']);
      expect(repository.indexedBooks!.map((b) => b.title), ['שבת']);
      expect(engine.removedFilePaths.toSet(), {'id:1'});
    });

    test('כשהכל תואם — מסתיים בהצלחה בלי לגעת באינדקס', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final b = book(1, 'שבת');
      final library = _buildLibrary(bavliBooks: const []);
      library.books.add(b);
      engine.fingerprints = {
        BookIdentity.indexedFilePath(b): BigInt.from(7),
      };

      final repository = _ReindexProbeRepository(provider);
      final result = await _reconcile(
        repository,
        library,
        onProgress: (_, _) {},
        loadText: (_) async => 'טקסט',
        fingerprintOf: (_, _) async => BigInt.from(7),
      );

      expect(result.completed, isTrue);
      expect(repository.indexedBooks, isNull);
      expect(engine.removedFilePaths, isEmpty);
    });

    for (final cancelInProgressCallback in [false, true]) {
      test(
        'ביטול בספר האחרון לפני האינדוקס ($cancelInProgressCallback)',
        () async {
          final engine = _CancellationRecordingEngine();
          final provider = _RecordingTantivyDataProvider(engine);
          final b = book(1, 'שבת');
          final library = _buildLibrary(bavliBooks: const []);
          library.books.add(b);
          engine.fingerprints = {'id:1': BigInt.from(9)};
          final repository = _ReindexProbeRepository(provider);
          final hashing = Completer<void>();
          final release = Completer<BigInt>();
          final run = _reconcile(
            repository,
            library,
            onlyBooks: [b],
            onProgress: (_, _) {},
            onScanProgress: (processed, _) {
              if (cancelInProgressCallback && processed > 0) {
                provider.isIndexing.value = false;
              }
            },
            loadText: (_) async => 'טקסט',
            fingerprintOf: (_, _) {
              hashing.complete();
              return release.future;
            },
          );
          await hashing.future;
          if (!cancelInProgressCallback) provider.isIndexing.value = false;
          release.complete(BigInt.one);
          final result = await run;
          expect(result.completed, isFalse);
          expect(repository.indexedBooks, isNull);
          expect(engine.removedFilePaths, isEmpty);
          expect(provider.isIndexing.value, isFalse);
        },
      );
    }

    test('כשל בחישוב חתימה מאפס מצב עבודה ומשמר את האינדקס', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final b = book(1, 'שבת');
      final library = _buildLibrary(bavliBooks: const []);
      library.books.add(b);
      engine.fingerprints = {'id:1': BigInt.from(9)};
      final repository = _ReindexProbeRepository(provider);
      await expectLater(
        _reconcile(
          repository,
          library,
          onlyBooks: [b],
          onProgress: (_, _) {},
          loadText: (_) async => 'טקסט',
          fingerprintOf: (_, _) async => throw StateError('worker failed'),
        ),
        throwsStateError,
      );
      expect(provider.isIndexing.value, isFalse);
      expect(repository.indexedBooks, isNull);
      expect(engine.removedFilePaths, isEmpty);
    });

    test('ביטול באמצע הסריקה מחזיר false בלי לאנדקס', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const []);
      library.books.addAll([book(1, 'שבת'), book(2, 'עירובין')]);
      engine.fingerprints = {
        for (final b in library.books)
          BookIdentity.indexedFilePath(b): BigInt.from(9),
      };

      final repository = _ReindexProbeRepository(provider);
      final result = await _reconcile(
        repository,
        library,
        onProgress: (_, _) {},
        loadText: (b) async {
          // מדמה לחיצת ביטול של המשתמש בזמן הסריקה.
          provider.isIndexing.value = false;
          return 'טקסט';
        },
        fingerprintOf: (_, _) async => BigInt.one,
      );

      expect(result.completed, isFalse);
      expect(repository.indexedBooks, isNull);
    });
  });

  group('IndexingRepository.stripDataUrisForIndex', () {
    test('מסלק תמונות base64 ומשמר את מבנה השורות', () {
      final img = 'data:image/png;base64,${'A' * 500}';
      final text = 'שורה ראשונה\n<img src="$img" style="x"/>\nשורה שלישית';

      final stripped = IndexingRepository.stripDataUrisForIndex(text);

      expect(stripped.split('\n'), hasLength(3));
      expect(stripped, isNot(contains('base64')));
      expect(stripped, contains('שורה ראשונה'));
      expect(stripped, contains('שורה שלישית'));
    });

    test('טקסט ללא data URI חוזר כמו שהוא (אותו מופע)', () {
      const text = 'טקסט רגיל בלי תמונות';
      expect(
        identical(IndexingRepository.stripDataUrisForIndex(text), text),
        isTrue,
      );
    });

    test('data URI ענק (מיליוני תווים) מסולק בלי Stack Overflow', () {
      final img = 'data:image/jpeg;base64,${'B' * 5000000}';
      final text = 'לפני\n$img\nאחרי';

      final stripped = IndexingRepository.stripDataUrisForIndex(text);

      expect(stripped, 'לפני\n\nאחרי');
    });

    test('רצף data: קצר מ-64 תווים נשמר (אותו מופע)', () {
      final text = 'ראו data:text/plain,${'A' * 20} בהמשך';
      expect(
        identical(IndexingRepository.stripDataUrisForIndex(text), text),
        isTrue,
      );
    });
  });

  group('IndexingRepository.bytesContainDataUriScheme', () {
    // מכריעה אם מסלול ה-bytes המהיר של האינדוקס חייב לרדת לפענוח וניקוי.
    // בלי הניקוי, טביעת האצבע באינדקס לעולם לא תואמת את האימות (issue #828).
    test('מזהה data: בתוך טקסט UTF-8 עברי', () {
      final bytes = Uint8List.fromList(
        utf8.encode('שורה\n<img src="data:image/png;base64,AAAA"/>'),
      );
      expect(IndexingRepository.bytesContainDataUriScheme(bytes), isTrue);
    });

    test('טקסט בלי data: מחזיר false', () {
      final bytes = Uint8List.fromList(utf8.encode('טקסט רגיל עם date: בלבד'));
      expect(IndexingRepository.bytesContainDataUriScheme(bytes), isFalse);
    });

    test('bytes קצרים מהתבנית מחזירים false', () {
      final bytes = Uint8List.fromList(utf8.encode('dat'));
      expect(IndexingRepository.bytesContainDataUriScheme(bytes), isFalse);
    });
  });

  group('IndexingRepository.dataUriLineOrdinals', () {
    const bom = '\uFEFF';
    final image = 'data:image/png;base64,${'A' * 80}';
    List<int> ordinals(List<String> rows) =>
        IndexingRepository.dataUriLineOrdinals(
          Uint8List.fromList(utf8.encode(rows.join('\n'))),
        );

    /// השורות שהניקוי משנה בפועל — ההגדרה ש-[dataUriLineOrdinals] מקיים.
    List<int> changedRows(List<String> rows) => [
      for (final (i, row) in rows.indexed)
        if (IndexingRepository.stripDataUrisForIndex(row) != row) i,
    ];

    test('data: בשורה הראשונה, ושורות עם BOM', () {
      final rows = [
        '$bom<img src="$image">',
        '$bomשורה נקייה',
        'שורה עם $image באמצע',
        '$bom$image',
      ];
      expect(ordinals(rows), [0, 2, 3]);
      expect(ordinals(rows), changedRows(rows));
    });

    test('כמה תמונות בשורה אחת נספרות פעם אחת', () {
      final rows = ['א', '<img src="$image"> ו-<img src="$image">', 'ב'];
      expect(ordinals(rows), [1]);
    });

    test('data: קצר אינו מנוקה ולכן אינו נספר', () {
      final rows = ['קצר data:abc נשאר', 'metadata: x', '$image data:ab'];
      expect(ordinals(rows), [2]);
      expect(ordinals(rows), changedRows(rows));
    });

    test('ספר בלי data: — רשימה ריקה; שורות ריקות נספרות במיקום', () {
      expect(ordinals(['א', '', 'ב']), isEmpty);
      expect(ordinals(['', '', image, '']), [2]);
      expect(ordinals([image]), [0]);
    });

    test('UTF-8 פגום אינו מזיז את מספרי השורות', () {
      final bytes = BytesBuilder()
        ..add([0xE0, 0x0A, 0xFF]) // רצף פגום, ואחריו \n אמיתי
        ..add(utf8.encode(image))
        ..addByte(0x0A)
        ..add(utf8.encode('ג'));
      final raw = bytes.takeBytes();
      expect(IndexingRepository.dataUriLineOrdinals(raw), [1]);
      final text = utf8.decode(raw, allowMalformed: true);
      expect(changedRows(text.split('\n')), [1]);
    });
  });

  group('IndexingRepository — עבודת data URI מחוץ לפריים', () {
    // מעל 1MB הסריקה נפרסת למנות על ה-thread הקורא והניקוי עובר ל-isolate;
    // הבדיקות מקבעות שהתוצאה זהה בשני צדי הסף — טביעת האצבע נגזרת ממנה.
    String bigTextWithImage() =>
        'לפני\n${'מילה ' * 300000}\ndata:image/png;base64,${'A' * 200000}\nאחרי';

    /// bytes שבהם ה-`data:` מתחיל בדיוק ב-[offset] (ASCII, ולכן היסט
    /// הבייטים הוא גם היסט התווים).
    Uint8List bytesWithUriAt(int offset) {
      final uri = utf8.encode('data:image/png;base64,${'A' * 200}');
      return Uint8List(offset + uri.length + 16)
        ..fillRange(0, offset, 0x78) // 'x'
        ..setRange(offset, offset + uri.length, uri)
        ..fillRange(offset + uri.length, offset + uri.length + 16, 0x79); // 'y'
    }

    test('bytes קטנים: אותה תוצאה כמו המסלול הסינכרוני', () async {
      final clean = Uint8List.fromList(utf8.encode('טקסט נקי בלי תמונות'));
      final cleanSource = await IndexingRepository.cleanDataUrisOffFrame(
        clean,
      );
      expect(cleanSource.bytes, same(clean));
      expect(cleanSource.text, isNull);

      final withImage = Uint8List.fromList(
        utf8.encode('שורה\n<img src="data:image/png;base64,${'A' * 100}"/>'),
      );
      final imageSource = await IndexingRepository.cleanDataUrisOffFrame(
        withImage,
      );
      expect(
        imageSource.text,
        IndexingRepository.stripDataUrisForIndex(
          utf8.decode(withImage, allowMalformed: true),
        ),
      );
      expect(imageSource.bytes, isNull);
      expect(imageSource.dataUriLines, [1]);
      expect(cleanSource.dataUriLines, isNull);

      // data: קצר בלבד: עובר לטקסט, אבל אין שורה שהשתנתה.
      final shortOnly = await IndexingRepository.cleanDataUrisOffFrame(
        Uint8List.fromList(utf8.encode('א\nקצר data:abc')),
      );
      expect(shortOnly.text, 'א\nקצר data:abc');
      expect(shortOnly.dataUriLines, isNull);
    });

    test('bytes גדולים (מסלול ה-isolate): אותה תוצאה בדיוק', () async {
      final text = bigTextWithImage();
      final bytes = Uint8List.fromList(utf8.encode(text));
      expect(bytes.length, greaterThan(1 << 20));

      final source = await IndexingRepository.cleanDataUrisOffFrame(bytes);
      expect(
        source.text,
        IndexingRepository.stripDataUrisForIndex(
          utf8.decode(bytes, allowMalformed: true),
        ),
      );
      expect(source.bytes, isNull);
      expect(source.dataUriLines, [2]);
    });

    test('bytes גדולים בלי data URI נשארים במסלול ה-bytes', () async {
      // שלוש מנות סריקה ומעלה, כדי לכסות גם את המנה האחרונה החלקית.
      final bytes = Uint8List((3 << 20) * 4 + 777)
        ..fillRange(0, (3 << 20) * 4 + 777, 0x78);
      final source = await IndexingRepository.cleanDataUrisOffFrame(bytes);
      expect(source.bytes, same(bytes));
      expect(source.text, isNull);
    });

    test('data: היושב על תפר בין מנות הסריקה אינו מפוספס', () async {
      const chunk = 4 << 20;
      // התאמה שמתחילה בארבעת הבייטים שלפני התפר נחתכת בין מנה למנה; סריקה
      // בלי חפיפה מחזירה כאן null, כלומר מסמנת ספר מצויר כנקי.
      for (final offset in [chunk - 4, chunk - 3, chunk - 2, chunk - 1]) {
        final bytes = bytesWithUriAt(offset);
        final raw = utf8.decode(bytes, allowMalformed: true);
        final expected = IndexingRepository.stripDataUrisForIndex(raw);
        expect(expected, isNot(raw), reason: 'התפר בהיסט $offset לא נוקה');
        final source = await IndexingRepository.cleanDataUrisOffFrame(bytes);
        expect(
          source.text,
          expected,
          reason: 'data: על התפר בהיסט $offset',
        );
        expect(source.bytes, isNull);
      }
    });

    test(
      'טקסט גדול (מסלול ה-isolate): אותה תוצאה כמו הניקוי הסינכרוני',
      () async {
        final text = bigTextWithImage();
        expect(text.length, greaterThan(1 << 20));

        expect(
          await IndexingRepository.stripDataUrisOffFrame(text),
          IndexingRepository.stripDataUrisForIndex(text),
        );
      },
    );

    test('טקסט נקי גדול: אותה תוצאה, בלי סריקה כפולה על החוט הקורא', () async {
      final text = 'מילה ' * 300000;
      expect(text.length, greaterThan(1 << 20));

      // גם הסריקה עצמה עוברת ל-isolate; בדיקה מקדימה כאן הייתה סורקת את
      // הטקסט פעמיים על החוט שמצייר פריימים (המחרוזת נשלחת בלי העתקה).
      expect(await IndexingRepository.stripDataUrisOffFrame(text), text);
    });

    test('טקסט קטן חוזר דרך המסלול הסינכרוני (אותו מופע)', () async {
      const text = 'טקסט רגיל בלי תמונות';
      expect(
        identical(await IndexingRepository.stripDataUrisOffFrame(text), text),
        isTrue,
      );
    });
  });

  group('IndexingRepository.indexAllBooks', () {
    test('includePdfBooks=false אינו כותב PDF לאינדקס ההפצה', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      library.books.add(
        PdfBook(title: 'שבת', path: r'C:\release-staging\שבת.pdf', id: 7),
      );
      final repository = IndexingRepository(provider);

      final result = await repository.indexAllBooks(
        library,
        includePdfBooks: false,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(engine.addedDocuments, isEmpty);
      expect(provider.indexedFilePaths, isEmpty);
    });

    test('מסכת PDF מצורפת אינה נכנסת למסלול האינדוקס המלא', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      final bundledPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\library\תלמוד בבלי\ברכות.pdf',
        externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
          'ברכות',
        ),
      );
      library.books.add(bundledPdf);
      final repository = _FakeExtractionRepository(provider);

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(result.totalBooks, 0);
      expect(repository.extractedTitles, isEmpty);
      expect(engine.addedPdfTitles, isEmpty);
      expect(provider.indexedFilePaths, isEmpty);
    });

    test('fast path מחזיר מוקדם בלי להפעיל isolate ובלי callbacks', () async {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      final indexedFilePaths = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(BookIdentity.indexedFilePath)
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

      expect(result.completed, isTrue);
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
      final specificRun = await repository.runIndexing(
        library,
        books: library.books.cast<Book>(),
        onProgress: (_, _) => progressCalls++,
      );
      final reconcileRun = await _reconcile(
        repository,
        library,
        onProgress: (_, _) => progressCalls++,
      );

      expect(fullRun.completed, isFalse);
      expect(specificRun.completed, isFalse);
      expect(reconcileRun.completed, isFalse);
      expect(progressCalls, 0);
      expect(engine.addedDocuments, isEmpty);
      expect(provider.isIndexing.value, isFalse);
    });

    testWidgets(
      'אינדקס שדורש בנייה מחדש אינו מדווח ככשל פתיחה (issue #2603)',
      (tester) async {
        // אינדקס מסכמה ישנה נפתח בכוונה על אינדקס זמני — אין כאן כשל פתיחה,
        // וההודעה "נסה להפעיל מחדש" שלחה את המשתמש לפתרון שאינו עוזר.
        await tester.pumpWidget(
          MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
        );
        final provider = FakeTantivyDataProvider(
          indexedFilePaths: {},
          requiresManualReindexValue: true,
        )..isTempFallback = true;
        final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
        final repository = IndexingRepository(provider);

        final runs = [
          await repository.indexAllBooks(library, onProgress: (_, _) {}),
          await repository.runIndexing(
            library,
            books: library.getAllBooks(),
            onProgress: (_, _) {},
          ),
          await _reconcile(
            repository,
            library,
            onProgress: (_, _) {},
          ),
        ];
        await tester.pump();

        expect(runs.map((run) => run.completed), everyElement(isFalse));
        expect(find.text(LibraryMessages.searchIndexOpenFailed), findsNothing);
      },
    );

    test('לא מדלג ב-fast path כשנדרש manual reindex', () async {
      final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
      final indexedFilePaths = library
          .getAllBooks()
          .where(IndexingRepository.isIndexableBook)
          .map(BookIdentity.indexedFilePath)
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

      expect(result.completed, isFalse);
      expect(actualIndexingStarted, isFalse);
      expect(progressCalls, 0);
    });

    test('מדווח את הספר הנוכחי בתחילת עיבודו, לפני הכתיבה למנוע', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      // PDF שקבציהם חסרים — עוברים במסלול סמן-ריק, בלי pdfrx ובלי DB.
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

      expect(result.completed, isTrue);
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

      expect(result.completed, isTrue);
      // הכתיבה החלקית אכן נרשמה במנוע לפני הכשל — ורק אז נמחקה.
      expect(engine.addedDocuments.map((d) => d.title), contains('ב'));
      // רק הספר שכשל נוקה; שכנו שהצליח לא נמחק.
      expect(engine.removedFilePaths, [r'C:\missing\ב.pdf']);
      expect(provider.indexedFilePaths, {r'C:\missing\א.pdf'});
    });

    for (final recoveringCommitted in [false, true]) {
      test(
        'חילוצי PDF מוקדמים ללא כפילות (${recoveringCommitted ? 'אחרי קריסה וסמן חתום' : 'ריצה בריאה'})',
        () async {
          // ברירת המחדל החד-סלוטית מונעת timeout של עבודה שממתינה בתור PDFium.
          final engine = _CancellationRecordingEngine();
          final provider = _RecordingTantivyDataProvider(engine);
          final library = Library(categories: []);
          final indexedText1 = TextBook(id: 1, title: 'ט1');
          final indexedText2 = TextBook(id: 2, title: 'ט2');
          final pdf1 = PdfBook(title: 'א', path: r'C:\pdfs\א.pdf');
          final pdf2 = PdfBook(title: 'ב', path: r'C:\pdfs\ב.pdf');
          library.books.addAll([indexedText1, indexedText2, pdf1, pdf2]);
          // אינדוקס ספרי הטקסט נותן ללולאה "זמן טקסטים" שבו חילוץ ה-prefetch
          // מסתיים ומנוקז.
          if (recoveringCommitted) {
            final temp = await io.Directory.systemTemp.createTemp(
              'canary_prefetch_',
            );
            addTearDown(() => temp.delete(recursive: true));
            provider.activeIndexPath = '${temp.path}/index';
            final key = BookIdentity.indexedFilePath(
              indexedText1,
            );
            engine.committedFilePaths = [key];
            io.File(
              '${provider.activeIndexPath}.in_flight.json',
            ).writeAsStringSync(jsonEncode({key: 2}));
          }
          final repository = _FakeExtractionRepository(provider);

          // יומן אירועים משולב — מוכיח את *סדר* הכתיבות ביחס להתקדמות הלולאה.
          final events = <String>[];
          engine.onPdfAdded = (title) => events.add('pdf:$title');

          final result = await repository.indexAllBooks(
            library,
            onProgress: (p, _) => events.add('progress:$p'),
          );

          expect(result.completed, isTrue);
          // הראשון נוקז מוקדם — נכתב לפני שהלולאה הגיעה למקומו (3). השני עשוי
          // להתנקז באותו סבב, ואז הלולאה מדלגת על דיווח 3.
          expect(
            events.indexOf('pdf:א'),
            lessThan(
              events.indexWhere(
                (e) =>
                    e.startsWith('progress:') &&
                    int.parse(e.substring('progress:'.length)) >= 3,
              ),
            ),
          );
          // כל PDF חולץ ואונדקס בדיוק פעם אחת — הניקוז המוקדם לא מכפיל.
          expect(repository.extractedTitles, ['א', 'ב']);
          expect(engine.addedPdfTitles, ['א', 'ב']);
          expect(
            provider.indexedFilePaths,
            containsAll([pdf1.path, pdf2.path]),
          );
        },
      );
    }

    test(
      'חילוצי PDF נשארים סדרתיים כי PDFium משתמש ב-worker יחיד',
      () async {
        // PDFium משתמש ב-worker יחיד, ולכן אין ערך בתור חילוצים מקבילי.
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final library = Library(categories: []);
        final texts = [
          for (var i = 0; i < 5; i++) TextBook(id: i + 1, title: 'ט$i'),
        ];
        final pdfs = [
          for (var i = 0; i < 40; i++)
            PdfBook(title: 'p$i', path: 'C:\\p$i.pdf'),
        ];
        library.books.addAll([...texts, ...pdfs]);
        // ספרי הטקסט מדולגים — נותנים ללולאה "זמן טקסטים" שבו החילוצים רצים.
        provider.indexedFilePaths.addAll(
          texts.map(BookIdentity.indexedFilePath),
        );
        final repository = _FakeExtractionRepository(provider);

        final result = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );

        expect(result.completed, isTrue);
        // המספר קשיח בכוונה: ציפייה שמתייחסת ל-defaultMaxInFlight עצמו הייתה
        // מעגלית ועוברת גם במימוש חד-סלוטי.
        expect(repository.peakConcurrentExtractions, 1);
        // התקרה היא הבלם על הזיכרון: מ-40 מועמדים לא נפתחו יותר ממנה.
        expect(
          repository.peakConcurrentExtractions,
          lessThanOrEqualTo(PdfExtractionPrefetcher.defaultMaxInFlight),
        );
        // כל 40 הספרים חולצו ואונדקסו בדיוק פעם אחת.
        expect(repository.extractedTitles.length, 40);
        expect(repository.extractedTitles.toSet().length, 40);
        expect(engine.addedPdfTitles.toSet().length, 40);
      },
    );

    test('חילוץ שנכשל אינו עוצר את שאר התור ואינו נספר כמאונדקס', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = Library(categories: []);
      final pdfs = [
        for (var i = 0; i < 4; i++) PdfBook(title: 'p$i', path: 'C:\\p$i.pdf'),
      ];
      library.books.addAll(pdfs);
      final repository = _FakeExtractionRepository(provider)
        ..failingTitles.add('p1');

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      // הכשל בחילוץ אינו כתיבה חלקית — אין מה לנקות, והשאר אונדקסו.
      expect(engine.addedPdfTitles, ['p0', 'p2', 'p3']);
      expect(provider.indexedFilePaths, isNot(contains(pdfs[1].path)));
      expect(
        provider.indexedFilePaths,
        containsAll([pdfs[0].path, pdfs[2].path, pdfs[3].path]),
      );
    });

    test('PDF מוגן בסיסמה מסומן כטופל ואינו יוצר לולאת אינדוקס', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'מוגן', path: r'C:\pdfs\protected.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..failureByTitle[pdf.title] = Exception(
          'PdfException: No password supplied by PasswordProvider.',
        );

      final firstRun = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );
      final extractionsAfterFirstRun = repository.extractedTitles.length;
      final secondRun = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(firstRun.completed, isTrue);
      expect(firstRun.isClean, isFalse);
      expect(
        firstRun.failures.single.kind,
        IndexingFailureKind.passwordProtected,
      );
      expect(provider.indexedFilePaths, contains(pdf.path));
      expect(
        engine.addedDocuments,
        contains(
          isA<DocumentInput>()
              .having((document) => document.filePath, 'filePath', pdf.path)
              .having((document) => document.text, 'text', isEmpty),
        ),
      );
      expect(secondRun.isClean, isTrue);
      expect(repository.extractedTitles.length, extractionsAfterFirstRun);
    });

    test(
      'docx מוצפן מסומן ככשל קבוע ואינו מפעיל אינדוקס מלא בכל עלייה',
      () async {
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final book = TextBook(
          id: 1009,
          title: 'הרב פינקוס',
          source: BookSource.user,
        );
        final library = Library(categories: [])..books.add(book);
        final repository = _FakeExtractionRepository(provider)
          ..textFailureByTitle[book.title] = const EncryptedDocumentException(
            format: DocumentFormat.docx,
            cause: 'החבילה מוצפנת (מכולת OLE במקום ZIP)',
          );

        final firstRun = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );
        final secondRun = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );

        expect(
          firstRun.failures.single.kind,
          IndexingFailureKind.passwordProtected,
        );
        expect(firstRun.retryableFailures, isEmpty);
        final filePath = BookIdentity.indexedFilePath(book);
        expect(provider.indexedFilePaths, contains(filePath));
        expect(
          engine.addedDocuments,
          contains(
            isA<DocumentInput>()
                .having((document) => document.filePath, 'filePath', filePath)
                .having((document) => document.text, 'text', isEmpty),
          ),
        );
        expect(secondRun.isClean, isTrue);
        expect(await repository.hasUnindexedBooks(library), isFalse);
      },
    );

    test(
      'ספר שהריצה מתה באמצעו פעמיים ברצף מדולג ככשל קבוע (issue #2038)',
      () async {
        final tempDir = await io.Directory.systemTemp.createTemp('canary_');
        addTearDown(() => tempDir.delete(recursive: true));
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine)
          ..activeIndexPath = p.join(tempDir.path, 'index');
        final crasher = TextBook(id: 1, title: 'קורס', source: BookSource.user);
        final crasherKey = BookIdentity.indexedFilePath(crasher);
        io.File(
          '${provider.activeIndexPath}.in_flight.json',
        ).writeAsStringSync(jsonEncode({crasherKey: 2}));
        final library = Library(categories: [])..books.add(crasher);

        final result = await _FakeExtractionRepository(
          provider,
        ).indexAllBooks(library, onProgress: (_, _) {});

        expect(result.failures.single.bookTitle, crasher.title);
        expect(result.failures.single.isRetryable, isFalse);
        expect(provider.indexedFilePaths, contains(crasherKey));
      },
    );

    for (final fullRun in [false, true]) {
      test(
        'חסימת ספר נשמרת כש-commit נכשל (${fullRun ? 'מלא' : 'נקודתי'})',
        () async {
          final temp = await io.Directory.systemTemp.createTemp(
            'canary_commit_',
          );
          addTearDown(() => temp.delete(recursive: true));
          final engine = _RecordingSearchEngine()..failCommit = true;
          final provider = _RecordingTantivyDataProvider(engine)
            ..activeIndexPath = '${temp.path}/index';
          final book = TextBook(id: 1, title: 'קורס', source: BookSource.user);
          final key = BookIdentity.indexedFilePath(book);
          final file = io.File('${provider.activeIndexPath}.in_flight.json');
          file.writeAsStringSync(jsonEncode({key: 2}));
          final library = Library(categories: [])..books.add(book);
          final repository = _FakeExtractionRepository(provider);
          await expectLater(
            fullRun
                ? repository.indexAllBooks(library, onProgress: (_, _) {})
                : repository.runIndexing(
                    library,
                    books: [book],
                    onProgress: (_, _) {},
                  ),
            throwsStateError,
          );
          expect(jsonDecode(file.readAsStringSync()), {key: 2});
        },
      );
    }

    test(
      'סריקה מלאה מנקה ספרים מוסתרים/מחוקים, נקודתית משמרת ספר שלא נבדק',
      () async {
        final temp = await io.Directory.systemTemp.createTemp('canary_stale_');
        addTearDown(() => temp.delete(recursive: true));
        final provider = _RecordingTantivyDataProvider(_RecordingSearchEngine())
          ..activeIndexPath = '${temp.path}/index';
        final visible = TextBook(id: 1, title: 'גלוי', source: BookSource.user);
        final hidden = TextBook(id: 2, title: 'מוסתר', source: BookSource.user);
        final hiddenKey = BookIdentity.indexedFilePath(hidden);
        final file = io.File('${provider.activeIndexPath}.in_flight.json');
        file.writeAsStringSync(jsonEncode({hiddenKey: 1, 'removed-book': 1}));
        final library = Library(categories: [])
          ..books.addAll([visible, hidden]);
        final repository = _FakeExtractionRepository(
          provider,
          hiddenStore: _FixedHiddenStore(
            HiddenLibrarySelection(
              bookKeys: {PerBookSettings.bookKey(hidden)},
            ),
          ),
        );
        await repository.runIndexing(
          library,
          books: [visible],
          onProgress: (_, _) {},
        );
        expect(jsonDecode(file.readAsStringSync()), {
          hiddenKey: 1,
          'removed-book': 1,
        });
        provider.indexedFilePaths.clear();
        await repository.indexAllBooks(library, onProgress: (_, _) {});
        expect(jsonDecode(file.readAsStringSync()), isEmpty);
      },
    );

    for (final fullRun in [false, true]) {
      test(
        'כשל כתיבת סמן שומר חסימה למרות commit מוצלח (${fullRun ? 'מלא' : 'נקודתי'})',
        () async {
          final temp = await io.Directory.systemTemp.createTemp(
            'canary_marker_',
          );
          addTearDown(() => temp.delete(recursive: true));
          final crasher = TextBook(
            id: 1,
            title: 'קורס',
            source: BookSource.user,
          );
          final healthy = TextBook(
            id: 2,
            title: 'תקין',
            source: BookSource.user,
          );
          final key = BookIdentity.indexedFilePath(crasher);
          final engine = _RecordingSearchEngine()
            ..failAddForTitle = crasher.title;
          final provider = _RecordingTantivyDataProvider(engine)
            ..activeIndexPath = '${temp.path}/index';
          final file = io.File('${provider.activeIndexPath}.in_flight.json');
          file.writeAsStringSync(jsonEncode({key: 2}));
          final library = Library(categories: [])
            ..books.addAll([crasher, healthy]);
          final repository = _FakeExtractionRepository(provider);
          if (fullRun) {
            await repository.indexAllBooks(library, onProgress: (_, _) {});
          } else {
            await repository.runIndexing(
              library,
              books: [crasher, healthy],
              onProgress: (_, _) {},
            );
          }
          expect(engine.commitCount, 1);
          expect(provider.indexedFilePaths, isNot(contains(key)));
          expect(jsonDecode(file.readAsStringSync()), {key: 2});
        },
      );
    }

    test(
      'התאוששות מנקה evidence חתום ושומרת evidence של מעקב ספקולטיבי',
      () async {
        final temp = await io.Directory.systemTemp.createTemp('canary_reader_');
        addTearDown(() => temp.delete(recursive: true));
        final speculative = TextBook(
          id: 1,
          title: 'טרם נשמר',
          source: BookSource.user,
        );
        final committed = TextBook(
          id: 2,
          title: 'נשמר',
          source: BookSource.user,
        );
        final healthy = TextBook(id: 3, title: 'חדש', source: BookSource.user);
        final speculativeKey = BookIdentity.indexedFilePath(
          speculative,
        );
        final committedKey = BookIdentity.indexedFilePath(
          committed,
        );
        final engine = _RecordingSearchEngine()
          ..committedFilePaths = [committedKey];
        final provider = _RecordingTantivyDataProvider(engine)
          ..activeIndexPath = '${temp.path}/index';
        provider.indexedFilePaths.addAll([speculativeKey, committedKey]);
        final file = io.File('${provider.activeIndexPath}.in_flight.json');
        file.writeAsStringSync(
          jsonEncode({speculativeKey: 2, committedKey: 2}),
        );
        final library = Library(categories: [])
          ..books.addAll([speculative, committed, healthy]);
        await _FakeExtractionRepository(
          provider,
        ).indexAllBooks(library, onProgress: (_, _) {});
        expect(jsonDecode(file.readAsStringSync()), {speculativeKey: 2});
      },
    );

    test('docx פגום (מעל מגבלת ה-ZIP) מסומן ככשל קבוע', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final book = TextBook(id: 536, title: 'שבת', source: BookSource.user);
      final library = Library(categories: [])..books.add(book);
      final repository = _FakeExtractionRepository(provider)
        ..textFailureByTitle[book.title] = const CorruptedDocumentException(
          format: DocumentFormat.docx,
          cause: 'הרשומה "word/document.xml" פרוסה ל-168141090 בתים',
        );

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(
        result.failures.single.kind,
        IndexingFailureKind.unreadableDocument,
      );
      expect(result.failures.single.isRetryable, isFalse);
      expect(
        provider.indexedFilePaths,
        contains(BookIdentity.indexedFilePath(book)),
      );
      expect(await repository.hasUnindexedBooks(library), isFalse);
    });

    test('כשל טעינה לא מזוהה בספר טקסט נשאר לניסיון חוזר', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final book = TextBook(id: 7, title: 'ברכות', source: BookSource.user);
      final library = Library(categories: [])..books.add(book);
      final repository = _FakeExtractionRepository(provider)
        ..textFailureByTitle[book.title] = StateError('קריאה נכשלה');

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.failures.single.kind, IndexingFailureKind.unknown);
      expect(result.retryableFailures, isNotEmpty);
      expect(
        provider.indexedFilePaths,
        isNot(contains(BookIdentity.indexedFilePath(book))),
      );
    });

    test('כשל rotation הקבוע מקבל סמן ריק ואינו מנוסה שוב', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'סיבוב פגום', path: r'C:\pdfs\rotation.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..failureByTitle[pdf.title] = RangeError.index(
          -1,
          const [0, 1, 2, 3],
          'rotation',
        );

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.failures.single.kind, IndexingFailureKind.pdfUnsupported);
      expect(result.failures.single.isRetryable, isFalse);
      expect(provider.indexedFilePaths, contains(pdf.path));
    });

    test('PDF חלקי מאונדקס אך מוחזר כאזהרה מפורטת', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'חלקי', path: r'C:\pdfs\partial.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..droppedPagesByTitle[pdf.title] = 7;

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(result.indexedBooks, 1);
      expect(result.warningCount, 1);
      expect(result.blockingFailureCount, 0);
      expect(result.retryableFailures, isEmpty);
      expect(result.failures.single.kind, IndexingFailureKind.partialPdf);
      expect(result.failures.single.error, contains('7'));
      expect(provider.indexedFilePaths, contains(pdf.path));
    });

    test(
      'כל העמודים ב-timeout — הספר נשאר לניסיון חוזר ולא מקבל סמן ריק',
      () async {
        // worker של pdfium שנתקע: כל loadText חורג, ואין עמוד אחד להוסיף. סימון
        // כ-partialPdf היה מחשיב את הספר מאונדקס עם אפס תוכן, לנצח.
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final pdf = PdfBook(title: 'נתקע', path: r'C:\pdfs\stuck.pdf');
        final library = Library(categories: [])..books.add(pdf);
        final repository = _FakeExtractionRepository(provider)
          ..emptyPagesTitles.add(pdf.title)
          ..droppedPagesByTitle[pdf.title] = 12;

        final result = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );

        expect(result.failures.single.kind, IndexingFailureKind.timeout);
        expect(result.retryableFailures, isNotEmpty);
        expect(provider.indexedFilePaths, isNot(contains(pdf.path)));
        expect(engine.addedDocuments, isEmpty);
      },
    );

    test(
      'עמודים ב-timeout ואפס תוכן שנוסף — ניסיון חוזר, לא סמן ריק',
      () async {
        // העמודים ששרדו סוננו במנוע כזבל: אין תוכן, אבל כן היו חריגות timeout,
        // ולכן זהו אינו PDF סרוק שראוי לסמן ריק.
        final engine = _RecordingSearchEngine()..addPdfReturnsZeroFor = 'מסונן';
        final provider = _RecordingTantivyDataProvider(engine);
        final pdf = PdfBook(title: 'מסונן', path: r'C:\pdfs\filtered.pdf');
        final library = Library(categories: [])..books.add(pdf);
        final repository = _FakeExtractionRepository(provider)
          ..droppedPagesByTitle[pdf.title] = 99;

        final result = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );

        expect(result.failures.single.kind, IndexingFailureKind.timeout);
        expect(provider.indexedFilePaths, isNot(contains(pdf.path)));
      },
    );

    test('ספר שקרס פעמיים חייב להידלג גם עם sidecar', () async {
      final temp = await io.Directory.systemTemp.createTemp('canary_sidecar_');
      addTearDown(() => temp.delete(recursive: true));
      final pdf = PdfBook(
        title: 'קורס עם sidecar',
        path: '${temp.path}/book.pdf',
      );
      await io.File('${pdf.path}.txt').writeAsString('תוכן OCR שקרס במנוע');
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine)
        ..activeIndexPath = '${temp.path}/index';
      io.File(
        '${provider.activeIndexPath}.in_flight.json',
      ).writeAsStringSync(jsonEncode({pdf.path: 2}));
      final library = Library(categories: [])..books.add(pdf);
      final result = await IndexingRepository(provider).indexAllBooks(
        library,
        onProgress: (_, _) {},
      );
      expect(
        engine.addedPdfTitles,
        isEmpty,
        reason: 'קובץ שמסווג כקורס אסור להישלח שוב למנוע',
      );
      expect(result.failures.single.kind, IndexingFailureKind.crashedApp);
    });

    test('sidecar מסונן אינו מסתיר timeout של חילוץ העמודים', () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'otzaria_pdf_sidecar_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final pdf = PdfBook(
        title: 'sidecar ריק',
        path: '${temp.path}${io.Platform.pathSeparator}stuck.pdf',
      );
      await io.File('${pdf.path}.txt').writeAsString('');

      final engine = _RecordingSearchEngine()..addPdfReturnsZeroFor = pdf.title;
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(provider)
        ..emptyPagesTitles.add(pdf.title)
        ..droppedPagesByTitle[pdf.title] = 8;
      final library = Library(categories: [])..books.add(pdf);

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.failures.single.kind, IndexingFailureKind.timeout);
      expect(provider.indexedFilePaths, isNot(contains(pdf.path)));
      expect(engine.addedPdfTitles, [pdf.title]);
    });

    test('sidecar מסונן אינו מסתיר timeout של פתיחת PDF', () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'otzaria_pdf_sidecar_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final pdf = PdfBook(
        title: 'פתיחה איטית',
        path: '${temp.path}${io.Platform.pathSeparator}slow.pdf',
      );
      await io.File('${pdf.path}.txt').writeAsString('טקסט שנדחה');

      final engine = _RecordingSearchEngine()..addPdfReturnsZeroFor = pdf.title;
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(provider)
        ..guardedOpenErrorByTitle[pdf.title] = TimeoutException(
          'PDF open timed out',
        );
      final library = Library(categories: [])..books.add(pdf);

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(
        result.failures.single.kind,
        IndexingFailureKind.unreadableDocument,
      );
      expect(result.failures.single.isRetryable, isFalse);
      expect(engine.addedPdfTitles, [pdf.title]);
    });

    test('PDF סרוק (אפס עמודים, בלי timeout) מקבל סמן ריק כמקודם', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'סרוק', path: r'C:\pdfs\scanned.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..emptyPagesTitles.add(pdf.title);

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.isClean, isTrue);
      expect(provider.indexedFilePaths, contains(pdf.path));
      expect(engine.addedDocuments, hasLength(1));
    });

    test('כשל בכתיבת סמן PDF קבוע אינו מפיל את הריצה', () async {
      final engine = _RecordingSearchEngine()..failAddForTitle = 'סיבוב פגום';
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'סיבוב פגום', path: r'C:\pdfs\rotation.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..failureByTitle[pdf.title] = RangeError.index(
          -1,
          const [0, 1, 2, 3],
          'rotation',
        );

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
      expect(result.failures.map((failure) => failure.kind), [
        IndexingFailureKind.pdfUnsupported,
        IndexingFailureKind.engineWrite,
      ]);
      expect(result.retryableFailures, isNotEmpty);
      expect(provider.indexedFilePaths, isNot(contains(pdf.path)));
      expect(engine.removedFilePaths, [pdf.path]);
      expect(engine.commitCount, 1);
    });

    test('timeout נשאר לניסיון חוזר ואינו מקבל סמן קבוע', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'איטי', path: r'C:\pdfs\slow.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..failureByTitle[pdf.title] = TimeoutException('PDF open timed out');

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.retryableFailures, isNotEmpty);
      expect(provider.indexedFilePaths, isNot(contains(pdf.path)));
      expect(engine.addedDocuments, isEmpty);

      // הריצה הבאה מנסה שוב — עומס רגעי לא מוציא ספר תקין מהאינדקס לתמיד.
      await repository.indexAllBooks(library, onProgress: (_, _) {});
      expect(repository.extractedTitles, [pdf.title, pdf.title]);
    });

    for (final entry in <String, Object>{
      'הרשאה': Exception('Access is denied. (os error 5)'),
    }.entries) {
      test('כשל ${entry.key} מסומן ואינו יוצר לולאת הפעלה', () async {
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final pdf = PdfBook(
          title: entry.key,
          path: 'C:\\pdfs\\${entry.key}.pdf',
        );
        final library = Library(categories: [])..books.add(pdf);
        final repository = _FakeExtractionRepository(provider)
          ..failureByTitle[pdf.title] = entry.value;

        final result = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );

        expect(result.completed, isTrue);
        expect(result.retryableFailures, isEmpty);
        expect(provider.indexedFilePaths, contains(pdf.path));
        expect(engine.addedDocuments, hasLength(1));

        final second = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );
        expect(second.isClean, isTrue);
        expect(repository.extractedTitles, [pdf.title]);
      });
    }

    test('כשל לא ידוע נשאר לניסיון חוזר ואינו מקבל סמן קבוע', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'לא ידוע', path: r'C:\pdfs\unknown.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..failureByTitle[pdf.title] = StateError('unexpected failure');

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.retryableFailures, isNotEmpty);
      expect(provider.indexedFilePaths, isNot(contains(pdf.path)));
      expect(engine.addedDocuments, isEmpty);
    });

    test('כשל פתיחת PDF לא מוכר מסומן ואינו חוזר בהפעלה הבאה', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'פתיחה נכשלה', path: r'C:\pdfs\broken.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..guardedOpenErrorByTitle[pdf.title] = Exception(
          'unknown PDFium open error',
        );

      final first = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );
      final second = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(first.failures.single.kind, IndexingFailureKind.pdfUnsupported);
      expect(first.retryableFailures, isEmpty);
      expect(second.isClean, isTrue);
      expect(provider.indexedFilePaths, contains(pdf.path));
      expect(repository.extractedTitles, [pdf.title]);
    });

    test('שינוי ספר מסיר את סמן הכשל ומאפשר אינדוקס אמיתי מחדש', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final pdf = PdfBook(title: 'הוחלף', path: r'C:\pdfs\replaced.pdf');
      final library = Library(categories: [])..books.add(pdf);
      final repository = _FakeExtractionRepository(provider)
        ..failureByTitle[pdf.title] = Exception('password required');

      final first = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );
      expect(first.failures.single.kind, IndexingFailureKind.passwordProtected);
      expect(provider.indexedFilePaths, contains(pdf.path));

      repository.failureByTitle.remove(pdf.title);
      final second = await _reindex(
        repository,
        [pdf],
        library,
        onProgress: (_, _) {},
      );

      expect(second.isClean, isTrue);
      expect(second.indexedBooks, 1);
      expect(engine.removedFilePaths, contains(pdf.path));
      expect(engine.addedPdfTitles, [pdf.title]);
      expect(provider.indexedFilePaths, contains(pdf.path));
      expect(repository.extractedTitles, [pdf.title, pdf.title]);
    });

    test(
      'ביטול באמצע — חילוצים שנותרו בתור נזרקים בלי שגיאה ללא-מטפל',
      () async {
        final engine = _RecordingSearchEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final library = Library(categories: []);
        final pdfs = [
          for (var i = 0; i < 20; i++)
            PdfBook(title: 'p$i', path: 'C:\\p$i.pdf'),
        ];
        library.books.addAll(pdfs);
        // כל התור מוזנק מראש, וכמה מהחילוצים ייכשלו אחרי הביטול.
        final repository = _FakeExtractionRepository(provider)
          ..failingTitles.addAll(['p8', 'p9', 'p10']);

        // ביטול אחרי הכתיבה הראשונה — התור מלא בחילוצים שלא ייצרכו.
        engine.onPdfAdded = (_) => provider.isIndexing.value = false;

        final result = await repository.indexAllBooks(
          library,
          onProgress: (_, _) {},
        );

        expect(result.completed, isFalse);
        // הריצה נעצרה מיד; שאר החילוצים נזרקו בלי להפיל את הריצה.
        expect(engine.addedPdfTitles.length, 1);
        await Future<void>.delayed(Duration.zero);
      },
    );

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
        BookIdentity.indexedFilePath(indexedText1),
        BookIdentity.indexedFilePath(indexedText2),
      ]);
      final repository = _FakeExtractionRepository(provider);

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );

      expect(result.completed, isTrue);
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
        // היה חותם את הכתיבה החלקית למרות הניקוי הכושל. הכשל בספר הראשון —
        // רק כך יש אחריו ספרים שטרם נוקזו, שהעצירה מוכחת עליהם.
        final engine = _RecordingSearchEngine()
          ..failAddForTitle = 'א'
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

        expect(result.completed, isFalse);
        expect(engine.commitCount, 0);
        expect(engine.rollbackCount, 1);
        // שני הספרים שאחרי הכושל לא עובדו — הריצה נעצרה מיד אחרי הכשל.
        expect(engine.addedDocuments.map((d) => d.title), ['א']);
        // המעקב בזיכרון נטען מחדש מהמצב החתום (ריק) — 'א' הלא-חתום ינוסה שוב.
        expect(provider.indexedFilePaths, isEmpty);
        expect(progressCalls, greaterThan(0));
      },
    );
  });

  group('IndexingRepository — ביטול בתוך טעינת מקור הספר', () {
    test('indexBooks עוצר ואינו מסמן את הספר כמאונדקס', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final first = TextBook(id: 1, title: 'שבת');
      final second = TextBook(id: 2, title: 'עירובין');
      final library = _buildLibrary(bavliBooks: const []);
      library.books.addAll([first, second]);

      final repository = _CancelDuringLoadRepository(provider);
      final progress = <(int, int)>[];
      final result = await repository.runIndexing(
        library,
        books: [first, second],
        onProgress: (p, t) => progress.add((p, t)),
      );

      expect(result.completed, isFalse);
      // רק הספר הראשון נטען, והוא לא נרשם כמאונדקס.
      expect(repository.loadedTitles, ['שבת']);
      expect(provider.indexedFilePaths, isEmpty);
      expect(result.indexedBooks, 0);
      // הדיווח נשאר כשהיה: הספר הנוכחי מדווח בתחילת עיבודו.
      expect(progress, [(1, 2)]);
    });
  });

  test('ספר בטקסט מפוענח נמסר למנוע כבתי UTF-8 ולא כ-String', () async {
    // קידוד String על גשר המנוע רץ על ה-UI isolate: ספר מצויר של 18M תווים
    // חסם אותו 337ms.
    final engine = _CancellationRecordingEngine();
    final repository = _FakeExtractionRepository(
      _RecordingTantivyDataProvider(engine),
    );
    final book = TextBook(id: 101, title: 'ספר');
    final library = Library(categories: [])..books.add(book);

    final result = await repository.runIndexing(
      library,
      books: [book],
      onProgress: (_, _) {},
    );

    expect(result.completed, isTrue);
    expect(engine.stringTextFilePaths, isEmpty);
    expect(engine.bytesByFilePath, {'id:101': utf8.encode('תוכן')});
  });

  group('IndexingRepository.runIndexing — איחוד בסוף', () {
    test('ריצה שהחליפה ספרים מאחדת בסופה, כשהריצה עדיין פעילה', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final book = TextBook(id: 101, title: 'ספר');
      final library = Library(categories: [])..books.add(book);
      bool? indexingDuringOptimize;
      engine.onOptimize = () =>
          indexingDuringOptimize = provider.isIndexing.value;
      var finalizingCalls = 0;

      provider.indexedFilePaths.add('id:101');
      final result = await _FakeExtractionRepository(provider).runIndexing(
        library,
        books: const [],
        changedBooks: [book],
        onProgress: (_, _) {},
        onFinalizing: () => finalizingCalls++,
      );

      expect(result.completed, isTrue);
      expect(engine.optimizeCount, 1);
      expect(indexingDuringOptimize, isTrue);
      expect(finalizingCalls, 1);
    });

    test('ריצה שבוטלה אינה מאחדת', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final book = TextBook(id: 101, title: 'ספר');
      final library = Library(categories: [])..books.add(book);
      engine.onTextAdded = (_) => provider.isIndexing.value = false;

      provider.indexedFilePaths.add('id:101');
      final result = await _FakeExtractionRepository(provider).runIndexing(
        library,
        books: const [],
        changedBooks: [book],
        onProgress: (_, _) {},
        onFinalizing: () => fail('onFinalizing בריצה שבוטלה'),
      );

      expect(result.completed, isFalse);
      expect(engine.optimizeCount, 0);
    });

    test('ספרים חדשים בלבד ברשימה — אינו מאחד', () async {
      final engine = _CancellationRecordingEngine();
      final book = TextBook(id: 101, title: 'ספר');
      final library = Library(categories: [])..books.add(book);

      await _FakeExtractionRepository(
        _RecordingTantivyDataProvider(engine),
      ).runIndexing(library, books: [book], onProgress: (_, _) {});

      expect(engine.optimizeCount, 0);
    });
  });

  group('IndexingRepository — ביטול אחרי כתיבת הספר הנוכחי', () {
    test('indexBooks: שומר את הקודם, מסיר את הנוכחי ומנסה אותו שוב', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(provider);
      final first = TextBook(id: 101, title: 'ראשון');
      final second = TextBook(id: 102, title: 'שני');
      final library = Library(categories: [])..books.addAll([first, second]);
      final firstKey = BookIdentity.indexedFilePath(first);
      final secondKey = BookIdentity.indexedFilePath(second);
      engine.onTextAdded = (title) {
        if (title == second.title) provider.isIndexing.value = false;
      };

      final cancelled = await repository.runIndexing(
        library,
        books: [first, second],
        onProgress: (_, _) {},
      );
      expect(cancelled.completed, isFalse);
      expect(cancelled.indexedBooks, 1);
      expect(engine.committedCounts, {firstKey: 1});
      expect(provider.indexedFilePaths, {firstKey});
      expect(engine.removedFilePaths, contains(secondKey));

      engine.onTextAdded = null;
      final resumed = await repository.runIndexing(
        library,
        books: [second],
        onProgress: (_, _) {},
      );
      expect(resumed.completed, isTrue);
      expect(engine.committedCounts, {firstKey: 1, secondKey: 1});
    });

    test('כשל בניקוי הספר שבוטל מונע commit של כל החוצץ', () async {
      final engine = _CancellationRecordingEngine()..failDeleteFilePaths = true;
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(provider);
      final first = TextBook(id: 109, title: 'ראשון');
      final second = TextBook(id: 110, title: 'שני');
      final library = Library(categories: [])..books.addAll([first, second]);
      engine.onTextAdded = (title) {
        if (title == second.title) provider.isIndexing.value = false;
      };

      final result = await repository.runIndexing(
        library,
        books: [first, second],
        onProgress: (_, _) {},
      );
      expect(result.completed, isFalse);
      expect(engine.commitCount, 0);
      expect(engine.rollbackCount, 1);
      expect(provider.indexedFilePaths, isEmpty);
    });

    test('indexBooks: ביטול בזמן כתיבת PDF אינו חותם אותו', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(provider);
      final first = TextBook(id: 103, title: 'ראשון');
      final pdf = PdfBook(title: 'שני', path: r'C:\pdfs\second.pdf');
      final library = Library(categories: [])..books.addAll([first, pdf]);
      final firstKey = BookIdentity.indexedFilePath(first);
      final pdfKey = BookIdentity.indexedFilePath(pdf);
      engine.onPdfAdded = (_) => provider.isIndexing.value = false;

      final cancelled = await repository.runIndexing(
        library,
        books: [first, pdf],
        onProgress: (_, _) {},
      );
      expect(cancelled.completed, isFalse);
      expect(engine.committedCounts, {firstKey: 1});
      expect(provider.indexedFilePaths, {firstKey});
      expect(engine.removedFilePaths, contains(pdfKey));

      engine.onPdfAdded = null;
      await repository.runIndexing(
        library,
        books: [pdf],
        onProgress: (_, _) {},
      );
      expect(engine.committedCounts, {firstKey: 1, pdfKey: 1});
    });

    test('indexAllBooks: ביטול בכתיבת טקסט שומר רק ספרים קודמים', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(provider);
      final first = TextBook(id: 104, title: 'ראשון');
      final second = TextBook(id: 105, title: 'שני');
      final library = Library(categories: [])..books.addAll([first, second]);
      final firstKey = BookIdentity.indexedFilePath(first);
      final secondKey = BookIdentity.indexedFilePath(second);
      engine.onTextAdded = (title) {
        if (title == second.title) provider.isIndexing.value = false;
      };

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );
      expect(result.completed, isFalse);
      expect(engine.committedCounts, {firstKey: 1});
      expect(provider.indexedFilePaths, {firstKey});
      expect(engine.removedFilePaths, contains(secondKey));
    });

    test('indexAllBooks: ביטול בכתיבת PDF במסלול הרגיל', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final repository = _FakeExtractionRepository(provider);
      final first = TextBook(id: 106, title: 'ראשון');
      final pdf = PdfBook(title: 'שני', path: r'C:\pdfs\second.pdf');
      final library = Library(categories: [])..books.addAll([first, pdf]);
      final firstKey = BookIdentity.indexedFilePath(first);
      final pdfKey = BookIdentity.indexedFilePath(pdf);
      engine.onPdfAdded = (_) => provider.isIndexing.value = false;

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );
      expect(result.completed, isFalse);
      expect(engine.committedCounts, {firstKey: 1});
      expect(provider.indexedFilePaths, {firstKey});
      expect(engine.removedFilePaths, contains(pdfKey));
    });

    test('indexAllBooks: ביטול בכתיבת PDF שנוקז מוקדם', () async {
      final engine = _CancellationRecordingEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final releasePdfExtraction = Completer<void>();
      final repository = _GatedPdfExtractionRepository(
        provider,
        releasePdfExtraction.future,
      );
      final first = TextBook(id: 107, title: 'ראשון');
      final middle = TextBook(id: 108, title: 'מדולג');
      final pdf = PdfBook(title: 'שלישי', path: r'C:\pdfs\third.pdf');
      final library = Library(categories: [])
        ..books.addAll([
          first,
          middle,
          pdf,
        ]);
      final firstKey = BookIdentity.indexedFilePath(first);
      final middleKey = BookIdentity.indexedFilePath(middle);
      final pdfKey = BookIdentity.indexedFilePath(pdf);
      provider.indexedFilePaths.add(middleKey);
      engine.onTextAdded = (_) => releasePdfExtraction.complete();
      engine.onPdfAdded = (_) => provider.isIndexing.value = false;

      final result = await repository.indexAllBooks(
        library,
        onProgress: (_, _) {},
      );
      expect(result.completed, isFalse);
      expect(result.indexedBooks, 1);
      expect(engine.committedCounts, {firstKey: 1});
      expect(provider.indexedFilePaths, {firstKey, middleKey});
      expect(engine.removedFilePaths, contains(pdfKey));
    });
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

    test('תנ״ך בגרשיים עבריים (כתיב ה-DB) מסווג כספר יסוד ראשון', () {
      final chumash = TextBook(
        title: 'בראשית',
        categoryPath: 'תנ״ך, תורה',
      );
      final mishna = TextBook(
        title: 'שבת',
        categoryPath: 'משנה, סדר מועד',
      );

      expect(IndexingRepository.foundationalTierForBook(chumash), 1);
      expect(
        IndexingRepository.chronologicalOrderForBook(chumash),
        lessThan(IndexingRepository.chronologicalOrderForBook(mishna)),
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

  group('BookIdentity.keyOf', () {
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
        BookIdentity.keyOf(first),
        isNot(BookIdentity.keyOf(second)),
      );
    });

    test('מבדיל בין ספר רשמי לספר אישי עם אותו id (חפיפת AUTOINCREMENT)', () {
      // id טבעי זהה בשני ה-DB — בלי תיוג המקור הספר האישי מדולג באינדוקס.
      final official = TextBook(id: 5, title: 'שבת');
      final userBook = TextBook(
        id: 5,
        title: 'הערות אישיות',
        source: BookSource.user,
      );

      expect(BookIdentity.keyOf(official), 'id:5');
      expect(BookIdentity.keyOf(userBook), 'uid:5');
    });

    test('ספר ממסד מצורף ממופתח db:<slug>:<id>, בלי לשנות את השאר', () {
      final attached = TextBook(
        id: 5,
        title: 'שבת',
        source: BookSource.attached('lib'),
      );
      final external = TextBook(
        id: 5,
        title: 'שבת',
        source: BookSource.attached('lib'),
        externalLibraryId: 'oh:9',
      );

      expect(BookIdentity.keyOf(attached), 'db:lib:5');
      // מסד מצורף קובע את ה-externalLibraryId בעצמו — אסור שיתנגש ברשמי.
      expect(BookIdentity.keyOf(external), 'db:lib:5');
      expect(
        BookIdentity.fromParts(title: 'שבת', bookId: 5),
        'id:5',
      );
    });

    test('ספר עם id או מזהה חיצוני אינו בונה את נתיב הקטגוריה', () {
      final category = _PathCountingCategory();
      final books = [
        TextBook(id: 5, title: 'שבת', category: category),
        TextBook(
          id: 5,
          title: 'שבת',
          category: category,
          source: BookSource.user,
        ),
        TextBook(
          id: 5,
          title: 'שבת',
          category: category,
          source: BookSource.attached('lib'),
        ),
        PdfBook(
          title: 'שבת',
          path: r'C:\books\a.pdf',
          category: category,
          externalLibraryId: 'oh:9',
        ),
      ];

      for (final book in books) {
        BookIdentity.keyOf(book);
      }

      // המפתח נבנה לכל ספר בכל מעבר על הספרייה (אינדוקס, חיפוש, הפעלה).
      expect(category.pathReads, 0);
    });

    test('המפתח זהה למפתח שנבנה מכל הרכיבים', () {
      final category = _PathCountingCategory();
      final books = <Book>[
        TextBook(id: 5, title: 'שבת', category: category),
        TextBook(
          id: 7,
          title: 'א',
          source: BookSource.user,
          category: category,
        ),
        TextBook(id: 3, title: 'ב', source: BookSource.attached('lib')),
        TextBook(title: 'ג', externalLibraryId: 'oh:1', category: category),
        TextBook(title: 'ד', externalLibraryId: '', category: category),
        TextBook(title: 'ה', categoryPath: 'תנ"ך, תורה', fileType: null),
        PdfBook(title: 'ו', path: r'C:\b\x.pdf', category: category),
        PdfBook(title: 'ז', path: '/b/y.pdf', externalLibraryId: 'hb:2'),
      ];

      for (final book in books) {
        expect(
          BookIdentity.keyOf(book),
          BookIdentity.fromParts(
            title: book.title,
            externalLibraryId: book.externalLibraryId,
            bookId: book.id,
            source: book.source,
            categoryKey: book.category?.path ?? book.categoryPath,
            fileTypeKey: book.fileType ?? book.runtimeType.toString(),
            pathKey: book is FileBook ? book.path : book.filePath,
          ),
          reason: book.title,
        );
      }
    });
  });

  group('BookIdentity.indexedFilePath', () {
    test('PdfBook ממופה לנתיב הקובץ, ספר טקסט למפתח הקטלוג', () {
      // המפתח הזה הוא שדה filePath של המסמכים באינדקס, ולכן הוא הבסיס
      // לשחזור מצב האינדוקס מהאינדקס עצמו (getIndexedFilePaths).
      final pdf = PdfBook(
        title: 'שבת',
        path: r'C:\books\a.pdf',
        categoryPath: 'תלמוד בבלי, סדר מועד',
      );
      final text = TextBook(title: 'בראשית');

      expect(BookIdentity.indexedFilePath(pdf), pdf.path);
      expect(
        BookIdentity.indexedFilePath(text),
        BookIdentity.keyOf(text),
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

    test('מסכת PDF מצורפת מוחרגת — הטקסט המלא שלה כבר באינדקס', () {
      final bundled = PdfBook(
        title: 'ברכות',
        path: r'C:\library\תלמוד בבלי\ברכות.pdf',
        externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
          'ברכות',
        ),
      );
      expect(IndexingRepository.isIndexableBook(bundled), isFalse);
    });

    test('PDF אישי נשאר אינדוקסיבילי גם בתיקייה בשם "תלמוד בבלי"', () {
      final personal = PdfBook(
        title: 'ברכות',
        path: r'C:\personal\תלמוד בבלי\ברכות.pdf',
        source: BookSource.user,
      );
      expect(IndexingRepository.isIndexableBook(personal), isTrue);

      final downloaded = PdfBook(
        title: 'ספר שהורד',
        path: r'C:\library\hbS45.pdf',
        externalLibraryId: 'hebrewbooks:12345',
      );
      expect(IndexingRepository.isIndexableBook(downloaded), isTrue);
    });
  });

  group('IndexingRepository.extractPageTextsWithRetry', () {
    test('עמוד שחרג מה-timeout מנוסה שוב בסוף ונשמר במקומו', () async {
      final attempts = <int>[];
      final result = await IndexingRepository.extractPageTextsWithRetry(
        pageCount: 4,
        loadPageText: (i) async {
          attempts.add(i);
          // עמודים 1 ו-2 נופלים רק בניסיון הראשון — תקיעה חולפת של ה-worker.
          final firstAttempt = attempts.where((a) => a == i).length == 1;
          if ((i == 1 || i == 2) && firstAttempt) return null;
          return 'עמוד $i';
        },
        beforeEachPage: () async => true,
      );

      expect(result, isNotNull);
      expect(result!.droppedPages, 0);
      expect(result.texts.keys.toList(), [0, 1, 2, 3]);
      expect(result.texts[2], 'עמוד 2');
      expect(attempts, [0, 1, 2, 3, 1, 2]);
    });

    test('עמוד שנכשל גם בניסיון החוזר נספר כנשמט', () async {
      final result = await IndexingRepository.extractPageTextsWithRetry(
        pageCount: 3,
        loadPageText: (i) async => i == 1 ? null : 'עמוד $i',
        beforeEachPage: () async => true,
      );

      expect(result!.droppedPages, 1);
      expect(result.texts.keys.toList(), [0, 2]);
    });

    test('ביטול האינדוקס באמצע הניסיון החוזר מחזיר null', () async {
      var calls = 0;
      final result = await IndexingRepository.extractPageTextsWithRetry(
        pageCount: 2,
        loadPageText: (i) async => null,
        beforeEachPage: () async => ++calls <= 2,
      );

      expect(result, isNull);
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
        BookIdentity.keyOf(docx),
        BookIdentity.keyOf(docx.toTextBook()),
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
          BookIdentity.keyOf(docx),
          BookIdentity.keyOf(docx.toTextBook()),
        );
      },
    );
  });

  group('IndexingRepository.textStorageFor', () {
    TextStorage decide(String filePath, int? id, {bool ready = true}) =>
        IndexingRepository.textStorageFor(
          filePath: filePath,
          libraryDbBookId: id,
          userBooksDbBookId: null,
          hostApiReady: ready,
          userBooksConfigured: true,
        );

    TextStorage decideUser(
      String filePath,
      int? id, {
      bool ready = true,
      bool configured = true,
    }) => IndexingRepository.textStorageFor(
      filePath: filePath,
      libraryDbBookId: null,
      userBooksDbBookId: id,
      hostApiReady: ready,
      userBooksConfigured: configured,
    );

    test('ספר רשמי שנקרא מ-seforim.db — הטקסט לא נשמר באינדקס', () {
      expect(decide('id:5', 5), TextStorage.libraryDb);
    });

    test('בלי SQLite משותף למנוע — הטקסט נשמר באינדקס', () {
      expect(decide('id:5', 5, ready: false), TextStorage.inIndex);
    });

    test('ספר אישי שנקרא משורות user_books.db — הטקסט לא נשמר באינדקס', () {
      expect(decideUser('uid:5', 5), TextStorage.libraryDb);
    });

    test('ספר אישי כשמקור הספרים האישיים אינו מוגדר — הטקסט נשמר', () {
      expect(decideUser('uid:5', 5, configured: false), TextStorage.inIndex);
    });

    test('ספר אישי בלי SQLite משותף למנוע — הטקסט נשמר באינדקס', () {
      expect(decideUser('uid:5', 5, ready: false), TextStorage.inIndex);
    });

    test('id של user_books.db אינו מתאים למפתח אחר', () {
      expect(decideUser('uid:5', null), TextStorage.inIndex);
      expect(decideUser('uid:6', 5), TextStorage.inIndex);
      expect(decideUser('id:5', 5), TextStorage.inIndex);
      expect(decideUser('ext:abc', 5), TextStorage.inIndex);
    });

    test('מקור שאינו seforim.db או מפתח אחר — הטקסט נשמר באינדקס', () {
      expect(decide('id:5', null), TextStorage.inIndex);
      expect(decide('id:6', 5), TextStorage.inIndex);
      expect(decide('uid:5', 5), TextStorage.inIndex);
      expect(decide('db:slug:5', 5), TextStorage.inIndex);
      expect(decide('ext:abc', 5), TextStorage.inIndex);
      expect(decide(r'C:\books\a.txt', 5), TextStorage.inIndex);
    });

    group('במסלול האינדוקס', () {
      tearDown(LibraryLineSource.debugReset);

      Future<_CancellationRecordingEngine> index({
        required bool hostApiReady,
        bool userBooksConfigured = false,
      }) async {
        LibraryLineSource.debugReset(engine: FakeLineSourceEngine());
        if (userBooksConfigured) {
          await LibraryLineSource.configureUserBooks('/db/user_books.db');
        }
        LibraryLineSource.debugHostApiReady = hostApiReady;
        final engine = _CancellationRecordingEngine();
        final provider = _RecordingTantivyDataProvider(engine);
        final repository = _FakeExtractionRepository(provider)
          ..libraryDbBookIdByTitle['מהמסד'] = 301
          ..userBooksDbBookIdByTitle['אישי'] = 7
          ..dataUriLinesByTitle['מהמסד'] = Uint32List.fromList([0, 2])
          ..dataUriLinesByTitle['אישי'] = Uint32List.fromList([3])
          ..dataUriLinesByTitle['מקובץ'] = Uint32List.fromList([1]);
        final fromDb = TextBook(id: 301, title: 'מהמסד');
        final fromFile = TextBook(id: 302, title: 'מקובץ');
        final personal = TextBook(
          id: 7,
          title: 'אישי',
          source: BookSource.user,
        );
        final library = Library(categories: [])
          ..books.addAll([fromDb, fromFile, personal]);
        final result = await repository.runIndexing(
          library,
          books: [fromDb, fromFile, personal],
          onProgress: (_, _) {},
        );
        expect(result.completed, isTrue);
        return engine;
      }

      test('רק הספר שנקרא מהמסד מאונדקס בלי טקסט', () async {
        final engine = await index(hostApiReady: true);
        expect(engine.textStorageByFilePath, {
          'id:301': TextStorage.libraryDb,
          'id:302': TextStorage.inIndex,
          'uid:7': TextStorage.inIndex,
        });
        // שורות התמונות נשמרות באינדקס רק בספר שטקסטו נקרא מהמסד.
        expect(engine.storedLinesByFilePath, {
          'id:301': [0, 2],
          'id:302': null,
          'uid:7': null,
        });
      });

      test('ספר אישי מהמסד מאונדקס בלי טקסט כשהמקור מוגדר', () async {
        final engine = await index(
          hostApiReady: true,
          userBooksConfigured: true,
        );
        expect(engine.textStorageByFilePath['uid:7'], TextStorage.libraryDb);
        expect(engine.storedLinesByFilePath['uid:7'], [3]);
        expect(engine.textStorageByFilePath['id:302'], TextStorage.inIndex);
      });

      test('כשהמנוע לא קיבל SQLite — הכול נשמר באינדקס', () async {
        final engine = await index(hostApiReady: false);
        expect(engine.textStorageByFilePath, {
          'id:301': TextStorage.inIndex,
          'id:302': TextStorage.inIndex,
          'uid:7': TextStorage.inIndex,
        });
        expect(engine.storedLinesByFilePath, {
          'id:301': null,
          'id:302': null,
          'uid:7': null,
        });
      });
    });
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

  group('מצב "בלי ספרים אישיים"', () {
    IndexingRepository repositoryFor(
      _RecordingTantivyDataProvider provider,
      IndexUpdateMode mode,
    ) => IndexingRepository(provider, indexUpdateMode: () => mode);

    test('ספרים אישיים יוצאים מרשימת האינדוקס', () {
      final official = TextBook(id: 1, title: 'שבת');
      final personal = TextBook(id: 1, title: 'אישי', source: BookSource.user);
      final attached = TextBook(
        id: 1,
        title: 'מצורף',
        source: BookSource.attached('lib'),
      );

      final attachedPdf = PdfBook(
        id: 2,
        title: 'מצורף סרוק',
        path: '/attached/scanned.pdf',
        source: attached.source,
      );

      expect(
        IndexingRepository.booksForIndexing(
          [official, personal, attached, attachedPdf],
          includePdfBooks: true,
          hidden: const HiddenLibrarySelection(),
          mode: IndexUpdateMode.libraryOnly,
        ),
        [official],
      );
    });

    test(
      'ספר אישי שאינו באינדקס אינו נחשב חסר — אין אינדוקס חוזר בכל עלייה',
      () async {
        final provider = _RecordingTantivyDataProvider(
          _RecordingSearchEngine(),
        );
        final library = _buildLibrary(bavliBooks: const [('שבת', 1)]);
        final personal = TextBook(
          id: 3,
          title: 'אישי',
          source: BookSource.user,
        );
        library.books.addAll([
          personal,
          TextBook(
            id: 3,
            title: 'מצורף',
            source: BookSource.attached('lib'),
          ),
        ]);
        provider.indexedFilePaths.addAll(
          library
              .getAllBooks()
              .where((book) => book.source.isOfficial)
              .where(IndexingRepository.isIndexableBook)
              .map(BookIdentity.indexedFilePath),
        );

        expect(
          await repositoryFor(
            provider,
            IndexUpdateMode.libraryOnly,
          ).hasUnindexedBooks(library),
          isFalse,
        );
        expect(
          await repositoryFor(provider, IndexUpdateMode.all).hasUnindexedBooks(
            library,
          ),
          isTrue,
          reason: 'חזרה ל"כל הספרים" מזהה את הספר האישי כחסר',
        );
      },
    );

    test('ניקוי היתומים מסיר את רשומות הספרים האישיים בלבד', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const []);
      final officialBook = TextBook(id: 7, title: 'רשמי');
      final personalText = TextBook(
        id: 1,
        title: 'אישי',
        source: BookSource.user,
      );
      final root = await io.Directory.systemTemp.createTemp('otzaria-personal');
      addTearDown(() => root.delete(recursive: true));
      final pdfFile = io.File(p.join(root.path, 'סרוק.pdf'))
        ..writeAsStringSync('');
      final personalPdf = PdfBook(
        title: 'סרוק',
        path: pdfFile.path,
        source: BookSource.user,
      );
      final hiddenFolder = io.Directory(p.join(root.path, 'מוסתרת'))
        ..createSync();
      final hiddenFolderPdf = p.join(hiddenFolder.path, 'אחר.pdf');
      // ספרייה שנמצאת בתוך תיקייה אישית — הקבצים שלה אינם אישיים.
      final nestedLibrary = p.join(hiddenFolder.path, 'ספרייה');
      final nestedLibraryPdf = p.join(nestedLibrary, 'רשמי.pdf');
      io.File(nestedLibraryPdf)
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      library.books.addAll([officialBook, personalText, personalPdf]);
      provider.indexedFilePaths.addAll({
        'id:7',
        'ext:abc',
        BookIdentity.indexedFilePath(personalText),
        BookIdentity.indexedFilePath(personalPdf),
        'uid:99', // ספר מתיקייה מוסתרת — אינו בעץ
        hiddenFolderPdf,
        nestedLibraryPdf,
      });

      final removed =
          await repositoryFor(
            provider,
            IndexUpdateMode.libraryOnly,
          ).dropOrphanedIndexEntries(
            library,
            customFolders: [
              CustomFolder(path: root.path, addedAt: DateTime(2026)),
              CustomFolder(
                path: hiddenFolder.path,
                hidden: true,
                addedAt: DateTime(2026),
              ),
            ],
            preservedHiddenUserBookKeys: {'uid:99'},
            attachedLibraries: const [],
            libraryRoot: nestedLibrary,
          );

      expect(removed, 4);
      expect(engine.commitCount, 1);
      expect(provider.indexedFilePaths, {'id:7', 'ext:abc', nestedLibraryPdf});
    });

    test('במצב "כל הספרים" הספרים האישיים נשמרים', () async {
      final engine = _RecordingSearchEngine();
      final provider = _RecordingTantivyDataProvider(engine);
      final library = _buildLibrary(bavliBooks: const []);
      final personal = TextBook(id: 1, title: 'אישי', source: BookSource.user);
      library.books.add(personal);
      provider.indexedFilePaths.addAll({'uid:1', 'uid:99'});

      final removed =
          await repositoryFor(
            provider,
            IndexUpdateMode.all,
          ).dropOrphanedIndexEntries(
            library,
            customFolders: const [],
            preservedHiddenUserBookKeys: {'uid:99'},
          );

      expect(removed, 0);
      expect(provider.indexedFilePaths, {'uid:1', 'uid:99'});
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
  String? activeIndexPath;

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

  @override
  bool get isEconomyIndexing => false;

  final _RecordingSearchEngine _engine;

  int reopenCount = 0;
  bool? lastReopenForce;

  @override
  bool isTempFallback = false;

  @override
  final Set<String> indexedFilePaths = {};

  @override
  String? activeIndexPath;

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

class _ReconcileTextBook extends TextBook {
  _ReconcileTextBook({required super.source, this.failure})
    : super(id: 7, title: 'ספר חסר', categoryId: 7);

  final DocumentConversionException? failure;

  @override
  Future<String> get text async {
    if (failure != null) throw failure!;
    return '';
  }
}

/// המחיקה והכתיבה אמיתיות מול המנוע המקליט; נרשמים הספרים שנטענו לכתיבה.
class _ReindexProbeRepository extends _FakeExtractionRepository {
  _ReindexProbeRepository(super.provider, {super.hiddenStore});

  List<Book>? indexedBooks;

  @override
  Future<_TextBookSource> loadTextBookSource(TextBook book) {
    (indexedBooks ??= []).add(book);
    return super.loadTextBookSource(book);
  }
}

class _FixedHiddenStore extends HiddenLibraryStore {
  const _FixedHiddenStore(this.selection);

  final HiddenLibrarySelection selection;

  @override
  HiddenLibrarySelection load() => selection;
}

typedef _TextBookSource = ({
  Uint8List? bytes,
  String? text,
  int? libraryDbBookId,
  int? userBooksDbBookId,
  int? attachedDbBookId,
  Uint32List? dataUriLines,
});

/// טעינת מקור הספר מתפרקת לשלבים עם yield (קריאת ה-DB במנות, עבודת ה-data
/// URI ב-isolate); הבדיקה מקבעת שביטול שנפל בתוך הטעינה עדיין נכבד.
class _CancelDuringLoadRepository extends IndexingRepository {
  _CancelDuringLoadRepository(this.provider) : super(provider);

  final _RecordingTantivyDataProvider provider;
  final loadedTitles = <String>[];

  @override
  Future<_TextBookSource> loadTextBookSource(TextBook book) async {
    loadedTitles.add(book.title);
    await Future<void>.delayed(Duration.zero);
    provider.isIndexing.value = false; // לחיצת ביטול בזמן טעינת התוכן
    return (
      bytes: null,
      text: 'תוכן',
      libraryDbBookId: null,
      userBooksDbBookId: null,
      attachedDbBookId: null,
      dataUriLines: null,
    );
  }
}

/// מחליף את חילוץ ה-PDF (pdfrx) בתוכן מזויף — לבדיקת צינור ה-prefetch
/// והניקוז המוקדם בלי קבצים אמיתיים.
class _FakeExtractionRepository extends IndexingRepository {
  _FakeExtractionRepository(super.provider, {super.hiddenStore});

  final extractedTitles = <String>[];

  /// שיא החילוצים שהיו בטיסה יחד — מודד את עומק ההזנקה מראש בפועל.
  int _activeExtractions = 0;
  int peakConcurrentExtractions = 0;

  /// כותרות שחילוצן ייכשל — לבדיקת שחרור הסלוט והפצת השגיאה.
  final failingTitles = <String>{};
  final failureByTitle = <String, Object>{};

  /// כותרות ספרי טקסט שטעינת התוכן שלהן תיכשל בחריגה הנתונה.
  final textFailureByTitle = <String, Object>{};
  final guardedOpenErrorByTitle = <String, Object>{};
  final droppedPagesByTitle = <String, int>{};

  /// כותרות שחילוצן מחזיר אפס עמודים — PDF סרוק, או כל העמודים ב-timeout.
  final emptyPagesTitles = <String>{};

  /// ה-id ב-seforim.db שממנו "נקרא" ספר הטקסט, לפי כותרת.
  final libraryDbBookIdByTitle = <String, int>{};

  /// ה-id ב-user_books.db שממנו "נקרא" ספר אישי, לפי כותרת.
  final userBooksDbBookIdByTitle = <String, int>{};

  /// שורות התמונות שנוקו מספר הטקסט, לפי כותרת.
  final dataUriLinesByTitle = <String, Uint32List>{};

  /// כותרות שהמסד מחזיר להן טקסט ריק — נכתב להן סמן ריק.
  final emptyTextTitles = <String>{};

  @override
  Future<_TextBookSource> loadTextBookSource(TextBook book) async {
    final failure = textFailureByTitle[book.title];
    if (failure != null) throw failure;
    return (
      bytes: null,
      text: emptyTextTitles.contains(book.title) ? '' : 'תוכן',
      libraryDbBookId: libraryDbBookIdByTitle[book.title],
      userBooksDbBookId: userBooksDbBookIdByTitle[book.title],
      attachedDbBookId: null,
      dataUriLines: dataUriLinesByTitle[book.title],
    );
  }

  @override
  Future<PdfExtraction> extractPdfPagesGuarded(PdfBook book) async {
    extractedTitles.add(book.title);
    _activeExtractions++;
    peakConcurrentExtractions = max(
      peakConcurrentExtractions,
      _activeExtractions,
    );
    // בלי סבב אירועים החילוץ מסתיים סינכרונית, ושיא המקביליות היה תמיד 1.
    await Future<void>.delayed(Duration.zero);
    _activeExtractions--;
    final guardedOpenError = guardedOpenErrorByTitle[book.title];
    if (guardedOpenError != null) {
      return (
        pages: const <({String reference, String text, int pageIndex})>[],
        outline: const <PdfOutlineNode>[],
        error: guardedOpenError,
        stackTrace: StackTrace.current,
        extractMs: 0,
        droppedPages: 0,
      );
    }
    final configuredFailure = failureByTitle[book.title];
    if (configuredFailure != null) {
      throw configuredFailure;
    }
    if (failingTitles.contains(book.title)) {
      throw StateError('חילוץ נכשל: ${book.title}');
    }
    final PdfExtraction extraction = (
      pages: emptyPagesTitles.contains(book.title)
          ? const <({String reference, String text, int pageIndex})>[]
          : [
              (reference: '${book.title}, עמוד 1', text: 'תוכן', pageIndex: 0),
            ],
      outline: const [],
      error: null,
      stackTrace: null,
      extractMs: 0,
      droppedPages: droppedPagesByTitle[book.title] ?? 0,
    );
    return extraction;
  }
}

class _GatedPdfExtractionRepository extends _FakeExtractionRepository {
  _GatedPdfExtractionRepository(super.provider, this.extractionGate);

  final Future<void> extractionGate;

  @override
  Future<PdfExtraction> extractPdfPagesGuarded(PdfBook book) async {
    await extractionGate;
    return super.extractPdfPagesGuarded(book);
  }
}

/// מדמה חוצץ writer: commit חותם רק מסמכים שלא נמחקו עד לאותה נקודה.
class _CancellationRecordingEngine extends _RecordingSearchEngine {
  final pendingCounts = <String, int>{};
  final committedCounts = <String, int>{};
  final textStorageByFilePath = <String, TextStorage>{};
  final storedLinesByFilePath = <String, Uint32List?>{};

  /// מה שהגיע ל-addTextBookBytes; ספר שנמסר כ-String אינו נרשם כאן.
  final bytesByFilePath = <String, List<int>>{};
  final sourceHashByFilePath = <String, BigInt>{};
  final stringTextFilePaths = <String>[];
  void Function(String title)? onTextAdded;

  void _add(String key) =>
      pendingCounts.update(key, (n) => n + 1, ifAbsent: () => 1);

  int _addText(
    String title,
    String filePath,
    TextStorage textStorage,
    Uint32List? storedLines,
  ) {
    _add(filePath);
    textStorageByFilePath[filePath] = textStorage;
    storedLinesByFilePath[filePath] = storedLines;
    onTextAdded?.call(title);
    return 1;
  }

  @override
  Future<int> addTextBook({
    required String title,
    required String topics,
    required String filePath,
    required String text,
    BigInt? sourceHash,
    List<String>? extraFacets,
    required TextStorage textStorage,
    Uint32List? storedLines,
  }) async {
    stringTextFilePaths.add(filePath);
    return _addText(title, filePath, textStorage, storedLines);
  }

  @override
  Future<int> addTextBookBytes({
    required String title,
    required String topics,
    required String filePath,
    required List<int> text,
    BigInt? sourceHash,
    List<String>? extraFacets,
    required TextStorage textStorage,
    Uint32List? storedLines,
  }) async {
    bytesByFilePath[filePath] = text;
    if (sourceHash != null) sourceHashByFilePath[filePath] = sourceHash;
    return _addText(title, filePath, textStorage, storedLines);
  }

  @override
  Future<int> addPdfBookBytes({
    required String title,
    required String topics,
    required String filePath,
    required List<int> bytes,
    required List<int> ends,
    required List<int> pageIndexes,
    List<String>? extraFacets,
  }) async {
    _add(filePath);
    addedPdfTitles.add(title);
    onPdfAdded?.call(title);
    return pageIndexes.length;
  }

  @override
  Future<void> deleteDocumentsByFilePaths({
    required List<String> filePaths,
  }) async {
    await super.deleteDocumentsByFilePaths(filePaths: filePaths);
    for (final key in filePaths) {
      pendingCounts.remove(key);
      pendingDeletes.add(key);
    }
  }

  /// כמו ב-Tantivy: מחיקה חלה על מה שנחתם לפניה, ולא על מה שנוסף אחריה.
  final pendingDeletes = <String>{};

  @override
  Future<void> commit() async {
    await super.commit();
    pendingDeletes
      ..forEach(committedCounts.remove)
      ..clear();
    for (final entry in pendingCounts.entries) {
      committedCounts.update(
        entry.key,
        (n) => n + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    pendingCounts.clear();
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
  Future<int> addPdfBookBytes({
    required String title,
    required String topics,
    required String filePath,
    required List<int> bytes,
    required List<int> ends,
    required List<int> pageIndexes,
    List<String>? extraFacets,
  }) async {
    addedPdfTitles.add(title);
    onPdfAdded?.call(title);
    if (title == failPdfAddForTitle) {
      throw StateError('engine pdf write failed');
    }
    // המנוע מסנן זבל בעצמו ועשוי להחזיר 0 גם כשנשלחו אליו עמודים.
    if (title == addPdfReturnsZeroFor) return 0;
    return pageIndexes.length;
  }

  /// כותרת שכתיבתה למנוע מחזירה 0 מסמכים — כל העמודים סוננו כזבל.
  String? addPdfReturnsZeroFor;

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

  int optimizeCount = 0;
  void Function()? onOptimize;

  @override
  Future<void> optimize() async {
    optimizeCount++;
    onOptimize?.call();
  }

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

  /// חותמות כמו של המנוע: textHash מ-[fingerprints], ו-metadata של [_metadata].
  @override
  Future<List<BookStamps>> getBookStamps() async => [
    for (final MapEntry(:key, :value) in fingerprints.entries)
      BookStamps(
        filePath: key,
        bookNumber: 1,
        documents: 1,
        contentHash: value,
        textHash: value,
        metadataHash: metadataHashes[key] ?? _metadata,
        sourceHash: sourceHashes[key] ?? BigInt.zero,
      ),
  ];

  final pushedOrders = <List<BookOrderEntry>>[];

  @override
  Future<BigInt> setBookOrder({required List<BookOrderEntry> entries}) async {
    pushedOrders.add(entries);
    return BigInt.from(pushedOrders.length);
  }

  final metadataHashes = <String, BigInt>{};
  final sourceHashes = <String, BigInt>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}

final _metadata = BigInt.from(77);

/// בודק לפי חותמות, שטביעת הטקסט שלו נבנית מ-[loadText] ו-[fingerprintOf].
StampChangeDetector _textDetector(
  IndexingRepository repository, {
  Future<String?> Function(TextBook book)? loadText,
  Future<BigInt> Function(TextBook book, String text)? fingerprintOf,
  BookSourceHashes? sourceHashes,
  BigInt Function(String title)? metadataOf,
}) => StampChangeDetector(
  repository,
  loadSourceHashes: (_) async => sourceHashes ?? BookSourceHashes.none,
  metadataFingerprint:
      ({
        required String title,
        required String topics,
        List<String>? extraFacets,
      }) => metadataOf?.call(title) ?? _metadata,
  textMatchesIndex: fingerprintOf == null || loadText == null
      ? null
      : (book, textHash) async {
          final text = await loadText(book as TextBook);
          if (text == null) return true;
          return await fingerprintOf(book, text) == textHash;
        },
);

/// שלב בדיקה והחלפה בלבד, בלי אינדוקס ספרים חדשים.
Future<IndexingRunResult> _reconcile(
  IndexingRepository repository,
  Library library, {
  List<Book>? onlyBooks,
  void Function(int processed, int total)? onScanProgress,
  required void Function(int processed, int total) onProgress,
  Future<String?> Function(TextBook book)? loadText,
  Future<BigInt> Function(TextBook book, String text)? fingerprintOf,
}) {
  repository.changeDetector = _textDetector(
    repository,
    loadText: loadText,
    fingerprintOf: fingerprintOf,
  );
  return repository.runIndexing(
    library,
    books: const [],
    check: onlyBooks == null
        ? IndexCheckScope.library
        : IndexCheckScope.books(onlyBooks),
    onScanProgress: onScanProgress,
    onProgress: onProgress,
  );
}

/// החלפת ספרים שדווחו כשונים, בלי ספרים חדשים.
Future<IndexingRunResult> _reindex(
  IndexingRepository repository,
  List<Book> changedBooks,
  Library library, {
  required void Function(int processed, int total) onProgress,
  void Function()? onFinalizing,
}) => repository.runIndexing(
  library,
  books: const [],
  changedBooks: changedBooks,
  onProgress: onProgress,
  onFinalizing: onFinalizing,
);

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

class _PathCountingCategory extends Category {
  _PathCountingCategory()
    : super(
        title: 'תורה',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: null,
      );

  int pathReads = 0;

  @override
  String get path {
    pathReads++;
    return super.path;
  }
}

Future<BigInt> _fakeContentFingerprint({required List<int> text}) async =>
    BigInt.from(1000 + text.length);
