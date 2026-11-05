import 'package:otzaria/data/book_identity.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/models/index_check_scope.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/utils/pending_reindex_store.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/utils/refresh_indexing_plan.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';

class _Files extends Fake implements FileSystemData {
  _Files(this.next);

  final Library next;

  @override
  String libraryPath = '.';

  @override
  Future<Library> getLibrary() async => next;
}

class _ReadyIndex extends Fake implements TantivyDataProvider {
  @override
  Future<bool> reopenIndex({bool force = false}) async => true;
}

class _EmptyHiddenStore extends HiddenLibraryStore {
  const _EmptyHiddenStore();

  @override
  HiddenLibrarySelection load() => const HiddenLibrarySelection();
}

/// בונה ספרייה שבה כל ספר יושב בשרשרת הקטגוריות שלו.
Library _libraryOf(Map<List<String>, List<Book Function(Category)>> tree) {
  final library = Library(categories: []);
  for (final entry in tree.entries) {
    Category parent = library;
    for (final title in entry.key) {
      final child = Category(
        title: title,
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: parent,
      );
      parent.subCategories.add(child);
      parent = child;
    }
    for (final build in entry.value) {
      parent.books.add(build(parent));
    }
  }
  return library;
}

const _userBookTitle = 'אנציקלופדיה תלמודית אות מ';
const _emptyTitle = 'ספר ריק';

TextBook _userBook(Category category) => TextBook(
  id: 5,
  title: 'אנציקלופדיה תלמודית אות מ',
  source: BookSource.user,
  category: category,
);

TextBook _officialBook(Category category) =>
    TextBook(id: 9, title: 'משנה ברורה', category: category);

