import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
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
  });
}
