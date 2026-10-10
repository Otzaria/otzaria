import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';

class MockDataRepository extends Mock implements DataRepository {}

typedef _Book = ({
  int id,
  String title,
  String? filePath,
  String fileType,
  double orderIndex,
  List<String> folderTitles,
});

_Book _book(int id, String title, {List<String> folders = const []}) => (
  id: id,
  title: title,
  filePath: null,
  fileType: 'txt',
  orderIndex: id.toDouble(),
  folderTitles: folders,
);

FindRefRepository _repo({
  required List<_Book> books,
  Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  })?
  userToc,
  Future<SeforimRepository> Function()? openUserBooksRepository,
}) => FindRefRepository(
  dataRepository: MockDataRepository(),
  isReferenceBooksCacheLoaded: () => true,
  warmUpReferenceBooksCache: () async {},
  searchReferenceBooks: (_, {limit = 50}) => const [],
  getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
  getAllUserBooks: openUserBooksRepository == null ? () async => books : null,
  getUserBookTocEntries: userToc,
  openUserBooksRepository: openUserBooksRepository,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('שמות הספרים האישיים מנורמלים פעם אחת בטעינה, לא בכל הקלדה', () async {
    final repo = _repo(
      books: [
        _book(1, 'ספר פלוני'),
        _book(2, 'חלק א', folders: const ['ספרים אישיים', 'שות פלוני']),
        _book(3, 'קונטרס'),
      ],
      userToc: (_, _, {queryTokens}) async => const [],
    );
    final before = FindRefRepository.debugSecondaryNameNormalizations;

    await repo.findRefs('ספר', includePersonalBooks: true);
    final afterLoad = FindRefRepository.debugSecondaryNameNormalizations;
    // כותרת לכל ספר + שם מורחב לכל סיומת של שרשרת התיקיות.
    expect(afterLoad - before, 3 + 2);

    for (final query in ['ספר פ', 'ספר פלוני', 'שות פלוני חלק', 'קונטרס ב']) {
      await repo.findRefs(query, includePersonalBooks: true);
    }
    expect(FindRefRepository.debugSecondaryNameNormalizations, afterLoad);
  });

  test('תוכן העניינים נבדק בכל הספרים האישיים שהשם שלהם תאם', () async {
    final books = [for (var i = 1; i <= 13; i++) _book(i, 'ספר פלוני')];
    final tocCalls = <int>[];
    final repo = _repo(
      books: books,
      userToc: (bookId, title, {queryTokens}) async {
        tocCalls.add(bookId);
        return [
          if (bookId == 13 && queryTokens!.join(' ') == 'פרק ב')
            {'reference': '$title פרק ב', 'segment': 88, 'level': 1},
        ];
      },
    );

    final results = await repo.findRefs(
      'ספר פלוני פרק ב',
      includePersonalBooks: true,
    );

    expect(tocCalls, [for (var i = 1; i <= 13; i++) i]);
    expect(
      results
          .where((r) => r.source == BookSource.user && r.bookId == 13)
          .map(
            (r) => (r.reference, r.segment),
          ),
      contains(('ספר פלוני פרק ב', 88)),
    );
  });

  test('כרך שהשם שלו כיסה יותר מהשאילתה נמצא בין עשרים כרכים', () async {
    const volumes = [
      'א',
      'ב',
      'ג',
      'ד',
      'ה',
      'ו',
      'ז',
      'ח',
      'ט',
      'י',
      'יא',
      'יב',
      'יג',
      'יד',
      'טו',
      'טז',
      'יז',
      'יח',
      'יט',
      'כ',
    ];
    final books = [
      for (var i = 0; i < volumes.length; i++)
        _book(i + 1, 'חלק ${volumes[i]}', folders: const ['שות פלוני']),
    ];
    final tocCalls = <int>[];
    final repo = _repo(
      books: books,
      userToc: (bookId, title, {queryTokens}) async {
        tocCalls.add(bookId);
        return [
          if (title == 'חלק טו' && queryTokens!.join(' ') == 'ג')
            {'reference': 'חלק טו, סימן ג', 'segment': 3, 'level': 2},
        ];
      },
    );

    final results = await repo.findRefs(
      'שות פלוני חלק טו ג',
      includePersonalBooks: true,
    );

    expect(tocCalls, contains(15));
    expect(results.map((r) => r.reference), contains('חלק טו, סימן ג'));
  });

  test(
    'מאות ספרים תואמים — חיפוש תוכן העניינים חסום כמו בקטלוג הרשמי',
    () async {
      var tocCalls = 0;
      final books = [for (var i = 1; i <= 300; i++) _book(i, 'שות מהדורה $i')];
      final repo = _repo(
        books: books,
        userToc: (_, _, {queryTokens}) async {
          tocCalls++;
          return const [];
        },
      );
      await repo.findRefs('שות סימן ג', includePersonalBooks: true);
      expect(tocCalls, FindRefRepository.maxSecondaryTocLookups);
    },
  );

  group('ספרים אישיים עוברים את מנוע ההתאמה של הקטלוג הרשמי', () {
    Future<List<DbReferenceResult>> personal(
      FindRefRepository repo,
      String query,
    ) async => [
      for (final r in await repo.findRefs(query, includePersonalBooks: true))
        if (r.source == BookSource.user) r,
    ];

    test('שאילתה שמופיעה באמצע השם מוצאת את הספר', () async {
      final repo = _repo(books: [_book(1, 'פירוש פלוני על בבא קמא')]);
      expect(
        (await personal(repo, 'בבא קמא')).map((r) => r.title),
        contains('פירוש פלוני על בבא קמא'),
      );
    });

    test('התאמה באמצע השם ממשיכה לתוכן העניינים עם טוקני הקטע', () async {
      List<String>? received;
      final repo = _repo(
        books: [_book(1, 'פירוש פלוני על בבא קמא')],
        userToc: (_, _, {queryTokens}) async {
          received = queryTokens;
          return [
            {
              'reference': 'פירוש פלוני על בבא קמא, ג',
              'segment': 7,
              'level': 2,
            },
          ];
        },
      );
      final results = await personal(repo, 'בבא קמא ג');
      expect(received, ['ג']);
      expect(
        results.map((r) => r.reference),
        contains('פירוש פלוני על בבא קמא, ג'),
      );
    });

    test('שגיאת כתיב בשם — התאמה מקורבת', () async {
      // וו/יי כפולות הן התאמה מילולית; "מיצ" מול "מצ" נשאר מקורב.
      final repo = _repo(books: [_book(1, 'ספר המיצות הגדול')]);
      expect(
        (await personal(repo, 'ספר המצות')).map((r) => r.title),
        contains('ספר המיצות הגדול'),
      );
    });

    test('התאמה מקורבת של ספר אישי יורדת מתחת להתאמה מילולית', () async {
      final repo = _repo(
        books: [_book(1, 'המיצות הגדולות'), _book(2, 'קונטרס המצות גדול')],
      );
      // בלי סימון ההתאמה המקורבת, orderIndex הנמוך של 1 היה מקדים אותו.
      expect((await personal(repo, 'המצות גדול')).map((r) => r.bookId), [
        2,
        1,
      ]);
    });

    test('מילת תיקייה נדרשת במלואה: "רא"ש" אינו תחילית של "ראשונים"', () async {
      final repo = _repo(
        books: [
          _book(1, 'הלכות ברכות להריטבא', folders: const ['הלכה', 'ראשונים']),
        ],
      );
      expect(await personal(repo, 'רא"ש ברכות'), isEmpty);
      // מילה אחרונה עשויה להיות באמצע הקלדה, אבל ראשי-תיבות בגרשיים הם מילה שלמה
      expect(await personal(repo, 'רא"ש'), isEmpty);
      expect(
        (await personal(repo, 'ראשונים הלכות ברכות')).map((r) => r.title),
        contains('הלכות ברכות להריטבא'),
      );
    });

    test('ספר רשמי קודם לספר אישי כשהרלוונטיות שווה', () async {
      final repo = FindRefRepository(
        dataRepository: MockDataRepository(),
        isReferenceBooksCacheLoaded: () => true,
        warmUpReferenceBooksCache: () async {},
        searchReferenceBooks: (query, {limit = 50}) => [
          if (query == 'ספר פלוני')
            ReferenceBookHit(
              bookId: 900,
              title: 'ספר פלוני',
              normalizedTitle: 'ספר פלוני',
              filePath: '',
              fileType: 'txt',
              matchRank: 0,
              orderIndex: 50,
            ),
        ],
        getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
        getAllUserBooks: () async => [_book(1, 'ספר פלוני')],
        getUserBookTocEntries: (_, _, {queryTokens}) async => const [],
      );
      final results = await repo.findRefs(
        'ספר פלוני',
        includePersonalBooks: true,
      );
      expect(results.map((r) => r.source), [
        BookSource.official,
        BookSource.user,
      ]);
    });

    test('ספרייה אישית גדולה נבנית ב-isolate עם אותן תוצאות', () async {
      final previous = FindRefRepository.secondaryIndexIsolateThreshold;
      addTearDown(
        () => FindRefRepository.secondaryIndexIsolateThreshold = previous,
      );
      FindRefRepository.secondaryIndexIsolateThreshold = 0;
      final repo = _repo(books: [_book(1, 'פירוש פלוני על בבא קמא')]);
      expect(
        (await personal(repo, 'בבא קמא')).map((r) => r.bookId),
        contains(1),
      );
    });
  });

  group('תוכן עניינים של ספר אישי ב-worker', () {
    late Directory tempDir;
    late String dbPath;
    late MyDatabase userDb;

    void addHeading(int id, String text) {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        db.execute('INSERT INTO tocText (id, text) VALUES (?, ?)', [id, text]);
        db.execute(
          'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) '
          'VALUES (?, ?, NULL, ?, 1, 2)',
          [id, SeforimFixtureIds.bereshitId, id],
        );
      } finally {
        db.close();
      }
    }

    setUp(() async {
      await QueryLoader.initialize();
      tempDir = await Directory.systemTemp.createTemp('otzaria_findref_user');
      dbPath = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
      addHeading(901, 'ג');
      userDb = MyDatabase.withPath(dbPath);
    });

    tearDown(() async {
      AttachedFindRefWorker.instance.reset();
      userDb.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    Future<List<String>> userRefs(
      FindRefRepository repo,
      String query,
    ) async => [
      for (final r in await repo.findRefs(query, includePersonalBooks: true))
        if (r.source == BookSource.user) r.reference,
    ];

    test('כותרת שנוספה למסד אחרי הטעינה נמצאת', () async {
      final userRepo = SeforimRepository(userDb);
      final repo = _repo(
        books: const [],
        openUserBooksRepository: () async => userRepo,
      );
      const title = SeforimFixtureIds.bereshitTitle;

      expect(await userRefs(repo, '$title ג'), contains('$title ג'));

      // חיבור אחר כותב — קאש ה-TOC של ה-worker חייב להתבטל.
      addHeading(902, 'ד');
      expect(await userRefs(repo, '$title ד'), contains('$title ד'));
    });

    for (final count in [13, 200]) {
      test('$count ספרים באותו שם — הכותרת שבספר האחרון נמצאת', () async {
        // כל הספרים באצווה אחת ל-worker, גם מעבר לתקרה הרגילה.
        final previousCap = FindRefRepository.maxSecondaryTocLookups;
        addTearDown(
          () => FindRefRepository.maxSecondaryTocLookups = previousCap,
        );
        FindRefRepository.maxSecondaryTocLookups = count;
        final lastId = 10 + count;
        final db = sqlite3.sqlite3.open(dbPath);
        try {
          for (var id = 11; id <= lastId; id++) {
            db.execute(
              'INSERT INTO book (id, categoryId, sourceId, title, orderIndex) '
              "VALUES (?, 2, 1, 'ספר פלוני', ?)",
              [id, id],
            );
          }
          db.execute(
            'INSERT INTO line (id, bookId, lineIndex, content) '
            "VALUES (500, ?, 88, 'שורה')",
            [lastId],
          );
          db.execute("INSERT INTO tocText (id, text) VALUES (950, 'פרק ב')");
          db.execute(
            'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) '
            'VALUES (950, ?, NULL, 950, 1, 500)',
            [lastId],
          );
        } finally {
          db.close();
        }
        final userRepo = SeforimRepository(userDb);
        final repo = _repo(
          books: const [],
          openUserBooksRepository: () async => userRepo,
        );

        final results = await repo.findRefs(
          'ספר פלוני פרק ב',
          includePersonalBooks: true,
        );

        expect(
          results
              .where((r) => r.source == BookSource.user && r.bookId == lastId)
              .map((r) => r.segment),
          contains(88),
        );
      });
    }

    void execute(String sql, [List<Object?> args = const []]) {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        db.execute(sql, args);
      } finally {
        db.close();
      }
    }

    test('ספר מתיקייה אישית: הכותרת נפתחת בשורה שלה (#1902)', () async {
      // ספר שתוכנו בקובץ: אין שורות במסד, והמיקום נשמר ב-tocEntry.lineIndex.
      execute('ALTER TABLE tocEntry ADD COLUMN lineIndex INTEGER');
      execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex) '
        'VALUES (60, ?, 1, ?, 3)',
        [SeforimFixtureIds.torahCategoryId, 'קונטרס חיצוני'],
      );
      execute("INSERT INTO tocText (id, text) VALUES (960, 'פרק ג')");
      execute(
        'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId, '
        'lineIndex) VALUES (960, 60, NULL, 960, 1, NULL, 42)',
      );
      final repo = _repo(
        books: const [],
        openUserBooksRepository: () async => SeforimRepository(userDb),
      );

      final results = await repo.findRefs(
        'קונטרס חיצוני פרק ג',
        includePersonalBooks: true,
      );

      expect(
        results
            .where((r) => r.source == BookSource.user && r.bookId == 60)
            .map((r) => (r.reference, r.segment)),
        contains(('קונטרס חיצוני פרק ג', 42)),
      );
    });

    test('ספר שנוסף למסד אחרי החיפוש הראשון נמצא', () async {
      final repo = _repo(
        books: const [],
        openUserBooksRepository: () async => SeforimRepository(userDb),
      );
      expect(await userRefs(repo, 'קונטרס חדש'), isEmpty);

      execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex) '
        'VALUES (50, ?, 1, ?, 3)',
        [SeforimFixtureIds.torahCategoryId, 'קונטרס חדש'],
      );
      // כתיבה מתוך האפליקציה: רענון הספרייה מפעיל את הבדיקה ברקע.
      FindRefRepository.revalidateUserBooks();
      await repo.debugUserBooksRefresh;
      expect(await userRefs(repo, 'קונטרס חדש'), contains('קונטרס חדש'));
    });

    test('ספר שנמחק מהמסד אינו מוצע עוד', () async {
      final repo = _repo(
        books: const [],
        openUserBooksRepository: () async => SeforimRepository(userDb),
      );
      const title = SeforimFixtureIds.rashiTitle;
      expect(await userRefs(repo, title), contains(title));

      execute('DELETE FROM book WHERE id = ?', [SeforimFixtureIds.rashiId]);
      // כתיבה של חיבור אחר: החיפוש הראשון מחזיר מהקאש ובודק ברקע.
      await userRefs(repo, title);
      await repo.debugUserBooksRefresh;
      expect(await userRefs(repo, title), isNot(contains(title)));
    });

    test('שינוי בזמן שמסד הספרים האישיים סגור נראה בחיפוש הבא', () async {
      final repo = _repo(
        books: const [],
        openUserBooksRepository: () async => SeforimRepository(userDb),
      );
      const title = SeforimFixtureIds.rashiTitle;
      expect(await userRefs(repo, title), contains(title));

      await UserBooksDatabaseHolder.instance.close();
      execute('DELETE FROM book WHERE id = ?', [SeforimFixtureIds.rashiId]);
      expect(await userRefs(repo, title), isNot(contains(title)));
    });

    test('כשיש אינדקס, החיפוש אינו ממתין ל-worker עסוק', () async {
      final repo = _repo(
        books: const [],
        openUserBooksRepository: () async => SeforimRepository(userDb),
      );
      const title = SeforimFixtureIds.rashiTitle;
      expect(await userRefs(repo, title), contains(title));

      final busy = AttachedFindRefWorker.instance.run(
        dbPath,
        immutable: false,
        version: '0',
        job: _slowJob,
      );
      final stopwatch = Stopwatch()..start();
      expect(await userRefs(repo, title), contains(title));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      await busy;
    });

    test('חיבור חדש לאותו תוכן אינו בונה את האינדקס מחדש', () async {
      final repo = _repo(
        books: const [],
        openUserBooksRepository: () async => SeforimRepository(userDb),
      );
      const title = SeforimFixtureIds.rashiTitle;
      await userRefs(repo, title);
      final index = repo.debugUserBooksIndex;
      expect(index, isNotNull);

      // כמו idleClose: ה-worker פותח חיבור חדש, data_version מתחיל מחדש.
      AttachedFindRefWorker.instance.reset();
      await userRefs(repo, title);
      await repo.debugUserBooksRefresh;
      expect(identical(repo.debugUserBooksIndex, index), isTrue);
    });
  });

  test('אינדקס שנבנה בזמן שהחיפוש בוטל נשמר לחיפוש הבא', () async {
    final gate = Completer<void>();
    var loads = 0;
    final repo = FindRefRepository(
      dataRepository: MockDataRepository(),
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      searchReferenceBooks: (_, {limit = 50}) => const [],
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllUserBooks: () async {
        loads++;
        await gate.future;
        return [_book(1, 'ספר פלוני')];
      },
      getUserBookTocEntries: (_, _, {queryTokens}) async => const [],
    );
    final first = repo.findRefs('ספר', includePersonalBooks: true);
    await pumpEventQueue();
    repo.cancelPendingSearch();
    gate.complete();
    await expectLater(first, throwsA(isA<FindRefQueryCancelled>()));

    final results = await repo.findRefs('ספר', includePersonalBooks: true);
    expect(loads, 1);
    expect(results.map((r) => r.source), contains(BookSource.user));
  });
}

Future<int> _slowJob(SeforimRepository repository) async {
  await Future<void>.delayed(const Duration(milliseconds: 2000));
  return 1;
}