Future<void> main() async {
  final nativeAvailable = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileSystemData previousFiles;
  late TantivyDataProvider previousIndex;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    previousFiles = FileSystemData.instance;
    previousIndex = TantivyDataProvider.instance;
    TantivyDataProvider.instance = _ReadyIndex();
  });

  tearDown(() {
    FileSystemData.instance = previousFiles;
    TantivyDataProvider.instance = previousIndex;
  });

  Future<LibraryState> refreshStateBetween(
    Library before,
    Library after, {
    Set<String> changedBookKeys = const {},
    Set<String> changedAttachedSlugs = const {},
  }) async {
    final files = _Files(after);
    FileSystemData.instance = files;
    final repository = DataRepository(fileSystemData: files);
    repository.library = Future.value(before);
    await repository.library;
    final bloc = LibraryBloc(
      hiddenStore: const _EmptyHiddenStore(),
      repository: repository,
    );
    addTearDown(bloc.close);
    final done = bloc.stream.firstWhere(
      (state) => state.completedRefreshRequestIds?.contains(1) ?? false,
    );
    bloc.add(
      RefreshLibrary(
        requestIds: const {1},
        changedBookKeys: changedBookKeys,
        changedAttachedSlugs: changedAttachedSlugs,
      ),
    );
    return done;
  }

  Future<List<Book>?> refreshBetween(Library before, Library after) async =>
      (await refreshStateBetween(before, after)).booksToCheckForIndex;

  RunIndexing planFor(LibraryState state) =>
      buildRefreshIndexingPlan(
            library: state.library!,
            newBooks: state.newBooksToIndex ?? const [],
            changedBooks: state.changedBooksToIndex ?? const [],
            checkBooks: state.booksToCheckForIndex ?? const [],
            indexWholeLibrary: false,
            reconcile: false,
            indexUpdateMode: IndexUpdateMode.all,
          ).single
          as RunIndexing;

  group('ביטול מיזוג אישי (issue #3603)', () {
    late _PersistentIndex index;
    late Library before;
    late Library merged;

    setUp(() async {
      index = await _PersistentIndex.open();
      addTearDown(index.close);
      TextBook secondUserBook(Category category) => TextBook(
        id: 6,
        title: 'ספר אישי שני',
        source: BookSource.user,
        category: category,
      );
      before = _libraryOf({
        ['ספרים אישיים']: [_userBook, secondUserBook],
      });
      merged = _libraryOf({
        ['מדרש']: [_userBook, secondUserBook],
      });
      await index.repository.runIndexing(before, onProgress: (_, _) {});
    });

    test(
      'ביטול לפני כתיבה וחזרה למטא־דאטה המקורית שורדים הפעלה מחדש',
      () async {
        final plan = planFor(await refreshStateBetween(before, merged));
        final cancelled = await index.repository.runIndexing(
          merged,
          books: plan.books,
          changedBooks: plan.changedBooks,
          check: plan.check,
          onWorkListReady: (_) => index.repository.cancelIndexing(),
          onProgress: (_, _) {},
        );
        expect(cancelled.cancelled, isTrue);
        expect(cancelled.indexedBooks, 0);

        await index.restart();
        final resumed = await index.repository.runIndexing(
          before,
          onProgress: (_, _) {},
        );

        expect(resumed.isClean, isTrue);
        expect(resumed.indexedBooks, 0);
        expect(await index.repository.hasUnindexedBooks(before), isFalse);
        expect((await index.pending.read()).isEmpty, isTrue);
      },
    );

    test(
      'אחרי כתיבה חלקית רק הספר שנחתם במיזוג מוחזר לקטגוריה המקורית',
      () async {
        var loaded = 0;
        index.repository.onLoad = (_) => loaded++;
        final cancelled = await index.repository.runIndexing(
          merged,
          books: const [],
          check: IndexCheckScope.books(merged.getIndexableBooks()),
          onProgress: (processed, _) {
            if (processed == 1 && loaded == 1) {
              index.repository.cancelIndexing();
            }
          },
        );
        expect(cancelled.cancelled, isTrue);
        expect(cancelled.indexedBooks, 1);
        expect(await index.pathsIn('/מדרש'), ['uid:5']);

        await index.restart();
        final plan = planFor(await refreshStateBetween(merged, before));
        final restored = await index.repository.runIndexing(
          before,
          books: plan.books,
          changedBooks: plan.changedBooks,
          check: plan.check,
          onProgress: (_, _) {},
        );

        expect(restored.isClean, isTrue);
        expect(restored.indexedBooks, 1);
        expect(await index.pathsIn('/מדרש'), isEmpty);
        expect(await index.pathsIn('/ספרים אישיים'), ['uid:5', 'uid:6']);
        expect((await index.pending.read()).isEmpty, isTrue);
      },
    );

    test(
      'ביטול מיזוג כשהאינדוקס האוטומטי כבוי אינו מכריח כתיבה בהמשך',
      () async {
        final state = await refreshStateBetween(before, merged);
        final deferred =
            buildRefreshIndexingPlan(
                  library: merged,
                  newBooks: state.newBooksToIndex ?? const [],
                  changedBooks: state.changedBooksToIndex ?? const [],
                  checkBooks: state.booksToCheckForIndex ?? const [],
                  indexWholeLibrary: false,
                  reconcile: false,
                  indexUpdateMode: IndexUpdateMode.off,
                ).single
                as DeferIndexing;
        await index.repository.rememberChangedBooks(
          deferred.changedBooks,
          checkBooks: deferred.checkBooks,
          checkLibrary: deferred.checkLibrary,
        );

        await index.restart();
        final resumed = await index.repository.runIndexing(
          before,
          onProgress: (_, _) {},
        );

        expect(resumed.isClean, isTrue);
        expect(resumed.indexedBooks, 0);
        expect(await index.repository.hasUnindexedBooks(before), isFalse);
        expect((await index.pending.read()).isEmpty, isTrue);
      },
    );

    test('שינוי תוכן מפורש נשמר גם כשהקטגוריה חזרה לחותם המקורי', () async {
      final changed = merged.getIndexableBooks().first;
      index.texts[changed.title] = 'תוכן חדש';
      final cancelled = await index.repository.runIndexing(
        merged,
        books: const [],
        changedBooks: [changed],
        check: IndexCheckScope.books(merged.getIndexableBooks()),
        onWorkListReady: (_) => index.repository.cancelIndexing(),
        onProgress: (_, _) {},
      );
      expect(cancelled.cancelled, isTrue);

      await index.restart();
      final restored = await index.repository.runIndexing(
        before,
        books: const [],
        check: IndexCheckScope.books(before.getIndexableBooks()),
        onProgress: (_, _) {},
      );

      expect(restored.indexedBooks, 1);
      expect(await index.pathsIn('/ספרים אישיים', query: 'תוכן חדש'), [
        'uid:5',
      ]);
      expect((await index.pending.read()).isEmpty, isTrue);
    });

    test(
      'בדיקות שנדחו בתור אינן מבטלות שינוי תוכן שנוסף לפניהן או אחריהן',
      () async {
        final books = merged.getIndexableBooks();
        index.texts[books.first.title] = 'תוכן חדש';
        await index.repository.rememberChangedBooks(
          const [],
          checkBooks: books,
        );
        await index.repository.rememberChangedBooks([books.first]);
        await index.repository.rememberChangedBooks(
          const [],
          checkBooks: books,
        );

        await index.restart();
        final resumed = await index.repository.runIndexing(
          before,
          onProgress: (_, _) {},
        );

        expect(resumed.indexedBooks, 1);
        expect(await index.pathsIn('/ספרים אישיים', query: 'תוכן חדש'), [
          'uid:5',
        ]);
        expect((await index.pending.read()).isEmpty, isTrue);
      },
    );

    test('סימון החלפה ישן גובר גם על בדיקה חופפת שנשמרה בקובץ', () async {
      index.texts[_userBookTitle] = 'תוכן חדש';
      await index.pending.save({'uid:5'}, checkKeys: {'uid:5', 'uid:6'});

      await index.restart();
      final resumed = await index.repository.runIndexing(
        before,
        onProgress: (_, _) {},
      );

      expect(resumed.indexedBooks, 1);
      expect(await index.pathsIn('/ספרים אישיים', query: 'תוכן חדש'), [
        'uid:5',
      ]);
      expect((await index.pending.read()).isEmpty, isTrue);
    });

    test(
      'ספר שנמחק לפני כשל כתיבה משוחזר גם בריצה חלקית אחרי הפעלה מחדש',
      () async {
        index.repository.onLoad = (_) => throw StateError('קריאה נכשלה');
        final failed = await index.repository.runIndexing(
          merged,
          books: const [],
          check: IndexCheckScope.books([merged.getIndexableBooks().first]),
          onProgress: (_, _) {},
        );
        expect(failed.failures.single.isRetryable, isTrue);
        expect(await index.pathsIn('/ספרים אישיים'), ['uid:6']);

        await index.restart();
        final resumed = await index.repository.runIndexing(
          before,
          books: const [],
          check: IndexCheckScope.books([before.getIndexableBooks().last]),
          onProgress: (_, _) {},
        );

        expect(resumed.isClean, isTrue);
        expect(resumed.indexedBooks, 1);
        expect(await index.pathsIn('/ספרים אישיים'), ['uid:5', 'uid:6']);
        expect((await index.pending.read()).isEmpty, isTrue);
      },
    );
  }, skip: nativeAvailable ? false : searchEngineSkipReason);

  group('רענון שמעביר ספר לקטגוריה אחרת (issue #1977)', () {
    test('שינוי תוכן גובר על הזזת קטגוריה, גם ב־PDF ממסד מצורף', () async {
      PdfBook movedPdf(Category category) => PdfBook(
        id: 3,
        title: 'סרוק אישי',
        path: '/tmp/personal.pdf',
        source: BookSource.user,
        category: category,
      );
      PdfBook changedPdf(Category category) => PdfBook(
        id: 4,
        title: 'סרוק מצורף',
        path: '/tmp/attached.pdf',
        source: BookSource.attached('reference'),
        category: category,
      );
      Library library(String category) => _libraryOf({
        [category]: [_userBook, movedPdf, changedPdf],
      });
      final state = await refreshStateBetween(
        library('ספרים אישיים'),
        library('מדרש'),
        changedBookKeys: {'uid:5'},
        changedAttachedSlugs: {'reference'},
      );

      final plan = planFor(state);

      expect(state.changedBooksToIndex, hasLength(2));
      expect(plan.changedBooks.map(BookIdentity.keyOf), [
        'uid:5',
        'db:reference:4',
      ]);
      expect(plan.check.books.map(BookIdentity.keyOf), ['uid:3']);
      expect(state.copyWith().booksToCheckForIndex, isNull);
    });

    test(
      'מיזוג ספרים אישיים לעץ — הספר שעבר מאונדקס מחדש (issue #1977)',
      () async {
        final before = _libraryOf({
          ['ספרים אישיים', 'ספריה', 'מילונים וספרי יעץ', 'אנציקלופדיות']: [
            _userBook,
          ],
          ['הלכה']: [_officialBook],
        });
        final after = _libraryOf({
          ['מילונים וספרי יעץ', 'אנציקלופדיות']: [_userBook],
          ['הלכה']: [_officialBook],
        });

        final changed = await refreshBetween(before, after);

        expect(changed?.map((b) => b.title), ['אנציקלופדיה תלמודית אות מ']);
        expect(
          changed!.single.category!.path,
          '/מילונים וספרי יעץ/אנציקלופדיות',
        );
      },
    );

    test(
      'מיזוג אישי: רק הספר שעבר מאונדקס, הסדר מהמיפוי והמזהים יציבים',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'moved_book_index_',
        );
        final engine = await SearchEngine.newInstance(path: directory.path);
        final provider = _NativeIndex(engine)..activeIndexPath = directory.path;
        addTearDown(() async {
          provider.isIndexing.dispose();
          engine.dispose();
          await directory.delete(recursive: true);
        });
        final indexer = _MemoryTextRepository(provider);
        TextBook earlyBook(Category category) =>
            TextBook(id: 1, title: 'ספר מוקדם', category: category);
        TextBook attachedBook(Category category) => TextBook(
          id: 5,
          title: 'ספר מצורף',
          category: category,
          source: BookSource.attached('reference'),
        );
        final before = _libraryOf({
          ['תנ"ך']: [earlyBook],
          ['הלכה']: [_officialBook],
          ['ספרים אישיים']: [_userBook],
          ['מצורף']: [attachedBook],
        });
        final after = _libraryOf({
          ['תנ"ך']: [earlyBook],
          ['מדרש']: [_userBook],
          ['הלכה']: [_officialBook],
          ['מצורף']: [attachedBook],
        });
        Future<List<SearchResult>> search(
          String query, [
          List<String> facets = const [],
        ]) => engine.searchExact(
          query: query,
          facets: facets,
          limit: 10,
          offset: 0,
          order: ResultsOrder.catalogue,
          matchNikud: false,
          matchTaamim: false,
        );

        final initial = await indexer.runIndexing(
          before,
          books: before.getIndexableBooks(),
          onProgress: (_, _) {},
        );
        expect(initial.isClean, isTrue);
        final originalIds = {
          for (final hit in await search('שלום')) hit.filePath: hit.id,
        };
        // ספרים אישיים אחרי הספרייה והמסדים המצורפים, כפי שהיו.
        expect(
          originalIds.keys,
          ['id:1', 'id:9', 'db:reference:5', 'uid:5'],
          reason: 'סדר הקטלוג של העץ הקודם',
        );
        expect(await search('שלום', ['/מדרש']), isEmpty);

        // רק הספר שעבר קטגוריה מוחלף: שכנו שזז ברצף ממוין לפי המיפוי.
        final changed = await refreshBetween(before, after);
        expect(changed?.map(BookIdentity.keyOf), ['uid:5']);
        final result = await indexer.runIndexing(
          after,
          books: const [],
          changedBooks: changed!,
          onProgress: (_, _) {},
        );
        expect(result.isClean, isTrue);
        expect(result.indexedBooks, 1);
        final hits = await search('שלום');
        expect(hits.map((hit) => hit.filePath), [
          'id:1',
          'id:9',
          'db:reference:5',
          'uid:5',
        ]);
        // מספר הספר יציב: גם הספר שנכתב מחדש שומר על המזהים שלו.
        expect({for (final hit in hits) hit.filePath: hit.id}, originalIds);
        expect((await search('שלום עולם')).map((r) => r.filePath), ['uid:5']);
        expect((await search('שלום', ['/מדרש'])).map((r) => r.filePath), [
          'uid:5',
        ]);
        expect(await search('שלום', ['/ספרים אישיים']), isEmpty);
        expect(await refreshBetween(after, after), isNull);

        final reversed = await refreshBetween(after, before);
        expect(reversed?.map(BookIdentity.keyOf), ['uid:5']);
        await indexer.runIndexing(
          before,
          books: const [],
          changedBooks: reversed!,
          onProgress: (_, _) {},
        );
        expect(
          (await search('שלום')).map((hit) => hit.filePath),
          originalIds.keys,
        );
        expect(
          (await search('שלום', ['/ספרים אישיים'])).map((r) => r.filePath),
          ['uid:5'],
        );
      },
      skip: nativeAvailable ? false : searchEngineSkipReason,
    );

    test(
      'בדיקה מלאה מול המנוע: שינוי סדר אינו מאנדקס, שינוי קטגוריה כן',
      () async {
        final directory = await Directory.systemTemp.createTemp('stamp_check_');
        final engine = await SearchEngine.newInstance(path: directory.path);
        final provider = _NativeIndex(engine)..activeIndexPath = directory.path;
        addTearDown(() async {
          provider.isIndexing.dispose();
          engine.dispose();
          await directory.delete(recursive: true);
        });
        final indexer = _MemoryTextRepository(provider);
        TextBook earlyBook(Category category) =>
            TextBook(id: 1, title: 'ספר מוקדם', category: category);
        final before = _libraryOf({
          ['הלכה']: [_officialBook],
          ['ספרים אישיים']: [_userBook],
          ['תנ"ך']: [earlyBook],
        });
        // ספר חדש לפני כולם, והאישי עבר קטגוריה.
        TextBook newcomer(Category category) =>
            TextBook(id: 2, title: 'ספר חדש', category: category);
        final after = _libraryOf({
          ['תנ"ך']: [newcomer, earlyBook],
          ['מדרש']: [_userBook],
          ['הלכה']: [_officialBook],
        });
        await indexer.runIndexing(
          before,
          books: before.getIndexableBooks(),
          onProgress: (_, _) {},
        );
        final read = <String>[];
        indexer.onLoad = read.add;

        final result = await indexer.runIndexing(
          after,
          books: const [],
          check: IndexCheckScope.library,
          onProgress: (_, _) {},
        );

        expect(result.completed, isTrue);
        // רק האישי הוחלף (topics); הרשמיים נבדקו בטביעת טקסט ונמצאו תואמים.
        expect(result.indexedBooks, 1);
        expect(read.where((title) => title == _userBookTitle), hasLength(1));
        final stamps = {
          for (final stamp in await engine.getBookStamps())
            stamp.filePath: stamp,
        };
        expect(stamps.keys.toSet(), {'id:1', 'id:9', 'uid:5'});
      },
      skip: nativeAvailable ? false : searchEngineSkipReason,
    );

    test('סמן של ספר ריק נושא את טביעת הטקסט הריק של המנוע', () async {
      final directory = await Directory.systemTemp.createTemp('empty_marker_');
      final engine = await SearchEngine.newInstance(path: directory.path);
      final provider = _NativeIndex(engine)..activeIndexPath = directory.path;
      addTearDown(() async {
        provider.isIndexing.dispose();
        engine.dispose();
        await directory.delete(recursive: true);
      });
      final library = _libraryOf({
        ['הלכה']: [
          (category) => TextBook(id: 3, title: _emptyTitle, category: category),
        ],
      });

      await _MemoryTextRepository(provider).runIndexing(
        library,
        books: library.getIndexableBooks(),
        onProgress: (_, _) {},
      );

      final stamp = (await engine.getBookStamps()).single;
      expect(
        stamp.textHash,
        await computeContentFingerprintBytes(text: const []),
      );
      expect(stamp.textHash, isNot(BigInt.zero));
    }, skip: nativeAvailable ? false : searchEngineSkipReason);

    test('רענון שלא הזיז ספרים — אין אינדוקס מחדש (issue #1977)', () async {
      Library build() => _libraryOf({
        ['מילונים וספרי יעץ', 'אנציקלופדיות']: [_userBook],
        ['הלכה']: [_officialBook],
      });

      expect(await refreshBetween(build(), build()), isNull);
    });

    test(
      'ספר שעבר בין קטגוריות באותו שם תחת הורים שונים מאונדקס, ושכניו לא',
      () async {
        Book Function(Category) at(int id) =>
            (category) =>
                TextBook(id: id, title: 'ספר $id', category: category);
        final before = _libraryOf({
          ['הלכה', 'מפרשים']: [at(1)],
          ['תנ"ך', 'מפרשים']: [at(2), at(3)],
        });
        final after = _libraryOf({
          ['הלכה', 'מפרשים']: [at(1), at(2)],
          ['תנ"ך', 'מפרשים']: [at(3)],
        });

        final changed = await refreshBetween(before, after);

        expect(changed?.map((b) => b.title), ['ספר 2']);
        expect(changed!.single.category!.path, '/הלכה/מפרשים');
      },
    );
  });
}

