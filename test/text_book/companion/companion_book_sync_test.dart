import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/companion/companion_book_sync.dart';
import 'package:otzaria/text_book/companion/companion_books.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

import '../../helpers/memory_settings_cache.dart';

Link _source(int primaryLine, int baseLine) => Link(
  heRef: 'שו״ע',
  index1: primaryLine + 1,
  path2: 'שולחן ערוך, אורח חיים',
  index2: baseLine + 1,
  connectionType: LinkTypes.source,
  baseProvenance: 2,
);

TextBookLoaded _loaded(TextBook book, Map<int, List<Link>> links) =>
    TextBookLoaded(
      book: book,
      content: List.filled(1000, 'שורה'),
      fontSize: 20,
      showLeftPane: false,
      showSplitView: true,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: links,
      tableOfContents: const [],
      visibleIndices: [for (final line in links.keys) line - 1],
      pinLeftPane: false,
      searchText: '',
    );

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);
  final requested = <int>[];
  @override
  Future<List<Link>> getSiblingCommentaries({
    required String sourceBookTitle,
    required int? sourceCategoryId,
    required int sourceLineIndex,
    required String currentBookTitle,
    required int? currentCategoryId,
    BookSource sourceBookSource = BookSource.official,
    BookSource currentBookSource = BookSource.official,
    bool requireExactLine = false,
  }) async {
    requested.add(sourceLineIndex);
    return [
      Link(
        heRef: 'ביאור הלכה',
        index1: sourceLineIndex + 1,
        path2: 'ביאור הלכה',
        index2: sourceLineIndex + 1,
        connectionType: LinkTypes.commentary,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => Settings.init(cacheProvider: MemorySettingsCache()));

  test(
    'late links resynchronize after an earlier successful synchronization',
    () {
      fakeAsync((async) {
        final repository = _Repository();
        final book = TextBook(title: 'משנה ברורה');
        final bloc = TextBookBloc(
          repository: repository,
          initialState: TextBookInitial.named(book, 0, false, const []),
        );
        bloc.emit(
          _loaded(book, {
            1: [_source(0, 10)],
          }),
        );
        final primary = TextBookTab(book: book, index: 0, blocOverride: bloc);
        final companion = TextBookTab(
          book: TextBook(title: 'ביאור הלכה'),
          index: 0,
        );
        final sync = CompanionBookSync(primary: primary, companion: companion);
        async.elapse(const Duration(milliseconds: 400));
        expect(companion.index, 10);
        primary.lines.jumpToLine(500);
        async.elapse(const Duration(milliseconds: 400));
        bloc.emit(
          _loaded(book, {
            501: [_source(500, 70)],
          }),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 400));
        expect(companion.index, 70);
        bloc.emit((bloc.state as TextBookLoaded).copyWith(fontSize: 30));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        expect(repository.requested, [10, 70]);
        sync.dispose();
        primary.dispose();
        companion.dispose();
        async.flushMicrotasks();
      });
    },
  );

  test(
    'an old async result is invalid as soon as a newer position arrives',
    () {
      fakeAsync((async) {
        final primary = TextBookTab(
          book: TextBook(title: 'משנה ברורה'),
          index: 0,
        );
        final companion = TextBookTab(
          book: TextBook(title: 'ביאור הלכה'),
          index: 0,
        );
        final results = <int, Completer<int?>>{};
        final sync = CompanionBookSync(
          primary: primary,
          companion: companion,
          resolveCompanionLine: (line) =>
              (results[line] = Completer<int?>()).future,
        );
        async.elapse(const Duration(milliseconds: 300));
        primary.lines.jumpToLine(500);
        results[0]!.complete(10);
        async.flushMicrotasks();
        expect(companion.index, 0);
        async.elapse(const Duration(milliseconds: 300));
        results[500]!.complete(70);
        async.flushMicrotasks();
        expect(companion.index, 70);
        primary.lines.jumpToLine(600);
        async.elapse(const Duration(milliseconds: 300));
        sync.dispose();
        results[600]!.complete(80);
        async.flushMicrotasks();
        expect(companion.index, 70);
        primary.dispose();
        companion.dispose();
        async.flushMicrotasks();
      });
    },
  );

  test('following the primary adds no return points (issue #3909)', () {
    fakeAsync((async) {
      final primary = TextBookTab(
        book: TextBook(title: 'משנה ברורה'),
        index: 0,
      );
      final companion = TextBookTab(
        book: TextBook(title: 'ביאור הלכה'),
        index: 0,
        initialReadingAnchor: const ReadingAnchor(line: 0),
      );
      final sync = CompanionBookSync(
        primary: primary,
        companion: companion,
        resolveCompanionLine: (line) async => line,
      );
      async.elapse(const Duration(milliseconds: 400));
      // A link inside the companion pane.
      companion.lines.scrollToLine(300);
      for (final line in [10, 20, 30]) {
        primary.lines.jumpToLine(line);
        async.elapse(const Duration(milliseconds: 400));
      }
      expect(companion.index, 30);
      companion.lines.goBack();
      async.flushMicrotasks();
      expect(companion.lines.captureAnchor()!.line, 0);
      expect(companion.lines.canGoBack.value, isFalse);
      sync.dispose();
      primary.dispose();
      companion.dispose();
      async.flushMicrotasks();
    });
  });

  for (final source in [BookSource.user, BookSource.attached('test')]) {
    test(
      'does not open a non-official companion from ${source.wireKey}',
      () async {
        final library = Library(categories: []);
        library.books.add(TextBook(title: 'ביאור הלכה', source: source));
        DataRepository.instance.library = Future.value(library);
        final primary = TextBookTab(
          book: TextBook(title: 'משנה ברורה'),
          index: 0,
        );
        final companion = await createCompanionTab(primary);
        addTearDown(() {
          primary.dispose();
          companion?.dispose();
        });
        expect(companion, isNull);
      },
    );
  }

  test(
    'finds the official companion even after a personal book with its title',
    () async {
      final official = TextBook(title: 'ביאור הלכה');
      final library = Library(categories: []);
      library.books.addAll([
        TextBook(title: official.title, source: BookSource.user),
        official,
      ]);
      DataRepository.instance.library = Future.value(library);
      final primary = TextBookTab(
        book: TextBook(title: 'משנה ברורה'),
        index: 0,
      );
      final companion = await createCompanionTab(primary);
      addTearDown(() {
        primary.dispose();
        companion?.dispose();
      });
      expect(companion?.book, same(official));
    },
  );

  group('exact base line', () {
    late Directory dir;
    late MyDatabase database;
    late TextBookRepository repository;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('companion-sync-');
      database = MyDatabase.withPath('${dir.path}/test.db');
      final db = await database.database;
      db.execute("INSERT INTO category(id,title,level) VALUES(1,'קטגוריה',0)");
      db.execute("INSERT INTO source(id,name) VALUES(1,'בדיקה')");
      for (final entry in {
        1: 'שולחן ערוך, אורח חיים',
        2: 'ביאור הלכה',
        3: 'משנה ברורה',
      }.entries) {
        db.execute(
          'INSERT INTO book(id,title,categoryId,sourceId) VALUES(?,?,1,1)',
          [entry.key, entry.value],
        );
      }
      for (var i = 0; i < 10; i++) {
        db.execute(
          "INSERT INTO line(id,bookId,lineIndex,content) VALUES(?,1,?,'סעיף')",
          [100 + i, i],
        );
        db.execute(
          "INSERT INTO line(id,bookId,lineIndex,content) VALUES(?,2,?,'ביאור')",
          [200 + i, i],
        );
      }
      db.execute("INSERT INTO connection_type(id,name) VALUES(1,'COMMENTARY')");
      db.execute(
        'INSERT INTO link(sourceBookId,targetBookId,sourceLineId,targetLineId,connectionTypeId) VALUES(1,2,104,208,1)',
      );
      repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
        sqliteProvider: SqliteDataProvider.withRepository(
          SeforimRepository(database),
        ),
      );
    });
    tearDown(() async {
      database.close();
      await dir.delete(recursive: true);
    });

    Future<void> check(
      TextBookRepository repository,
      int exactBase,
      int emptyBase,
    ) async {
      final book = TextBook(title: 'משנה ברורה');
      final bloc = TextBookBloc(
        repository: repository,
        initialState: TextBookInitial.named(book, 0, false, const []),
      );
      bloc.emit(
        _loaded(book, {
          1: [_source(0, emptyBase)],
        }),
      );
      final primary = TextBookTab(book: book, index: 0, blocOverride: bloc);
      final companion = TextBookTab(
        book: TextBook(title: 'ביאור הלכה'),
        index: 3,
      );
      final sync = CompanionBookSync(
        primary: primary,
        companion: companion,
        debounce: Duration.zero,
      );
      addTearDown(() {
        sync.dispose();
        primary.dispose();
        companion.dispose();
      });
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(companion.index, 3, reason: 'סעיף ללא בה״ל לא מזיז את החלונית');
      final reached = Completer<void>();
      void onPosition() {
        if (companion.index == 8 && !reached.isCompleted) reached.complete();
      }

      companion.lines.position.addListener(onPosition);
      addTearDown(() => companion.lines.position.removeListener(onPosition));
      bloc.emit(
        _loaded(book, {
          501: [_source(500, exactBase)],
        }),
      );
      primary.lines.jumpToLine(500);
      await reached.future.timeout(const Duration(seconds: 10));
      expect(companion.index, 8);
    }

    test(
      'a single fallback target must not be mistaken for an exact match',
      () async {
        final siblings = await repository.getSiblingCommentaries(
          sourceBookTitle: 'שולחן ערוך, אורח חיים',
          sourceCategoryId: null,
          sourceLineIndex: 5,
          currentBookTitle: 'משנה ברורה',
          currentCategoryId: null,
        );
        expect(siblings.single.index2, 9);
        expect(siblings.single.index2End, isNull);
        await check(repository, 4, 5);
      },
    );

    final realDb = Platform.environment['OTZARIA_TEST_DB'];
    test(
      'real Shulchan Aruch Orach Chaim 1:5 and 1:6',
      () async {
        final real = MyDatabase.withPath(
          realDb!,
          readOnly: true,
          official: true,
        );
        addTearDown(real.close);
        final seforim = SeforimRepository(real);
        final rows = await seforim.getSiblingCommentaryLinkRowsForLine(
          bookId: 382,
          bookTitle: 'שולחן ערוך, אורח חיים',
          lineIndex: 8,
          excludeBookId: 3860,
        );
        CommentaryService.seedEraCache({
          for (final row in rows)
            row['targetBookTitle'] as String: CommentaryEra.other,
        });
        addTearDown(CommentaryService.clearEraCache);
        final repository = TextBookRepository(
          fileSystem: FileSystemData.instance,
          sqliteProvider: SqliteDataProvider.withRepository(seforim),
        );
        Future<List<Link>> siblings(int line, {bool exact = false}) =>
            repository.getSiblingCommentaries(
              sourceBookTitle: 'שולחן ערוך, אורח חיים',
              sourceCategoryId: 61,
              sourceLineIndex: line,
              currentBookTitle: 'משנה ברורה',
              currentCategoryId: 703,
              requireExactLine: exact,
            );
        final exact = await siblings(8, exact: true);
        expect(
          exact.where((link) => link.path2 == 'ביאור הלכה').single.index2,
          9,
        );
        final empty = await siblings(9, exact: true);
        expect(empty.where((link) => link.path2 == 'ביאור הלכה'), isEmpty);
        final fallback = await siblings(9);
        expect(
          fallback.where((link) => link.path2 == 'ביאור הלכה').single.index2,
          5,
        );
      },
      skip: realDb == null
          ? 'יש להגדיר OTZARIA_TEST_DB למסד אמיתי לקריאה בלבד'
          : false,
    );
  });
}
