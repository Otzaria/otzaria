import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/memory_settings_cache.dart';
import '../helpers/seforim_fixture_db.dart';

class _ObservedRepository extends FindRefRepository {
  _ObservedRepository(SeforimRepository userRepository)
    : super(
        isReferenceBooksCacheLoaded: () => true,
        warmUpReferenceBooksCache: () async {},
        searchReferenceBooks: (_, {limit = 50}) => const [],
        getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
        openUserBooksRepository: () async => userRepository,
      );

  final searches = <(String, bool)>[];
  Completer<void>? holdNextResult;
  Completer<void>? resultReady;

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    searches.add((ref, includePersonalBooks));
    final hold = holdNextResult;
    holdNextResult = null;
    final results = await super.findRefs(
      ref,
      includePersonalBooks: includePersonalBooks,
    );
    if (hold != null) {
      resultReady!.complete();
      await hold.future;
    }
    return results;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late String databasePath;
  late MyDatabase database;
  late _ObservedRepository repository;
  late FindRefBloc bloc;
  late List<FindRefState> states;
  late StreamSubscription<FindRefState> stateSubscription;
  const query = 'קונטרס חדש';
  const debounce = Duration(milliseconds: 350);

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await QueryLoader.initialize();
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('find_ref_refresh_');
    databasePath = SeforimFixtureDb.create(
      directory,
      SeforimFixtureVariant.full,
    );
    database = MyDatabase.withPath(databasePath);
    final userRepository = SeforimRepository(database);
    await userRepository.ensureInitialized();
    repository = _ObservedRepository(userRepository);
    bloc = FindRefBloc(findRefRepository: repository);
    states = [];
    stateSubscription = bloc.stream.listen(states.add);
  });

  tearDown(() async {
    if (!bloc.isClosed) await bloc.close();
    await repository.debugUserBooksRefresh;
    await stateSubscription.cancel();
    await AttachedFindRefWorker.instance.reset();
    database.close();
    await directory.delete(recursive: true);
  });

  void addBook({int id = 50}) {
    final db = sqlite3.sqlite3.open(databasePath);
    try {
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex) '
        'VALUES (?, ?, 1, ?, 3)',
        [id, SeforimFixtureIds.torahCategoryId, query],
      );
    } finally {
      db.close();
    }
  }

  Future<FindRefSuccess> search(
    String text, {
    bool includePersonalBooks = true,
  }) async {
    final result = bloc.stream.firstWhere((state) => state is FindRefSuccess);
    bloc.add(
      SearchRefRequested(text, includePersonalBooks: includePersonalBooks),
    );
    return await result.timeout(const Duration(seconds: 10)) as FindRefSuccess;
  }

  Future<void> refresh({bool Function(FindRefState)? until}) async {
    final result = until == null ? null : bloc.stream.firstWhere(until);
    // LibraryBloc invokes this after catalog refresh, including startup sync.
    FindRefRepository.revalidateUserBooks();
    await repository.debugUserBooksRefresh;
    if (result == null) {
      await Future<void>.delayed(debounce);
    } else {
      await result.timeout(
        const Duration(seconds: 5),
        onTimeout: () => bloc.state,
      );
    }
  }

  bool hasNewBook(FindRefState state) =>
      state is FindRefSuccess &&
      state.refs.any(
        (ref) => ref.source == BookSource.user && ref.bookId == 50,
      );

  ({Future<void> ready, void Function() release}) pauseNextRead({
    bool fail = false,
  }) {
    final ready = Completer<void>();
    final released = Completer<void>();
    final previous = repository.debugAfterUserBooksRead;
    repository.debugAfterUserBooksRead = () async {
      repository.debugAfterUserBooksRead = previous;
      if (previous != null) await previous();
      ready.complete();
      await released.future;
      if (fail) throw StateError('held personal catalog read failed');
    };
    void release() {
      if (!released.isCompleted) released.complete();
    }

    addTearDown(release);
    return (ready: ready.future, release: release);
  }

  test('personal catalog refresh updates already displayed results', () async {
    expect((await search(query)).refs, isEmpty);
    addBook();

    await refresh(until: hasNewBook);

    expect(bloc.state, predicate<FindRefState>(hasNewBook));
    expect((bloc.state as FindRefSuccess).query, query);
    expect(repository.searches, [(query, true), (query, true)]);
  });

  test('unchanged catalog and initial load do not repeat the search', () async {
    await search(query);
    final before = states.length;

    await refresh();
    bloc.add(const SearchRefRequested('$query ', includePersonalBooks: true));
    await Future<void>.delayed(debounce);

    expect(repository.searches, [(query, true)]);
    expect(states, hasLength(before));
  });

  for (final personal in [true, false]) {
    test(
      'refresh keeps the latest query during debounce ($personal)',
      () async {
        await search('בראשית');
        bloc.add(SearchRefRequested(query, includePersonalBooks: personal));
        await pumpEventQueue();
        addBook();

        await refresh(
          until: (state) =>
              state is FindRefSuccess &&
              state.query == query &&
              state.includePersonalBooks == personal &&
              hasNewBook(state) == personal,
        );

        final result = bloc.state as FindRefSuccess;
        expect(result.query, query);
        expect(result.includePersonalBooks, personal);
        expect(hasNewBook(result), personal);
        expect(repository.searches.skip(1), everyElement((query, personal)));
      },
    );
  }

  for (final personal in [true, false]) {
    test(
      'catalog invalidation survives returning to the old query ($personal)',
      () async {
        await search(query);
        final updated = bloc.stream.firstWhere(hasNewBook);
        if (!personal) {
          bloc.add(
            const SearchRefRequested('בראשית', includePersonalBooks: false),
          );
          await pumpEventQueue();
        }
        addBook();
        final changed = repository.userBooksChanges.first;
        FindRefRepository.revalidateUserBooks();
        await changed.timeout(const Duration(seconds: 5));
        await pumpEventQueue();
        if (personal) {
          bloc.add(
            const SearchRefRequested('בראשית', includePersonalBooks: true),
          );
          await pumpEventQueue();
        }
        bloc.add(const SearchRefRequested(query, includePersonalBooks: true));
        await updated.timeout(
          const Duration(seconds: 5),
          onTimeout: () => bloc.state,
        );

        expect(bloc.state, predicate<FindRefState>(hasNewBook));
        expect((bloc.state as FindRefSuccess).query, query);
      },
    );
  }

  test(
    'reusing non-personal results cancels a personal refresh in debounce',
    () async {
      await search('בראשית');
      final shown = await search(query, includePersonalBooks: false);
      bloc.add(const SearchRefRequested('בראשית', includePersonalBooks: true));
      await pumpEventQueue();
      addBook();
      final changed = repository.userBooksChanges.first;
      FindRefRepository.revalidateUserBooks();
      await changed.timeout(const Duration(seconds: 5));
      await pumpEventQueue();

      bloc.add(const SearchRefRequested(query, includePersonalBooks: false));
      await Future<void>.delayed(debounce);

      expect(bloc.state, shown);
      expect(repository.searches, [('בראשית', true), (query, false)]);
    },
  );

  test('refresh does not revive results after clearing the query', () async {
    await search(query);
    bloc.add(ClearSearchRequested());
    await pumpEventQueue();
    addBook();

    await refresh();

    expect(bloc.state, isA<FindRefInitial>());
    expect(repository.searches, [(query, true)]);
  });

  test('refresh keeps personal books disabled', () async {
    await search('בראשית');
    await search(query, includePersonalBooks: false);
    addBook();

    await refresh();

    final result = bloc.state as FindRefSuccess;
    expect(result.query, query);
    expect(result.includePersonalBooks, isFalse);
    expect(result.refs, isEmpty);
    expect(repository.searches, [('בראשית', true), (query, false)]);
  });

  test(
    'older in-flight results cannot replace the refreshed catalog',
    () async {
      await search('בראשית');
      final snapshot = pauseNextRead();
      final gate = repository.holdNextResult = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      repository.resultReady = Completer<void>();
      bloc.add(const SearchRefRequested(query, includePersonalBooks: true));
      await repository.resultReady!.future.timeout(const Duration(seconds: 10));
      await snapshot.ready.timeout(const Duration(seconds: 10));
      addBook();

      final refreshing = refresh(until: hasNewBook);
      snapshot.release();
      await refreshing;
      gate.complete();
      await pumpEventQueue();

      expect(bloc.state, predicate<FindRefState>(hasNewBook));
      expect((bloc.state as FindRefSuccess).query, query);
    },
  );

  for (final failedRead in [false, true]) {
    test(
      'a write during initial loading is not lost (failure: $failedRead)',
      () async {
        final snapshot = pauseNextRead(fail: failedRead);
        final updated = bloc.stream.firstWhere(hasNewBook);
        bloc.add(const SearchRefRequested(query, includePersonalBooks: true));
        await snapshot.ready.timeout(const Duration(seconds: 10));
        expect(repository.debugUserBooksIndex, isNull);
        addBook();

        FindRefRepository.revalidateUserBooks();
        snapshot.release();
        await updated.timeout(
          const Duration(seconds: 5),
          onTimeout: () => bloc.state,
        );

        expect(bloc.state, predicate<FindRefState>(hasNewBook));
        expect((bloc.state as FindRefSuccess).query, query);
      },
    );
  }

  test('a later write recovers after initial loading already failed', () async {
    repository.debugAfterUserBooksRead = () async {
      repository.debugAfterUserBooksRead = null;
      throw StateError('initial personal catalog read failed');
    };
    expect((await search(query)).refs, isEmpty);
    expect(repository.debugUserBooksIndex, isNull);
    expect(repository.debugUserBooksRefresh, isNull);
    addBook();

    await refresh(until: hasNewBook);

    expect(bloc.state, predicate<FindRefState>(hasNewBook));
    expect((bloc.state as FindRefSuccess).query, query);
  });

  test(
    'ordinary polls share a read; write signals share one fresh read',
    () async {
      await search(query);
      await search(query, includePersonalBooks: false);
      var reads = 0;
      var changes = 0;
      repository.debugAfterUserBooksRead = () async {
        reads++;
      };
      final subscription = repository.userBooksChanges.listen((_) => changes++);
      addTearDown(subscription.cancel);
      final snapshot = pauseNextRead();
      await repository.findRefs(query, includePersonalBooks: true);
      await snapshot.ready.timeout(const Duration(seconds: 10));

      for (var i = 0; i < 3; i++) {
        await repository.findRefs(query, includePersonalBooks: true);
      }
      expect(reads, 1);
      final changed = repository.userBooksChanges.first;
      for (var i = 0; i < 3; i++) {
        addBook(id: 50 + i);
        FindRefRepository.revalidateUserBooks();
      }
      snapshot.release();
      await changed.timeout(const Duration(seconds: 5), onTimeout: () {});
      await pumpEventQueue();

      expect(reads, 2);
      expect(changes, 1);
      final results = await repository.findRefs(
        query,
        includePersonalBooks: true,
      );
      expect(
        results
            .where((ref) => ref.source == BookSource.user)
            .map((ref) => ref.bookId),
        containsAll([50, 51, 52]),
      );
    },
  );

  for (final reset in ['cache reset', 'holder close', 'dispose']) {
    test(
      'a queued write refresh stops on $reset',
      () async {
        await search(query);
        var reads = 0;
        repository.debugAfterUserBooksRead = () async {
          reads++;
        };
        final snapshot = pauseNextRead();
        await repository.findRefs(query, includePersonalBooks: true);
        await snapshot.ready.timeout(const Duration(seconds: 10));
        addBook();
        FindRefRepository.revalidateUserBooks();
        final oldRead = repository.debugUserBooksRefresh;

        if (reset == 'dispose') {
          await bloc.close();
        } else if (reset == 'holder close') {
          await UserBooksDatabaseHolder.instance.close();
        } else {
          repository.clearCaches();
        }
        FindRefRepository.revalidateUserBooks();
        snapshot.release();
        await oldRead;
        await pumpEventQueue();

        expect(reads, 1);
        expect(repository.debugUserBooksRefresh, isNull);
        if (reset != 'dispose') expect(repository.debugUserBooksIndex, isNull);
        expect(repository.searches, [(query, true), (query, true)]);
      },
    );
  }

  test('closing the bloc while revalidating does not restart search', () async {
    await search(query);
    addBook();
    FindRefRepository.revalidateUserBooks();
    final refresh = repository.debugUserBooksRefresh;

    await bloc.close();
    await refresh;
    await pumpEventQueue();

    expect(repository.searches, [(query, true)]);
    expect(bloc.isClosed, isTrue);
  });
}