class _NativeIndex extends Fake implements TantivyDataProvider {
  _NativeIndex(this.value);

  final SearchEngine value;
  @override
  final indexedFilePaths = <String>{};
  @override
  final isIndexing = ValueNotifier(false);
  @override
  bool get requiresManualReindex => false;
  @override
  String? activeIndexPath;
  @override
  bool get isTempFallback => false;
  @override
  Future<SearchEngine> get engine async => value;
  @override
  Future<bool> reopenIndex({bool force = false}) async {
    indexedFilePaths
      ..clear()
      ..addAll(await value.getIndexedFilePaths());
    return true;
  }
}

class _MemoryTextRepository extends IndexingRepository {
  _MemoryTextRepository(super.provider)
    : super(hiddenStore: const _EmptyHiddenStore());

  @override
  Future<
    ({
      Uint8List? bytes,
      String? text,
      int? libraryDbBookId,
      int? userBooksDbBookId,
      int? attachedDbBookId,
      Uint32List? dataUriLines,
    })
  >
  loadTextBookSource(TextBook book) async {
    onLoad?.call(book.title);
    return _source(book);
  }

  void Function(String title)? onLoad;
  Map<String, String> texts = {};

  ({
    Uint8List? bytes,
    String? text,
    int? libraryDbBookId,
    int? userBooksDbBookId,
    int? attachedDbBookId,
    Uint32List? dataUriLines,
  })
  _source(TextBook book) => (
    bytes: null,
    text:
        texts[book.title] ??
        (book.title == _emptyTitle
            ? ''
            : book.source.isUser
            ? 'שלום\nעולם אישי'
            : 'שלום\nאחר רשמי'),
    libraryDbBookId: null,
    userBooksDbBookId: null,
    attachedDbBookId: null,
    dataUriLines: null,
  );
}

