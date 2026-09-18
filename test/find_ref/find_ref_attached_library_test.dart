import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/utils/text/ref_key.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';

class MockDataRepository extends Mock implements DataRepository {}

const _slug = 'lib-a';
final _source = BookSource.attached(_slug);
const _bookId = SeforimFixtureIds.bereshitId;
const _title = SeforimFixtureIds.bereshitTitle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AttachedLibraryRegistry previousRegistry;
  late AttachedLibraryRegistry registry;

  /// מסד מצורף עם שורה 5 שה-heRef שלה מסתיים ב-"א ב", כותרת תוכן 'ג' על
  /// שורה 6, וכינוי 'זזז' לספר. [withLineRef] = false מסיר את האינדקס.
  String createDb({required bool withLineRef}) {
    final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
    final db = sqlite3.sqlite3.open(path);
    db.execute(
      'INSERT INTO line (id, bookId, lineIndex, content, heRef) VALUES '
      "(901, ?, 5, 'x', ?), (902, ?, 6, 'y', ?)",
      [_bookId, '$_title א ב', _bookId, '$_title ג'],
    );
    db.execute("INSERT INTO tocText (id, text) VALUES (901, 'ג')");
    db.execute(
      'INSERT INTO tocEntry (id, bookId, parentId, textId, level, lineId) '
      'VALUES (901, ?, NULL, 901, 1, 902)',
      [_bookId],
    );
    db.execute("INSERT INTO book_acronym (bookId, term) VALUES (?, 'זזז')", [
      _bookId,
    ]);
    if (withLineRef) {
      db.execute('INSERT INTO line_ref VALUES (?, ?, 5)', [
        _bookId,
        refKeyHash(buildRefKey('א ב')!),
      ]);
    } else {
      db.execute('DROP TABLE line_ref');
    }
    db.close();
    return path;
  }

  Future<void> attach(String path) async {
    registry.update([
      AttachedLibrary(
        slug: _slug,
        displayName: 'Lib A',
        path: path,
        addedAt: DateTime(2026),
      ),
    ]);
  }

  FindRefRepository buildRepo({List<ReferenceBookHit> official = const []}) =>
      FindRefRepository(
        dataRepository: MockDataRepository(),
        isReferenceBooksCacheLoaded: () => true,
        warmUpReferenceBooksCache: () async {},
        searchReferenceBooks: (query, {int limit = 50}) => official,
        getTocEntriesForReference: (id, title, {queryTokens}) async => const [],
        getAllUserBooks: () async => const [],
      );

  List<DbReferenceResult> attachedOnly(List<DbReferenceResult> results) => [
    for (final r in results)
      if (r.source == _source) r,
  ];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_findref_attached');
    previousRegistry = AttachedLibraryRegistry.instance;
    registry = AttachedLibraryRegistry(idleTimeout: null);
    AttachedLibraryRegistry.instance = registry;
    AcronymsCache.instance.clear();
  });

  tearDown(() async {
    await registry.closeAll();
    AttachedLibraryRegistry.instance = previousRegistry;
    AcronymsCache.instance.clear();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('ספר ממסד מצורף נמצא לפי כותרת, עם המקור שלו', () async {
    await attach(createDb(withLineRef: true));
    final results = attachedOnly(
      await buildRepo().findRefs(_title, includePersonalBooks: true),
    );
    expect(results, hasLength(1));
    expect(results.single.bookId, _bookId);
    expect(results.single.bookPath, isNotEmpty);
  });

  test('מסד מצורף אינו נחקר כשספרים אישיים אינם כלולים', () async {
    await attach(createDb(withLineRef: true));
    final results = await buildRepo().findRefs(_title);
    expect(attachedOnly(results), isEmpty);
  });

  test('הפניה נפתרת לשורה מדויקת דרך line_ref של המסד', () async {
    await attach(createDb(withLineRef: true));
    final results = attachedOnly(
      await buildRepo().findRefs('$_title א ב', includePersonalBooks: true),
    );
    final exact = results.where((r) => r.isSourceLine).toList();
    expect(exact, hasLength(1));
    expect(exact.single.segment, 5);
    expect(exact.single.sourceLineId, 901);
  });

  test('בלי line_ref — אין שורה מדויקת, ותוכן העניינים עדיין נמצא', () async {
    await attach(createDb(withLineRef: false));
    final repo = buildRepo();
    final byRef = attachedOnly(
      await repo.findRefs('$_title א ב', includePersonalBooks: true),
    );
    expect(byRef.where((r) => r.isSourceLine), isEmpty);

    final byToc = attachedOnly(
      await repo.findRefs('$_title ג', includePersonalBooks: true),
    );
    expect(byToc.map((r) => r.sourceLineId), contains(902));
  });

  test('כינוי מ-book_acronym של המסד', () async {
    await attach(createDb(withLineRef: true));
    final results = attachedOnly(
      await buildRepo().findRefs('זזז', includePersonalBooks: true),
    );
    expect(results.map((r) => r.bookId), [_bookId]);
    expect(AcronymsCache.instance.acronymsFor(_source, _bookId), isNotEmpty);
    expect(
      AcronymsCache.instance.acronymsFor(BookSource.official, _bookId),
      isNull,
    );
  });

  test('ספר רשמי וספר מצורף באותו id וכותרת אינם מתאחדים', () async {
    await attach(createDb(withLineRef: true));
    final results = await buildRepo(
      official: [
        ReferenceBookHit(
          bookId: _bookId,
          title: _title,
          normalizedTitle: _title,
          filePath: '',
          fileType: 'txt',
          matchRank: 1,
          orderIndex: 1,
        ),
      ],
    ).findRefs(_title, includePersonalBooks: true);
    final sources = results
        .where((r) => r.bookId == _bookId && r.title == _title)
        .map((r) => r.source)
        .toSet();
    expect(sources, {BookSource.official, _source});
  });

  test('מסד שנותק — אין ממנו תוצאות', () async {
    final path = createDb(withLineRef: true);
    await attach(path);
    final repo = buildRepo();
    expect(
      attachedOnly(await repo.findRefs(_title, includePersonalBooks: true)),
      isNotEmpty,
    );
    registry.update([]);
    expect(
      attachedOnly(await repo.findRefs(_title, includePersonalBooks: true)),
      isEmpty,
    );
  });

  test('החיפוש רץ ב-worker — בלי חיבור למסד ב-main isolate', () async {
    await attach(createDb(withLineRef: true));
    final results = attachedOnly(
      await buildRepo().findRefs('$_title ג', includePersonalBooks: true),
    );
    expect(results.map((r) => r.sourceLineId), contains(902));
    expect(registry.isOpen(_slug), isFalse);
  });

  test('תקרת ספרים לשלב תוכן העניינים', () async {
    final previous = FindRefRepository.maxAttachedTocBooks;
    addTearDown(() => FindRefRepository.maxAttachedTocBooks = previous);
    FindRefRepository.maxAttachedTocBooks = 0;
    await attach(createDb(withLineRef: false));
    final results = attachedOnly(
      await buildRepo().findRefs('$_title ג', includePersonalBooks: true),
    );
    expect(results.map((r) => r.sourceLineId), isNot(contains(902)));
    expect(results.map((r) => r.bookId), contains(_bookId));
  });

  group('AttachedFindRefWorker', () {
    test('עבודה תקועה — timeout, והמסד מושבת זמנית בלי להמתין שוב', () async {
      final path = createDb(withLineRef: false);
      final previous = AttachedFindRefWorker.callTimeout;
      addTearDown(() {
        AttachedFindRefWorker.callTimeout = previous;
        AttachedFindRefWorker.instance.reset();
      });
      AttachedFindRefWorker.callTimeout = const Duration(milliseconds: 300);
      final worker = AttachedFindRefWorker.instance;

      await expectLater(
        worker.run(path, immutable: false, version: '', job: _hangingJob),
        throwsA(isA<TimeoutException>()),
      );
      final stopwatch = Stopwatch()..start();
      await expectLater(
        worker.run(path, immutable: false, version: '', job: _countBooksJob),
        throwsA(isA<StateError>()),
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(200));

      worker.reset();
      expect(
        await worker.run(
          path,
          immutable: false,
          version: '',
          job: _countBooksJob,
        ),
        greaterThan(0),
      );
    });
  });
}

Future<int> _hangingJob(SeforimRepository repository) =>
    Completer<int>().future;

Future<int> _countBooksJob(SeforimRepository repository) async =>
    (await repository.database.bookDao.getAllLocalBooks()).length;
