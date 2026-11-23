import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration;
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart' show PdfBook;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup/backup_import_merge.dart';
import 'package:otzaria/settings/services/backup/backup_merge.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/services/pdf_tracking_identity.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late Map<String, int> fixtureBookIds;
  late MemoryCacheProvider cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sz_provider_test_');
    dbPath = '${tempDir.path}/seforim.db';
    final database = MyDatabase.withPath(dbPath);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    fixtureBookIds = await _insertFixture(repository);
    database.close();

    cache = MemoryCacheProvider();
    await Settings.init(cacheProvider: cache);
    await _setLibrarySettings(tempDir.path);
    await Settings.setValue<String>(
      'sz:tracked_books',
      '[${fixtureBookIds['ספר אישי']}]',
    );

    await SqliteDataProvider.instance.dispose();
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('כשל טעינת TOC אינו נצרב בקאש — ניסיון חוזר מצליח', () async {
    await SqliteDataProvider.instance.initialize();
    final provider = ShamorZachorDataProvider(
      sqliteDataProvider: SqliteDataProvider.instance,
    );
    addTearDown(provider.dispose);
    final bookId = fixtureBookIds['בראשית']!;

    addTearDown(() async {
      await FindRefDbIsolate.resumeAfterExternalWrite();
      (await FindRefDbIsolate.instance()).disposeForTesting();
    });

    // ה-worker ללא חיבור מדמה כשל זמני (נפילה, או חלון כתיבה חיצונית).
    await FindRefDbIsolate.suspendForExternalWrite();
    expect(await provider.getTocForBook(bookId), isEmpty);

    await FindRefDbIsolate.resumeAfterExternalWrite();
    final sections = await provider.getTocForBook(bookId);

    expect(sections, isNotEmpty, reason: 'הכשל נצרב בקאש במקום להתאפשר שוב');
    expect(sections.first.title, 'פרק א');
  });

  test('loadAllData hydrates provider state from loader result', () async {
    final provider = ShamorZachorDataProvider(
      sqliteDataProvider: SqliteDataProvider.instance,
      categoryTreeLoader:
          ({
            required String dbPath,
            required List<int> trackedBookIds,
          }) async {
            expect(dbPath, endsWith('seforim.db'));
            expect(trackedBookIds, [fixtureBookIds['ספר אישי']]);
            return {
              'categories': [
                {
                  'name': 'תנ"ך',
                  'contentType': 'text',
                  'books': {
                    'בראשית': {
                      'contentType': 'text',
                      'id': 10,
                      'originalPageCount': 3,
                      'parts': [
                        {'name': 'ראשי', 'start': 1, 'end': 3},
                      ],
                      'sections': [
                        {
                          'id': '1000',
                          'title': 'פרק א',
                          'level': 1,
                          'startPage': 0,
                          'endPage': 2,
                        },
                      ],
                      'categoryPath': 'תנ"ך',
                    },
                  },
                  'defaultStartPage': 1,
                  'isCustom': false,
                  'sourceFile': 'db',
                  'schemaVersion': 1,
                },
              ],
              'relevantBookCount': 2,
              'allBookCount': 3,
              'categoryCount': 3,
            };
          },
    );
    addTearDown(provider.dispose);

    await provider.loadAllData();

    expect(provider.error, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.hasData, isTrue);

    final category = provider.getCategory('תנ"ך');
    expect(category, isNotNull);
    expect(category!.contentType, 'text');

    final details = provider.getBookDetails('תנ"ך', 'בראשית');
    expect(details, isNotNull);
    expect(details!.id, 10);
    expect(details.categoryPath, 'תנ"ך');
    expect(details.sections, isNotNull);
    expect(details.sections, hasLength(1));
    expect(details.sections!.single.title, 'פרק א');
  });

  test(
    'loadAllData falls back to sqlite provider when loader throws',
    () async {
      final provider = ShamorZachorDataProvider(
        sqliteDataProvider: SqliteDataProvider.instance,
        categoryTreeLoader:
            ({
              required String dbPath,
              required List<int> trackedBookIds,
            }) async {
              throw Exception('worker failed');
            },
      );
      addTearDown(provider.dispose);

      await provider.loadAllData();

      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.hasData, isTrue);

      final category = provider.getCategory('תנ"ך');
      expect(category, isNotNull);

      final details = provider.getBookDetails('תנ"ך', 'בראשית');
      expect(details, isNotNull);
      expect(details!.id, fixtureBookIds['בראשית']);
      expect(details.categoryPath, 'תנ"ך');

      expect(provider.getBookDetails('תנ"ך', 'ספר אישי'), isNotNull);
      expect(provider.getBookDetails('תנ"ך', 'לא במעקב'), isNull);
    },
  );

  group('addCustomBooks', () {
    ShamorZachorDataProvider buildProvider() => ShamorZachorDataProvider(
      sqliteDataProvider: SqliteDataProvider.instance,
      categoryTreeLoader:
          ({
            required String dbPath,
            required List<int> trackedBookIds,
          }) async {
            throw Exception('force fallback');
          },
    );

    test('מזהה לפי id מול המסד הרשמי גם כשהשם לא קיים', () async {
      final provider = buildProvider();
      addTearDown(provider.dispose);
      await provider.loadAllData();

      final result = await provider.addCustomBooks([
        (
          id: fixtureBookIds['לא במעקב'],
          bookName: 'שם שלא קיים במסד',
          categoryId: null,
        ),
      ]);

      expect(result.added, 1);
      expect(result.failed, 0);
      expect(provider.trackedBookIds, contains(fixtureBookIds['לא במעקב']));
    });

    test('נופל לזיהוי לפי כותרת כאשר אין id', () async {
      final provider = buildProvider();
      addTearDown(provider.dispose);
      await provider.loadAllData();

      final result = await provider.addCustomBooks([
        (id: null, bookName: 'לא במעקב', categoryId: null),
      ]);

      expect(result.added, 1);
      expect(provider.trackedBookIds, contains(fixtureBookIds['לא במעקב']));
    });

    test('ספר שלא נמצא נספר ככישלון', () async {
      final provider = buildProvider();
      addTearDown(provider.dispose);
      await provider.loadAllData();

      final result = await provider.addCustomBooks([
        (id: null, bookName: 'ספר שאינו קיים', categoryId: null),
      ]);

      expect(result.added, 0);
      expect(result.failed, 1);
    });
  });

  group('track PDF books in shamor zachor (issue #4345)', () {
    // מזהה היברובוקס שחופף במקרה למזהה ספר רשמי ב-seforim.db.
    PdfBook hebrewBooksPdf() => PdfBook(
      title: 'ספר מהיברובוקס',
      id: fixtureBookIds['בראשית'],
      path: '/hebrewbooks/123.pdf',
      externalLibraryId: 'hb:123',
    );

    /// קובץ PDF אמיתי בתיקיית הבדיקה; [content] קובע את זהותו.
    String pdfFile(String relativePath, String content) {
      final file = File(p.join(tempDir.path, 'pdfs', relativePath))
        ..createSync(recursive: true)
        ..writeAsStringSync('%PDF-1.4 $content');
      return file.path;
    }

    ShamorZachorDataProvider buildProvider({
      int pageCount = 3,
      List<PdfOutlineNode> outline = const [],
      Future<({int pageCount, List<PdfOutlineNode> outline})> Function(
        String path,
      )?
      pdfInfoLoader,
    }) => ShamorZachorDataProvider(
      sqliteDataProvider: SqliteDataProvider.instance,
      categoryTreeLoader:
          ({
            required String dbPath,
            required List<int> trackedBookIds,
          }) async {
            throw Exception('force fallback');
          },
      pdfInfoLoader:
          pdfInfoLoader ??
          (path) async => (pageCount: pageCount, outline: outline),
    );

    Map<String, BookDetails> pdfBooks(ShamorZachorDataProvider provider) =>
        provider.getCategory(ShamorZachorDataProvider.pdfCategoryName)?.books ??
        const {};

    List<Map<String, dynamic>> persistedPdfBooks() => [
      for (final e
          in jsonDecode(
                Settings.getValue<String>('sz:tracked_pdf_books') ?? '[]',
              )
              as List)
        (e as Map).cast<String, dynamic>(),
    ];

    int persistedKeyOf(String title) =>
        persistedPdfBooks().singleWhere((e) => e['title'] == title)['key']
            as int;

    PdfOutlineNode node(
      String title,
      int page, [
      List<PdfOutlineNode> children = const [],
    ]) => PdfOutlineNode(
      title: title,
      dest: PdfDest(page, PdfDestCommand.xyz, null),
      children: children,
    );

    test('PDF עם outline: הפריטים הם עלי ה-outline', () async {
      final provider = buildProvider(
        pageCount: 6,
        outline: [
          node('חלק א', 1, [node('פרק א', 1), node('פרק ב', 3)]),
          node('חלק ב', 5),
        ],
      );
      addTearDown(provider.dispose);
      await provider.loadAllData();

      final result = await provider.addPdfBooks([hebrewBooksPdf()]);

      expect(result, (added: 1, failed: 0));
      final details = pdfBooks(provider)['ספר מהיברובוקס']!;
      expect(details.learnableItems.map((i) => i.displayLabel), [
        'פרק א',
        'פרק ב',
        'חלק ב',
      ]);
      expect(details.learnableItems.map((i) => i.pageNumber), [1, 3, 5]);
    });

    test('PDF בלי outline: פריט לכל עמוד', () async {
      final provider = buildProvider(pageCount: 3);
      addTearDown(provider.dispose);
      await provider.loadAllData();

      await provider.addPdfBooks([hebrewBooksPdf()]);

      final details = pdfBooks(provider)['ספר מהיברובוקס']!;
      expect(details.learnableItems.map((i) => i.pageNumber), [1, 2, 3]);
    });

    test(
      'מפתח ה-PDF לא מתנגש בספר רשמי עם אותו id, ונשמר בין הפעלות',
      () async {
        final provider = buildProvider();
        addTearDown(provider.dispose);
        await provider.loadAllData();
        await provider.addPdfBooks([hebrewBooksPdf()]);

        final key = pdfBooks(provider)['ספר מהיברובוקס']!.id!;
        expect(key, PdfTrackingIdentity.keyOf('ext:hb:123'));
        expect(
          provider.getBookDetails('תנ"ך', 'בראשית')!.id,
          fixtureBookIds['בראשית'],
        );
        expect(provider.isBookTrackedById(key), isTrue);
        expect(
          provider.isBookTrackedById(fixtureBookIds['בראשית']!),
          isFalse,
        );
        expect(await provider.isPdfBookTracked(hebrewBooksPdf()), isTrue);

        final reloaded = buildProvider();
        addTearDown(reloaded.dispose);
        await reloaded.loadAllData();
        expect(pdfBooks(reloaded)['ספר מהיברובוקס']?.id, key);
        expect(
          (await reloaded.addPdfBooks([hebrewBooksPdf()])).added,
          0,
          reason: 'אותו PDF אינו נוסף פעמיים',
        );

        await reloaded.removeBookFromTracking(key);
        expect(pdfBooks(reloaded), isEmpty);
        expect(reloaded.isBookTrackedById(key), isFalse);
      },
    );

    test('שני קובצי PDF בעלי שם זהה נשמרים במעקב זה לצד זה', () async {
      final provider = buildProvider();
      addTearDown(provider.dispose);
      await provider.loadAllData();

      final result = await provider.addPdfBooks([
        PdfBook(title: 'שו"ת', path: pdfFile('a/שו"ת.pdf', 'חלק א')),
        PdfBook(title: 'שו"ת', path: pdfFile('b/שו"ת.pdf', 'חלק ב')),
      ]);

      expect(result, (added: 2, failed: 0));
      final books = pdfBooks(provider);
      expect(books, hasLength(2), reason: 'ספר אחד דרס את השני ברשימה');
      expect(books.values.map((b) => b.id).toSet(), hasLength(2));
      for (final id in books.values.map((b) => b.id!)) {
        expect(provider.isBookTrackedById(id), isTrue);
      }
    });

    test('ספר PDF אישי שהועבר לנתיב חדש נשאר במעקב לפי תוכנו', () async {
      final provider = buildProvider();
      addTearDown(provider.dispose);
      await provider.loadAllData();
      PdfBook personal(String path) => PdfBook(
        title: 'סיכומים',
        id: 5,
        source: BookSource.user,
        path: path,
      );

      final oldPath = pdfFile('old/סיכומים.pdf', 'סיכומים');
      await provider.addPdfBooks([personal(oldPath)]);
      final newPath = p.join(tempDir.path, 'pdfs', 'new', 'סיכומים.pdf');
      Directory(p.dirname(newPath)).createSync(recursive: true);
      File(oldPath).renameSync(newPath);
      final moved = personal(newPath);

      expect(await provider.isPdfBookTracked(moved), isTrue);
      expect((await provider.addPdfBooks([moved])).added, 0);
      expect(pdfBooks(provider), hasLength(1));
      expect(
        await provider.findTrackedPdf(pdfBooks(provider).values.single.id!, [
          moved,
        ]),
        same(moved),
      );
      pdfFile('old/סיכומים.pdf', 'קובץ אחר');
      expect(
        await provider.isPdfBookTracked(personal(oldPath)),
        isFalse,
        reason: 'קובץ אחר באותו נתיב אינו הספר שבמעקב',
      );
    });

    test(
      'רענון בזמן הוספת אצווה אינו מאבד אף PDF מהמעקב ומהתצוגה',
      () async {
        final secondInfo = Completer<void>();
        final secondRequested = Completer<void>();
        final provider = buildProvider(
          pdfInfoLoader: (path) async {
            if (path.endsWith('b.pdf')) {
              secondRequested.complete();
              await secondInfo.future;
            }
            return (pageCount: 2, outline: const <PdfOutlineNode>[]);
          },
        );
        addTearDown(provider.dispose);
        await provider.loadAllData();

        final adding = provider.addPdfBooks([
          PdfBook(title: 'ספר א', path: pdfFile('a.pdf', 'א')),
          PdfBook(title: 'ספר ב', path: pdfFile('b.pdf', 'ב')),
        ]);
        await secondRequested.future;
        await provider.loadAllData();
        secondInfo.complete();
        final result = await adding;

        expect(result, (added: 2, failed: 0));
        expect(persistedPdfBooks(), hasLength(2));
        expect(pdfBooks(provider).keys, containsAll(['ספר א', 'ספר ב']));

        final reloaded = buildProvider();
        addTearDown(reloaded.dispose);
        await reloaded.loadAllData();
        expect(pdfBooks(reloaded).keys, containsAll(['ספר א', 'ספר ב']));
      },
    );

    group('זהות בין מכשירים וגיבוי (סגירת #5767)', () {
      /// עובר ל"מכשיר" אחר: הגדרות ריקות, אותה ספרייה רשמית.
      Future<void> switchDevice() async {
        cache = MemoryCacheProvider();
        await Settings.init(cacheProvider: cache);
        await _setLibrarySettings(tempDir.path);
      }

      Map<String, dynamic> szData() => {
        for (final key in cache.getKeys().cast<String>())
          if (key.startsWith('sz:')) key: cache.getValue<Object>(key),
      };

      /// מכשיר שעוקב אחרי ספר PDF אחד ([title], בתוכן [content]) ומסמן בו
      /// "לימוד" בפריטים [marked]. מחזיר את מפתח הספר במכשיר.
      Future<int> trackAndMark(
        String title,
        String content, {
        List<int> marked = const [],
      }) async {
        final provider = buildProvider(pageCount: 2);
        addTearDown(provider.dispose);
        await provider.loadAllData();
        await provider.addPdfBooks([
          PdfBook(title: title, path: pdfFile('$title.pdf', content)),
        ]);
        final key = persistedKeyOf(title);
        final progress = ShamorZachorProgressProvider();
        addTearDown(progress.dispose);
        await progress.ensureLoaded();
        final details = BookDetails(
          id: key,
          contentType: 'pdf',
          parts: const [BookPart(name: 'ראשי', startPage: 1, endPage: 2)],
        );
        for (final index in marked) {
          await progress.updateProgressById(key, index, 'learn', true, details);
        }
        return key;
      }

      Future<Map<String, PageProgress>> progressOf(int key) async {
        final progress = ShamorZachorProgressProvider();
        addTearDown(progress.dispose);
        await progress.ensureLoaded();
        return progress.getProgressForBookById(key);
      }

      test(
        'אותו PDF מקבל אותו מפתח בשני מכשירים, ו-PDF אחר — מפתח אחר',
        () async {
          final onA = await trackAndMark('ספר', 'תוכן א');
          await switchDevice();
          final sameOnB = await trackAndMark('שם אחר', 'תוכן א');
          await switchDevice();
          final otherOnC = await trackAndMark('ספר', 'תוכן ב');

          expect(sameOnB, onA);
          expect(otherOnC, isNot(onA));
        },
      );

      test(
        'ייבוא ממזג: סימון מגיבוי של מכשיר אחר לא נוחת על PDF מקומי אחר',
        () async {
          // מכשיר א: ספר X, עמוד 1 מסומן.
          await trackAndMark('ספר X', 'תוכן X', marked: [0]);
          final backupA = szData();

          // מכשיר ב: ספר Y, נוסף ראשון במכשיר — כמו X במכשיר א.
          await switchDevice();
          final keyY = await trackAndMark('ספר Y', 'תוכן Y');
          final merged = BackupImportMerge.mergeShamorZachor(szData(), backupA);
          for (final entry in merged.toWrite.entries) {
            await cache.setObject(entry.key, entry.value);
          }

          expect(
            await progressOf(keyY),
            isEmpty,
            reason: 'הסימון של ספר X נחת על ספר Y',
          );
          // הספר X מהגיבוי נשמר יחד עם הסימון שלו.
          expect(persistedPdfBooks().map((e) => e['title']), contains('ספר X'));
          final progressX = await progressOf(persistedKeyOf('ספר X'));
          expect(progressX['0']?.getProperty('learn'), isTrue);
        },
      );

      test(
        'ארכיון מתגלגל: התקדמות של PDF מגיבוי אחד לא נצמדת ל-PDF של אחר',
        () async {
          await trackAndMark('ספר X', 'תוכן X', marked: [0]);
          final older = {'shamorZachor': szData()};

          await switchDevice();
          await trackAndMark('ספר Y', 'תוכן Y');
          final newer = {'shamorZachor': szData()};

          final merged = BackupMerge.merge(
            older,
            newer,
            olderTimestamp: DateTime(2026, 1, 1),
            newerTimestamp: DateTime(2026, 2, 1),
            now: DateTime(2026, 2, 2),
          );
          // שחזור הארכיון במכשיר חדש.
          await switchDevice();
          for (final entry in (merged['shamorZachor'] as Map).entries) {
            await cache.setObject(entry.key as String, entry.value);
          }

          expect(
            await progressOf(persistedKeyOf('ספר Y')),
            isEmpty,
            reason: 'הסימון של ספר X נחת על ספר Y',
          );
          final progressX = await progressOf(persistedKeyOf('ספר X'));
          expect(progressX['0']?.getProperty('learn'), isTrue);
        },
      );

      test('גיבוי במפתחות מונה של גרסה קודמת: מפתח זר אינו נקלט במיזוג', () {
        final local = <String, Object?>{
          'sz:tracked_pdf_books': jsonEncode([
            {'key': -1, 'identity': '/b/y.pdf', 'title': 'Y', 'pages': 2},
          ]),
        };
        final incoming = <String, dynamic>{
          'sz:tracked_pdf_books': jsonEncode([
            {'key': -1, 'identity': '/a/x.pdf', 'title': 'X', 'pages': 2},
          ]),
          'sz:progress_by_id': jsonEncode({
            '-1': {
              '0': {'learn': true},
            },
          }),
          'sz:last_touched:-1': 0,
        };

        final imported = BackupImportMerge.mergeShamorZachor(local, incoming);
        expect(
          _progressKeys(imported.toWrite),
          isNot(contains('-1')),
        );
        expect(imported.toWrite.containsKey('sz:last_touched:-1'), isFalse);

        final archived =
            BackupMerge.merge(
                  {'shamorZachor': incoming},
                  {'shamorZachor': local},
                  olderTimestamp: DateTime(2026, 1, 1),
                  newerTimestamp: DateTime(2026, 2, 1),
                  now: DateTime(2026, 2, 2),
                )['shamorZachor']
                as Map;
        expect(
          _progressKeys(archived),
          isNot(contains('-1')),
        );
        expect(archived.containsKey('sz:last_touched:-1'), isFalse);
      });

      test(
        'הסבת מפתחות מונה ישנים לזהות: כל הנתונים עוברים, וריצה חוזרת לא משנה',
        () async {
          final path = pdfFile('ישן.pdf', 'תוכן ישן');
          await Settings.setValue<String>(
            'sz:tracked_pdf_books',
            jsonEncode([
              {
                'key': -1,
                'identity': path,
                'title': 'ספר ישן',
                'pages': 2,
                'outline': const [],
              },
              {
                'key': -2,
                'identity': '/missing.pdf',
                'title': 'חסר',
                'pages': 2,
                'outline': const [],
              },
            ]),
          );
          await Settings.setValue<String>(
            'sz:progress_by_id',
            jsonEncode({
              '-1': {
                '0': {'learn': true},
              },
            }),
          );
          await Settings.setValue<String>(
            'sz:completion_dates_by_id',
            jsonEncode({'-1': '2026-01-01'}),
          );
          await Settings.setValue<String>(
            'sz:book_columns',
            jsonEncode({
              '-1': [
                {'id': 'learn', 'label': 'עיון'},
              ],
            }),
          );
          await Settings.setValue<int>('sz:last_touched:-1', 1);

          final provider = buildProvider(pageCount: 2);
          addTearDown(provider.dispose);
          await provider.loadAllData();
          final progress = ShamorZachorProgressProvider();
          addTearDown(progress.dispose);
          await progress.ensureLoaded();
          final library = [PdfBook(title: 'ספר ישן', path: path)];

          expect(
            await provider.migrateLegacyPdfBooks(library, progress.rekeyBooks),
            1,
          );

          final key = PdfTrackingIdentity.keyOf(
            await PdfTrackingIdentity.of(library.single),
          );
          expect(persistedKeyOf('ספר ישן'), key);
          expect(
            persistedKeyOf('חסר'),
            -2,
            reason: 'קובץ שלא נמצא נשאר כמות שהוא',
          );
          expect(pdfBooks(provider)['ספר ישן']?.id, key);
          expect(progress.getProgressForBookById(-1), isEmpty);
          expect(
            progress.getProgressForBookById(key)['0']?.getProperty('learn'),
            isTrue,
          );
          expect(progress.getCompletionDateSyncById(key), '2026-01-01');
          expect(progress.getColumnsForBook(key).single.label, 'עיון');
          expect(progress.lastTouchedIndexById(key), 1);
          expect(progress.lastTouchedIndexById(-1), isNull);
          expect(
            await provider.findTrackedPdf(key, library),
            same(library.single),
          );

          final before = szData();
          expect(
            await provider.migrateLegacyPdfBooks(library, progress.rekeyBooks),
            0,
          );
          expect(szData(), before);
        },
      );

      test(
        'הסבה אינה מצמידה רשומה ישנה לקובץ שכותרתו או מספר עמודיו שונים',
        () async {
          final path = pdfFile('ישן.pdf', 'תוכן');
          await Settings.setValue<String>(
            'sz:tracked_pdf_books',
            jsonEncode([
              {
                'key': -1,
                'identity': path,
                'title': 'ספר ממכשיר אחר',
                'pages': 2,
                'outline': const [],
              },
            ]),
          );
          final provider = buildProvider(pageCount: 2);
          addTearDown(provider.dispose);
          await provider.loadAllData();

          expect(
            await provider.migrateLegacyPdfBooks([
              PdfBook(title: 'ספר מקומי', path: path),
            ], (_) async => fail('אין להעביר נתונים')),
            0,
          );
          expect(persistedKeyOf('ספר ממכשיר אחר'), -1);
        },
      );
    });
  });
}