class _PersistentIndex {
  _PersistentIndex(this.directory);

  final Directory directory;
  final texts = <String, String>{};
  late _NativeIndex provider;
  late _MemoryTextRepository repository;

  PendingReindexStore get pending =>
      PendingReindexStore.forIndex(directory.path)!;

  static Future<_PersistentIndex> open() async {
    final index = _PersistentIndex(
      await Directory.systemTemp.createTemp('cancel_merge_'),
    );
    await index._open();
    return index;
  }

  Future<void> _open() async {
    provider = _NativeIndex(
      await SearchEngine.newInstance(path: directory.path),
    )..activeIndexPath = directory.path;
    await provider.reopenIndex();
    repository = _MemoryTextRepository(provider)..texts = texts;
  }

  Future<void> restart() async {
    provider.value.dispose();
    provider.isIndexing.dispose();
    PendingReindexStore.resetMemoryForTesting();
    await _open();
  }

  Future<List<String>> pathsIn(String facet, {String query = 'שלום'}) async => [
    for (final hit in await provider.value.searchExact(
      query: query,
      facets: [facet],
      limit: 10,
      offset: 0,
      order: ResultsOrder.catalogue,
      matchNikud: false,
      matchTaamim: false,
    ))
      hit.filePath,
  ];

  Future<void> close() async {
    provider.value.dispose();
    provider.isIndexing.dispose();
    PendingReindexStore.resetMemoryForTesting();
    await directory.delete(recursive: true);
  }
}
