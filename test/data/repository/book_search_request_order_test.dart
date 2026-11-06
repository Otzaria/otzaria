import 'dart:async';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/book_search_worker.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

class _DelayedCatalogRepository extends DataRepository {
  final catalogRequested = Completer<void>();
  final catalog = Completer<List<ExternalLibraryBook>>();
  int catalogLoads = 0;

  @override
  Future<List<ExternalLibraryBook>> getOtzarBooks() {
    catalogLoads++;
    if (!catalogRequested.isCompleted) catalogRequested.complete();
    return catalog.future;
  }
}

class _CountedCatalogBook extends ExternalLibraryBook {
  _CountedCatalogBook(int id)
    : super(title: 'ספר חיצוני $id', id: id, link: '');

  int titleReads = 0;

  @override
  String get title {
    titleReads++;
    return super.title;
  }
}

class _SearchCategory extends Category {
  _SearchCategory()
    : super(
        title: 'ספרים',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [
          TextBook(title: 'מבחן אלף'),
          TextBook(title: 'מבחן בית'),
        ],
        parent: null,
      );

  void Function()? onCategories;

  @override
  List<Category> getAllCategories() {
    final callback = onCategories;
    onCategories = null;
    callback?.call();
    return super.getAllCategories();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DelayedCatalogRepository repository;
  late _SearchCategory category;
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    repository = _DelayedCatalogRepository();
    category = _SearchCategory();
  });
  tearDown(() => repository.bookSearchWorkerForTesting.dispose());

  for (final finishLatestFirst in [false, true]) {
    test(
      'a delayed older catalog cannot supersede the latest search '
      '(latest already completed: $finishLatestFirst)',
      () async {
        final key = Object();
        final older = repository.findBooksAndCategories(
          'אלף',
          category,
          includeOtzar: true,
          includeLocalHebrewBooks: false,
          supersedeKey: key,
        );
        final olderCheck = expectLater(
          older,
          throwsA(isA<BookSearchSupersededException>()),
        );
        await repository.catalogRequested.future;
        if (!finishLatestFirst) {
          // משחררים את הקטלוג בדיוק כשהחיפוש החדש מגיע לתור ה-worker.
          category.onCategories = () => repository.catalog.complete([]);
        }
        final newer = repository.findBooksAndCategories(
          'בית',
          category,
          includeLocalHebrewBooks: false,
          supersedeKey: key,
        );
        final result = await newer;
        expect(result.books.map((book) => book.title), ['מבחן בית']);
        if (finishLatestFirst) repository.catalog.complete([]);
        await olderCheck;
      },
    );
  }

  test('superseded catalog searches do not materialize book entries', () async {
    final key = Object();
    final olderChecks = <Future<void>>[];
    for (var i = 0; i < 4; i++) {
      olderChecks.add(
        expectLater(
          repository.findBooksAndCategories(
            'ישן $i',
            category,
            includeOtzar: true,
            includeLocalHebrewBooks: false,
            supersedeKey: key,
          ),
          throwsA(isA<BookSearchSupersededException>()),
        ),
      );
    }
    await repository.catalogRequested.future;
    final newer = await repository.findBooksAndCategories(
      'בית',
      category,
      includeLocalHebrewBooks: false,
      supersedeKey: key,
    );
    expect(newer.books.map((book) => book.title), ['מבחן בית']);

    final books = List.generate(32, _CountedCatalogBook.new);
    repository.catalog.complete(books);
    await Future.wait(olderChecks);

    expect(books.map((book) => book.titleReads), everyElement(0));
    expect(repository.catalogLoads, 1);
    expect(repository.bookSearchWorkerForTesting.indexUploads, 1);
  });

  test('the latest search still uses the shared catalog load', () async {
    final key = Object();
    final olderCheck = expectLater(
      repository.findBooksAndCategories(
        'ישן',
        category,
        includeOtzar: true,
        includeLocalHebrewBooks: false,
        supersedeKey: key,
      ),
      throwsA(isA<BookSearchSupersededException>()),
    );
    await repository.catalogRequested.future;
    final newer = repository.findBooksAndCategories(
      'חיצוני',
      category,
      includeOtzar: true,
      includeLocalHebrewBooks: false,
      sortByRatio: false,
      supersedeKey: key,
    );
    final books = List.generate(32, _CountedCatalogBook.new);
    repository.catalog.complete(books);

    await olderCheck;
    final result = await newer;
    expect(books.map((book) => book.titleReads), everyElement(1));
    expect(result.books, orderedEquals(books));
    expect(result.categories, isEmpty);
    expect(repository.catalogLoads, 1);
    expect(repository.bookSearchWorkerForTesting.indexUploads, 1);
  });

  for (final useKeys in [false, true]) {
    test(
      'independent catalog searches both complete (keys: $useKeys)',
      () async {
        final older = repository.findBooksAndCategories(
          'חיצוני',
          category,
          includeOtzar: true,
          includeLocalHebrewBooks: false,
          sortByRatio: false,
          supersedeKey: useKeys ? Object() : null,
        );
        await repository.catalogRequested.future;
        final newer = repository.findBooksAndCategories(
          'חיצוני',
          category,
          includeOtzar: true,
          includeLocalHebrewBooks: false,
          sortByRatio: false,
          supersedeKey: useKeys ? Object() : null,
        );
        final books = List.generate(32, _CountedCatalogBook.new);
        repository.catalog.complete(books);

        final results = await Future.wait([older, newer]);
        expect(books.map((book) => book.titleReads), everyElement(2));
        for (final result in results) {
          expect(result.books, orderedEquals(books));
          expect(result.categories, isEmpty);
        }
        expect(repository.catalogLoads, 1);
        expect(repository.bookSearchWorkerForTesting.indexUploads, 1);
      },
    );
  }

  test(
    'supersession while collecting categories keeps the latest token',
    () async {
      final key = Object();
      late Future<({List<Book> books, List<Category> categories})> newer;
      category.onCategories = () {
        newer = repository.findBooksAndCategories(
          'בית',
          category,
          includeLocalHebrewBooks: false,
          supersedeKey: key,
        );
      };
      await expectLater(
        repository.findBooksAndCategories(
          'אלף',
          category,
          includeLocalHebrewBooks: false,
          supersedeKey: key,
        ),
        throwsA(isA<BookSearchSupersededException>()),
      );

      expect((await newer).books.map((book) => book.title), ['מבחן בית']);
      expect(repository.bookSearchWorkerForTesting.indexUploads, 1);
    },
  );

  test('a catalog load failure keeps its error after supersession', () async {
    final key = Object();
    final error = StateError('catalog failed');
    final olderCheck = expectLater(
      repository.findBooksAndCategories(
        'אלף',
        category,
        includeOtzar: true,
        includeLocalHebrewBooks: false,
        supersedeKey: key,
      ),
      throwsA(same(error)),
    );
    await repository.catalogRequested.future;
    final newer = await repository.findBooksAndCategories(
      'בית',
      category,
      includeLocalHebrewBooks: false,
      supersedeKey: key,
    );
    repository.catalog.completeError(error);

    await olderCheck;
    expect(newer.books.map((book) => book.title), ['מבחן בית']);
    expect(repository.catalogLoads, 1);
    expect(repository.bookSearchWorkerForTesting.indexUploads, 1);
  });
}