/// מפתחות הספרים ב-`sz:progress_by_id` של תוצאת מיזוג.
Iterable<String> _progressKeys(Map<dynamic, dynamic> data) {
  final raw = data['sz:progress_by_id'];
  return raw is String ? (jsonDecode(raw) as Map).keys.cast<String>() : [];
}

Future<void> _setLibrarySettings(String libraryPath) async {
  await Settings.setValue<String>(
    SettingsRepository.keyLibraryPath,
    libraryPath,
  );
  await Settings.setValue<String>(SettingsRepository.keyLibraryFolderName, '');
  await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
}

Future<Map<String, int>> _insertFixture(SeforimRepository repository) async {
  final tanachCategoryId = await repository.insertCategory(
    const Category(title: 'תנ"ך'),
  );
  final chumashCategoryId = await repository.insertCategory(
    Category(title: 'חומש', parentId: tanachCategoryId, level: 1),
  );
  await repository.insertCategory(
    const Category(title: 'ספרים מספריות חיצוניות'),
  );

  final sourceId = await repository.insertSource('test-source', -1);

  final bereshitId = await repository.insertBook(
    migration.Book(
      id: 0,
      categoryId: chumashCategoryId,
      sourceId: sourceId,
      title: 'בראשית',
      totalLines: 3,
      isBaseBook: true,
      fileType: 'txt',
    ),
  );
  final personalId = await repository.insertBook(
    migration.Book(
      id: 0,
      categoryId: chumashCategoryId,
      sourceId: sourceId,
      title: 'ספר אישי',
      totalLines: 2,
      isBaseBook: false,
      fileType: 'txt',
    ),
  );
  final untrackedId = await repository.insertBook(
    migration.Book(
      id: 0,
      categoryId: chumashCategoryId,
      sourceId: sourceId,
      title: 'לא במעקב',
      totalLines: 2,
      isBaseBook: false,
      fileType: 'txt',
    ),
  );

  await repository.insertTocEntry(
    TocEntry(
      id: 1000,
      bookId: bereshitId,
      text: 'פרק א',
      level: 1,
      lineIndex: 0,
      isLastChild: true,
      hasChildren: false,
    ),
  );

  return {
    'בראשית': bereshitId,
    'ספר אישי': personalId,
    'לא במעקב': untrackedId,
  };
}
