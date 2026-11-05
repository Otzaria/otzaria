import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/models/index_check_scope.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  const failure = IndexingFailure(
    bookTitle: 'מוגן',
    bookPath: 'locked.pdf',
    kind: IndexingFailureKind.passwordProtected,
    error: 'password required',
  );

  Library libraryWithBooks([int count = 1]) =>
      Library(categories: [])
        ..books.addAll([
          for (var i = 0; i < count; i++) TextBook(id: i + 1, title: 'ספר $i'),
        ]);
  _FakeIndexingRepository repositoryOf(IndexingBloc bloc) =>
      (bloc as _FakeIndexingBloc).repository;

  group('StartIndexing', () {
    test('callback משלים גם כשאין ספרים ולא נפלט InProgress', () async {
      final bloc = _FakeIndexingBloc();
      final states = <IndexingState>[];
      final subscription = bloc.stream.listen(states.add);
      final settled = Completer<void>();
      bloc.add(
        StartIndexing(
          Library(categories: []),
          onSettled: settled.complete,
        ),
      );
      await settled.future.timeout(const Duration(seconds: 2));
      expect(states.whereType<IndexingInProgress>(), isEmpty);
      await subscription.cancel();
      await bloc.close();
    });

    test('callback שייך לאירוע המסוים וממתין לסיום העבודה', () async {
      final repository = _FakeIndexingRepository()
        ..finalizeGate = Completer<void>();
      final bloc = _FakeIndexingBloc(repository);
      final settled = Completer<void>();
      bloc.add(
        StartIndexing(
          libraryWithBooks(),
          onSettled: settled.complete,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(settled.isCompleted, isFalse);
      repository.finalizeGate!.complete();
      await settled.future.timeout(const Duration(seconds: 2));
      await bloc.close();
    });

    test('מחסום התור נפתח רק אחרי עבודת האינדוקס שלפניו', () async {
      final repository = _FakeIndexingRepository()
        ..finalizeGate = Completer<void>();
      final bloc = _FakeIndexingBloc(repository);
      final barrier = Completer<void>();
      bloc.add(StartIndexing(libraryWithBooks()));
      bloc.add(IndexingWorkBarrier(onSettled: barrier.complete));
      await Future<void>.delayed(Duration.zero);
      expect(barrier.isCompleted, isFalse);
      repository.finalizeGate!.complete();
      await barrier.future.timeout(const Duration(seconds: 2));
      expect(repository.indexAllCalls, 1);
      await bloc.close();
    });

    blocTest<IndexingBloc, IndexingState>(
      'ריצה נקייה מסתיימת ב-IndexingComplete נקי ואינה נרשמת ללוג',
      build: () {
        final repository = _FakeIndexingRepository();
        return _FakeIndexingBloc(repository);
      },
      act: (bloc) => bloc.add(StartIndexing(libraryWithBooks(2))),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isCreatingIndex: false,
        ),
        const IndexingComplete(),
      ],
      verify: (bloc) {
        final repository = repositoryOf(bloc);
        expect(repository.indexAllCalls, 1);
        expect(repository.reportedResults, isEmpty);
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'שלב האיחוד נפלט כמצב נפרד לפני ההשלמה',
      build: () {
        final repository = _FakeIndexingRepository()
          ..finalizeGate = Completer<void>();
        return _FakeIndexingBloc(repository);
      },
      act: (bloc) async {
        bloc.add(StartIndexing(libraryWithBooks(2)));
        await Future.delayed(Duration.zero);
        repositoryOf(bloc).finalizeGate!.complete();
      },
      expect: () => [
        const IndexingInProgress(booksProcessed: 0, totalBooks: 2),
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isFinalizing: true,
        ),
        const IndexingComplete(),
      ],
    );

    blocTest<IndexingBloc, IndexingState>(
      'ריצה עם כשל שומרת את הפרטים ב-state ומעבירה אותם לדיווח',
      build: () {
        final repository = _FakeIndexingRepository()
          ..result = const IndexingRunResult.completed(
            processedBooks: 1,
            totalBooks: 1,
            indexedBooks: 0,
            failures: [failure],
          );
        return _FakeIndexingBloc(repository);
      },
      act: (bloc) => bloc.add(StartIndexing(libraryWithBooks())),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 1,
          isCreatingIndex: false,
        ),
        const IndexingComplete(failures: [failure]),
      ],
      verify: (bloc) {
        expect(repositoryOf(bloc).reportedResults, hasLength(1));
        expect(repositoryOf(bloc).reportedResults.single.failures, [failure]);
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'ריצה שבוטלה אינה מוצגת כהשלמה אך הכשלים שלה נשמרים בדוח',
      build: () {
        final repository = _FakeIndexingRepository()
          ..result = const IndexingRunResult.cancelled(
            processedBooks: 1,
            totalBooks: 3,
            indexedBooks: 1,
            failures: [failure],
          );
        return _FakeIndexingBloc(repository);
      },
      act: (bloc) => bloc.add(StartIndexing(libraryWithBooks(3))),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 3,
          isCreatingIndex: false,
        ),
        isA<IndexingInitial>(),
      ],
      verify: (bloc) {
        expect(repositoryOf(bloc).reportedResults, hasLength(1));
        expect(repositoryOf(bloc).reportedResults.single.cancelled, isTrue);
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'אין עבודה — בלי InProgress, ישר להשלמה',
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..allBooksIndexed = true,
      ),
      act: (bloc) => bloc.add(StartIndexing(libraryWithBooks(3))),
      expect: () => [const IndexingComplete()],
      verify: (bloc) => expect(repositoryOf(bloc).indexAllCalls, 1),
    );

    blocTest<IndexingBloc, IndexingState>(
      'חריגת repository הופכת ל-IndexingError עם מוני ההתקדמות',
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..error = StateError('engine failed'),
      ),
      act: (bloc) => bloc.add(StartIndexing(libraryWithBooks())),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 1,
          isCreatingIndex: false,
        ),
        isA<IndexingError>()
            .having((state) => state.error, 'error', contains('engine failed'))
            .having((state) => state.booksProcessed, 'processed', 0)
            .having((state) => state.totalBooks, 'total', 1),
      ],
    );
  });

  group('שחזור הגדרות הסתרה', () {
    test('סיום ניקוי הסתרות ללא אינדוקס משחרר את ממתין העלייה', () async {
      final bloc = _FakeIndexingBloc();
      final settled = Completer<void>();
      bloc.add(
        ReconcileHiddenIndex(
          Library(categories: []),
          onSettled: settled.complete,
        ),
      );
      await settled.future.timeout(const Duration(seconds: 2));
      expect(bloc.repository.dropHiddenCalls, 1);
      await bloc.close();
    });

    final startupMessages = <String>[];
    blocTest<IndexingBloc, IndexingState>(
      'כשל ניקוי הסתרות בעלייה מדווח כשהחיפוש עלול לחשוף ספר',
      setUp: () async {
        startupMessages.clear();
        await const HiddenLibraryStore().save(
          HiddenLibrarySelection(
            bookKeys: {
              PerBookSettings.bookKey(TextBook(id: 1, title: 'ספר 0')),
            },
          ),
        );
      },
      build: () => IndexingBloc(
        _FakeIndexingRepository()..dropHiddenSucceeded = false,
        showHiddenReconciliationError: startupMessages.add,
      ),
      act: (bloc) => bloc.add(ReconcileHiddenIndex(libraryWithBooks())),
      expect: () => [isA<IndexingError>()],
      verify: (_) => expect(startupMessages, [
        SettingsMessages.hiddenBooksIndexUpdateFailed,
      ]),
      tearDown: () =>
          const HiddenLibraryStore().save(const HiddenLibrarySelection()),
    );

    blocTest<IndexingBloc, IndexingState>(
      'כשל תחזוקה ללא הסתרות אינו מציג הודעה מיותרת',
      setUp: () async {
        startupMessages.clear();
        await const HiddenLibraryStore().clearPendingIndexReconciliation();
        await const HiddenLibraryStore().save(const HiddenLibrarySelection());
      },
      build: () => IndexingBloc(
        _FakeIndexingRepository()..dropHiddenSucceeded = false,
        showHiddenReconciliationError: startupMessages.add,
      ),
      act: (bloc) => bloc.add(ReconcileHiddenIndex(libraryWithBooks())),
      expect: () => [isA<IndexingError>()],
      verify: (_) => expect(startupMessages, isEmpty),
    );

    blocTest<IndexingBloc, IndexingState>(
      'marker מתנקה גם כאשר כל הספרים הוסתרו',
      setUp: () async {
        await const HiddenLibraryStore().markIndexReconciliationPending();
        await const HiddenLibraryStore().save(
          HiddenLibrarySelection(
            bookKeys: {
              PerBookSettings.bookKey(TextBook(id: 1, title: 'ספר 0')),
            },
          ),
        );
      },
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(
        ReconcileHiddenIndex(
          libraryWithBooks(),
          indexVisible: true,
          clearRestoreMarker: true,
        ),
      ),
      verify: (bloc) {
        expect(repositoryOf(bloc).dropHiddenCalls, 1);
        expect(repositoryOf(bloc).indexAllCalls, 0);
        expect(
          const HiddenLibraryStore().hasPendingIndexReconciliation,
          isFalse,
        );
      },
      tearDown: () =>
          const HiddenLibraryStore().save(const HiddenLibrarySelection()),
    );

    blocTest<IndexingBloc, IndexingState>(
      'marker מתנקה אחרי ניקוי והשלמת אינדוקס',
      setUp: () => const HiddenLibraryStore().markIndexReconciliationPending(),
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(
        ReconcileHiddenIndex(
          libraryWithBooks(),
          indexVisible: true,
          clearRestoreMarker: true,
        ),
      ),
      verify: (bloc) {
        expect(repositoryOf(bloc).dropHiddenCalls, 1);
        expect(repositoryOf(bloc).indexAllCalls, 1);
        expect(
          const HiddenLibraryStore().hasPendingIndexReconciliation,
          isFalse,
        );
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'marker נשאר אחרי כשל במחיקת ספרים מוסתרים',
      setUp: () => const HiddenLibraryStore().markIndexReconciliationPending(),
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..dropHiddenSucceeded = false,
      ),
      act: (bloc) => bloc.add(
        ReconcileHiddenIndex(
          libraryWithBooks(),
          indexVisible: true,
          clearRestoreMarker: true,
        ),
      ),
      verify: (bloc) {
        expect(repositoryOf(bloc).indexAllCalls, 0);
        expect(
          const HiddenLibraryStore().hasPendingIndexReconciliation,
          isTrue,
        );
      },
    );

    for (final scenario in ['throw', 'cancel', 'unclean']) {
      final messages = <String>[];
      blocTest<IndexingBloc, IndexingState>(
        'כשל אינדוקס $scenario משאיר marker בלי הודעה כפולה',
        setUp: () async {
          messages.clear();
          await const HiddenLibraryStore().markIndexReconciliationPending();
        },
        build: () {
          final repository = _FakeIndexingRepository();
          if (scenario == 'throw') {
            repository.error = StateError('index failed');
          } else if (scenario == 'cancel') {
            repository.result = const IndexingRunResult.cancelled(
              processedBooks: 0,
              totalBooks: 1,
              indexedBooks: 0,
            );
          } else {
            repository.result = const IndexingRunResult.completed(
              processedBooks: 1,
              totalBooks: 1,
              indexedBooks: 0,
              failures: [failure],
            );
          }
          return IndexingBloc(
            repository,
            showHiddenReconciliationError: messages.add,
            reportFailures: (_, _) {},
          );
        },
        act: (bloc) => bloc.add(
          ReconcileHiddenIndex(
            libraryWithBooks(),
            indexVisible: true,
            clearRestoreMarker: true,
          ),
        ),
        verify: (bloc) {
          expect(
            const HiddenLibraryStore().hasPendingIndexReconciliation,
            isTrue,
          );
          if (scenario == 'unclean') {
            expect(bloc.state, const IndexingComplete(failures: [failure]));
            expect(messages, isEmpty);
          } else {
            expect(messages, [SettingsMessages.hiddenBooksIndexUpdateFailed]);
          }
        },
      );
    }
  });

  group('סימון שינויי הסתרה', () {
    const store = HiddenLibraryStore();

    setUp(() async {
      await store.resetRuntimeStateForAppRestart();
      await store.clearPendingVisibilityIndex(store.visibilityRevision);
      await store.clearPendingIndexReconciliation();
    });

    for (final outcome in [
      'כשל בספר',
      'חריגה',
      'תוצאה מבוטלת',
      'ביטול בזמן ריצה',
      'ביטול בבדיקת המצב',
    ]) {
      test('שחזור ספר עם $outcome מדווח כישלון ומשאיר marker', () async {
        final repository = _FakeIndexingRepository();
        switch (outcome) {
          case 'כשל בספר':
            repository.result = const IndexingRunResult.completed(
              processedBooks: 1,
              totalBooks: 1,
              indexedBooks: 0,
              failures: [failure],
            );
          case 'חריגה':
            repository.error = StateError('index failed');
          case 'תוצאה מבוטלת':
            repository.result = const IndexingRunResult.cancelled(
              processedBooks: 0,
              totalBooks: 1,
              indexedBooks: 0,
            );
          case 'ביטול בזמן ריצה':
            repository.runGate = Completer<void>();
          case 'ביטול בבדיקת המצב':
            repository.statusGate = Completer<void>();
        }
        final bloc = _FakeIndexingBloc(repository);
        addTearDown(bloc.close);
        final library = libraryWithBooks();
        final revision = await store.beginVisibilityIndexUpdate();
        final completions = <bool>[];
        final settled = Completer<void>();
        bloc
          ..add(
            ApplyHiddenIndexDelta(
              library,
              newlyHidden: const [],
              newlyVisible: library.books,
              visibilityRevision: revision,
              onCompleted: completions.add,
            ),
          )
          ..add(IndexingWorkBarrier(onSettled: settled.complete));
        final gate = repository.runGate ?? repository.statusGate;
        if (gate != null) {
          await pumpEventQueue();
          expect(repository.runs, hasLength(1));
          if (repository.statusGate != null) {
            expect(repository.statusChecks, 1);
          }
          bloc.add(CancelIndexing());
          await pumpEventQueue();
          gate.complete();
        }
        await settled.future.timeout(const Duration(seconds: 2));

        expect(completions, [false]);
        expect(store.hasPendingVisibilityIndex, isTrue);
        if (gate != null) expect(bloc.state, isA<IndexingStopped>());
      });
    }

    test('שתי פעולות ברצף מנקות marker רק בסיום האחרונה', () async {
      final first = await store.beginVisibilityIndexUpdate();
      final second = await store.beginVisibilityIndexUpdate();
      await store.completeVisibilityIndexUpdate(first, true);
      expect(store.hasPendingVisibilityIndex, isTrue);
      await store.completeVisibilityIndexUpdate(second, true);
      expect(store.hasPendingVisibilityIndex, isFalse);
    });

    test('התאמת startup אינה מנקה marker של שמירה שעדיין בתהליך', () async {
      final revision = await store.beginVisibilityIndexUpdate();
      await store.clearPendingVisibilityIndex(revision);
      expect(store.hasPendingVisibilityIndex, isTrue);
      await store.completeVisibilityIndexUpdate(revision, true);
      expect(store.hasPendingVisibilityIndex, isFalse);
    });

    test('כשל מוקדם משאיר marker גם אחרי פעולה מאוחרת מוצלחת', () async {
      final first = await store.beginVisibilityIndexUpdate();
      final second = await store.beginVisibilityIndexUpdate();
      await store.completeVisibilityIndexUpdate(first, false);
      await store.completeVisibilityIndexUpdate(second, true);
      expect(store.hasPendingVisibilityIndex, isTrue);
      await store.clearPendingVisibilityIndex(store.visibilityRevision);
    });

    test('השלמת delta אינה מנקה marker של שחזור גיבוי', () async {
      await store.markIndexReconciliationPending();
      final revision = await store.beginVisibilityIndexUpdate();
      await store.completeVisibilityIndexUpdate(revision, true);
      expect(store.hasPendingVisibilityIndex, isFalse);
      expect(store.hasPendingIndexReconciliation, isTrue);
      await store.clearPendingIndexReconciliation();
    });

    blocTest<IndexingBloc, IndexingState>(
      'התאמה בעלייה מנקה visibility marker רק אחרי אינדוקס נקי',
      setUp: () async {
        await store.beginVisibilityIndexUpdate();
        await store.resetRuntimeStateForAppRestart();
      },
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(
        ReconcileHiddenIndex(
          libraryWithBooks(),
          indexVisible: true,
          clearVisibilityMarker: true,
          visibilityRevision: store.visibilityRevision,
        ),
      ),
      verify: (_) => expect(store.hasPendingVisibilityIndex, isFalse),
    );

    blocTest<IndexingBloc, IndexingState>(
      'התאמה שנכשלה משאירה visibility marker לפתיחה הבאה',
      setUp: () async {
        await store.beginVisibilityIndexUpdate();
        await store.resetRuntimeStateForAppRestart();
      },
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..error = StateError('index failed'),
      ),
      act: (bloc) => bloc.add(
        ReconcileHiddenIndex(
          libraryWithBooks(),
          indexVisible: true,
          clearVisibilityMarker: true,
          visibilityRevision: store.visibilityRevision,
        ),
      ),
      verify: (_) => expect(store.hasPendingVisibilityIndex, isTrue),
    );
  });

  group('עבודות אינדוקס נוספות', () {
    for (final throwsError in [false, true]) {
      final completions = <bool>[];
      blocTest<IndexingBloc, IndexingState>(
        'תוצאת הסרת ספר מוסתר מדווחת אחרי כשל ${throwsError ? 'throw' : 'false'}',
        setUp: () => const HiddenLibraryStore().clearPendingVisibilityIndex(
          const HiddenLibraryStore().visibilityRevision,
        ),
        build: () => _FakeIndexingBloc(
          _FakeIndexingRepository()
            ..dropBookSucceeded = false
            ..dropBookThrows = throwsError,
        ),
        act: (bloc) {
          final library = libraryWithBooks();
          bloc.add(
            ApplyHiddenIndexDelta(
              library,
              newlyHidden: library.books,
              newlyVisible: const [],
              onCompleted: completions.add,
            ),
          );
        },
        expect: () => [isA<IndexingError>()],
        verify: (_) {
          expect(completions, [false]);
          expect(
            const HiddenLibraryStore().hasPendingVisibilityIndex,
            isTrue,
          );
        },
      );
    }

    blocTest<IndexingBloc, IndexingState>(
      'ריצה על ספרים מסוימים מפיצה כשל מפורט',
      build: () {
        final repository = _FakeIndexingRepository()
          ..result = const IndexingRunResult.completed(
            processedBooks: 1,
            totalBooks: 1,
            indexedBooks: 0,
            failures: [failure],
          );
        return _FakeIndexingBloc(repository);
      },
      act: (bloc) {
        final library = libraryWithBooks();
        bloc.add(RunIndexing(library, books: library.books));
      },
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 1,
          isCreatingIndex: false,
        ),
        const IndexingComplete(failures: [failure]),
      ],
      verify: (bloc) {
        expect(repositoryOf(bloc).indexBooksCalls, 1);
        expect(repositoryOf(bloc).reportedResults, hasLength(1));
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'ריצת רענון מעבירה ספרים חדשים, שהשתנו ובדיקה בקריאה אחת',
      build: _FakeIndexingBloc.new,
      act: (bloc) {
        final library = libraryWithBooks(3);
        repositoryOf(bloc)
          ..indexedBooks.add(library.books[2])
          ..result = const IndexingRunResult.completed(
            processedBooks: 2,
            totalBooks: 2,
            indexedBooks: 2,
          );
        bloc.add(
          RunIndexing(
            library,
            books: [library.books[0]],
            changedBooks: [library.books[1]],
            check: IndexCheckScope.books([library.books[2]]),
          ),
        );
      },
      expect: () => [
        const IndexingInProgress(booksProcessed: 0, totalBooks: 2),
        const IndexingInProgress(booksProcessed: 2, totalBooks: 2),
        const IndexingComplete(),
      ],
      verify: (bloc) {
        final run = repositoryOf(bloc).runs.single;
        expect(run.books!.map((b) => b.title), ['ספר 0']);
        expect(run.changedBooks.map((b) => b.title), ['ספר 1']);
        expect(run.check.books.map((b) => b.title), ['ספר 2']);
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'שלב הבדיקה נפלט עם isScanning, ואחריו רשימת העבודה בלבד',
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..scanProgressReports = [(0, 5), (5, 5)],
      ),
      act: (bloc) => bloc.add(
        RunIndexing(libraryWithBooks(2), check: IndexCheckScope.library),
      ),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 5,
          isScanning: true,
        ),
        const IndexingInProgress(
          booksProcessed: 5,
          totalBooks: 5,
          isScanning: true,
        ),
        const IndexingInProgress(booksProcessed: 0, totalBooks: 2),
        const IndexingComplete(),
      ],
    );

    blocTest<IndexingBloc, IndexingState>(
      'עדכון סדר הספרים עובר למאגר בלי פליטת מצב',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(SyncBookOrder(libraryWithBooks(2))),
      expect: () => <IndexingState>[],
      verify: (bloc) =>
          expect(repositoryOf(bloc).syncedOrders.single.books, hasLength(2)),
    );

    blocTest<IndexingBloc, IndexingState>(
      'ריצה בלי עבודה אינה פולטת InProgress',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(
        RunIndexing(Library(categories: []), books: const []),
      ),
      expect: () => [const IndexingComplete()],
    );
  });

  group('בקרה ומצב', () {
    blocTest<IndexingBloc, IndexingState>(
      'CancelIndexing מבטל ב-repository ומציג מצב עצירה מפורש',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(CancelIndexing()),
      expect: () => [isA<IndexingStopped>()],
      verify: (bloc) => expect(repositoryOf(bloc).cancelCalls, 1),
    );

    test(
      'דחיית שינויים ממתינה לריצה פעילה ואינה מתחילה אינדוקס נוסף',
      () async {
        final repository = _FakeIndexingRepository()
          ..runGate = Completer<void>();
        final bloc = _FakeIndexingBloc(repository);
        addTearDown(bloc.close);
        final library = libraryWithBooks(2);
        final changed = [library.books.first];
        final settled = Completer<void>();
        bloc
          ..add(StartIndexing(library))
          ..add(
            DeferIndexing(library, changedBooks: changed, checkLibrary: true),
          )
          ..add(IndexingWorkBarrier(onSettled: settled.complete));
        await pumpEventQueue();

        expect(repository.runs, hasLength(1));
        expect(repository.rememberedChanged, isEmpty);
        expect(settled.isCompleted, isFalse);
        repository.runGate!.complete();
        await settled.future.timeout(const Duration(seconds: 2));

        expect(repository.runs, hasLength(1));
        expect(repository.rememberedChanged, changed);
        expect(repository.rememberedLibraryCheck, isTrue);
        expect(bloc.state, isA<IndexingInitial>());
      },
    );

    test('ביטול מנקז ריצות שבתור, ושומר את מה שהיו מחליפות ובודקות', () async {
      final repository = _FakeIndexingRepository()..runGate = Completer<void>();
      final bloc = _FakeIndexingBloc(repository);
      final library = libraryWithBooks(2);
      final changed = [library.books.first];
      final checked = [library.books.last];
      final settled = Completer<void>();
      bloc.add(StartIndexing(library));
      bloc.add(
        RunIndexing(
          library,
          books: const [],
          changedBooks: changed,
          check: IndexCheckScope.books(checked),
        ),
      );
      bloc.add(RunIndexing(library, check: IndexCheckScope.library));
      bloc.add(IndexingWorkBarrier(onSettled: settled.complete));
      await Future<void>.delayed(Duration.zero);
      expect(repository.runs, hasLength(1));

      bloc.add(CancelIndexing());
      await Future<void>.delayed(Duration.zero);
      repository.runGate!.complete();
      await settled.future.timeout(const Duration(seconds: 2));

      expect(repository.runs, hasLength(1));
      // ספר שנשלח לבדיקה נזכר כשונה, ובקשת הבדיקה המלאה נדחית לריצה הבאה.
      expect(repository.rememberedChanged, [...changed, ...checked]);
      expect(repository.rememberedLibraryCheck, isTrue);

      // ריצה שנשלחה אחרי הביטול רצה כרגיל.
      final after = Completer<void>();
      bloc.add(StartIndexing(library, onSettled: after.complete));
      await after.future.timeout(const Duration(seconds: 2));
      expect(repository.runs, hasLength(2));
      await bloc.close();
    });

    test('ביטול מנקז גם בקשות איפוס ובנייה שכבר בתור', () async {
      final repository = _FakeIndexingRepository()..runGate = Completer<void>();
      final bloc = _FakeIndexingBloc(repository);
      final library = libraryWithBooks();
      final settled = Completer<void>();
      bloc
        ..add(ResetAndIndex(library))
        ..add(ResetAndIndex(library))
        ..add(IndexingWorkBarrier(onSettled: settled.complete));
      await pumpEventQueue();
      expect(repository.runs, hasLength(1));

      bloc.add(CancelIndexing());
      await pumpEventQueue();
      repository.runGate!.complete();
      await settled.future.timeout(const Duration(seconds: 2));
      expect(repository.runs, hasLength(1));

      final afterCancel = Completer<void>();
      bloc
        ..add(ResetAndIndex(library))
        ..add(IndexingWorkBarrier(onSettled: afterCancel.complete));
      await afterCancel.future.timeout(const Duration(seconds: 2));
      expect(repository.runs, hasLength(2));
      await bloc.close();
    });

    for (final duringClear in [false, true]) {
      test(
        'ביטול בזמן ${duringClear ? 'מחיקת האינדקס' : 'בדיקת התאימות'} עוצר את הבנייה',
        () async {
          final gate = Completer<void>();
          final repository = _FakeIndexingRepository()..manualReindex = true;
          if (duringClear) {
            repository.clearGate = gate;
          } else {
            repository.compatibilityGate = gate;
          }
          final bloc = _FakeIndexingBloc(repository);
          final settled = Completer<void>();
          bloc
            ..add(ResetAndIndex(libraryWithBooks()))
            ..add(IndexingWorkBarrier(onSettled: settled.complete));
          await pumpEventQueue();
          expect(repository.clearCalls, duringClear ? 1 : 0);

          bloc.add(CancelIndexing());
          await pumpEventQueue();
          gate.complete();
          await settled.future.timeout(const Duration(seconds: 2));
          expect(repository.runs, isEmpty);
          expect(repository.clearCalls, duringClear ? 1 : 0);
          expect(bloc.state, isA<IndexingStopped>());
          await bloc.close();
        },
      );
    }

    blocTest<IndexingBloc, IndexingState>(
      'ClearIndex מנקה ומחזיר למצב התחלתי',
      seed: () => IndexingStopped(),
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(ClearIndex()),
      expect: () => [isA<IndexingInitial>()],
      verify: (bloc) => expect(repositoryOf(bloc).clearCalls, 1),
    );

    // אינדוקס שמתחיל לפני שהמחיקה הסתיימה כותב לאינדקס שעומד להימחק.
    blocTest<IndexingBloc, IndexingState>(
      'ResetAndIndex מוחק את האינדקס ורק אחריו מאנדקס את כל הספרייה',
      build: () =>
          _FakeIndexingBloc(_FakeIndexingRepository()..manualReindex = true),
      act: (bloc) => bloc.add(ResetAndIndex(libraryWithBooks())),
      verify: (bloc) {
        final repository = repositoryOf(bloc);
        expect(repository.clearCalls, 1);
        expect(repository.runsAtClear, 0);
        expect(repository.indexAllCalls, 1);
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'ResetAndIndex על אינדקס שכבר תקין אינו מוחק אותו',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(ResetAndIndex(libraryWithBooks())),
      verify: (bloc) {
        expect(repositoryOf(bloc).clearCalls, 0);
        expect(repositoryOf(bloc).indexAllCalls, 1);
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'בדיקת מצב מחזירה complete כשכל הספרים מאונדקסים',
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..allBooksIndexed = true,
      ),
      act: (bloc) => bloc.add(CheckIndexStatus(libraryWithBooks(2))),
      expect: () => [const IndexingComplete()],
      verify: (bloc) => expect(repositoryOf(bloc).awaitReadyCalls, 1),
    );

    blocTest<IndexingBloc, IndexingState>(
      'בדיקת מצב אינה מכריזה complete כשחסר ספר',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(CheckIndexStatus(libraryWithBooks())),
      expect: () => [isA<IndexingInitial>()],
      verify: (bloc) => expect(repositoryOf(bloc).awaitReadyCalls, 1),
    );

    blocTest<IndexingBloc, IndexingState>(
      'דרישת reindex ידני גוברת על רשומות האינדקס',
      seed: () => const IndexingComplete(),
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()
          ..allBooksIndexed = true
          ..manualReindex = true,
      ),
      act: (bloc) => bloc.add(CheckIndexStatus(libraryWithBooks())),
      expect: () => [isA<IndexingInitial>()],
    );

    blocTest<IndexingBloc, IndexingState>(
      'ספרייה בלי ספרים אינדקסביליים נחשבת שלמה',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(CheckIndexStatus(Library(categories: []))),
      expect: () => [const IndexingComplete()],
    );
  });

  group('השהיה ומצב חסכוני', () {
    const inProgress = IndexingInProgress(
      booksProcessed: 3,
      totalBooks: 10,
      isCreatingIndex: true,
    );

    blocTest<IndexingBloc, IndexingState>(
      'PauseIndexing משהה את ה-repository ומסמן isPaused ב-state',
      seed: () => inProgress,
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(PauseIndexing()),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 3,
          totalBooks: 10,
          isCreatingIndex: true,
          isPaused: true,
        ),
      ],
      verify: (bloc) => expect(repositoryOf(bloc).pauseCalls, 1),
    );

    blocTest<IndexingBloc, IndexingState>(
      'PauseIndexing מחוץ לריצה אינו עושה דבר',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(PauseIndexing()),
      expect: () => <IndexingState>[],
      verify: (bloc) => expect(repositoryOf(bloc).pauseCalls, 0),
    );

    blocTest<IndexingBloc, IndexingState>(
      'ResumeIndexing אחרי השהיה מחזיר לריצה ומנקה את הדגל',
      seed: () => inProgress,
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc
        ..add(PauseIndexing())
        ..add(ResumeIndexing()),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 3,
          totalBooks: 10,
          isCreatingIndex: true,
          isPaused: true,
        ),
        const IndexingInProgress(
          booksProcessed: 3,
          totalBooks: 10,
          isCreatingIndex: true,
        ),
      ],
      verify: (bloc) => expect(repositoryOf(bloc).resumeCalls, 1),
    );

    blocTest<IndexingBloc, IndexingState>(
      'BLoC חדש מכבד את הבחירה שנשמרה ב-repository',
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..isEconomyIndexing = true,
      ),
      act: (bloc) => bloc.add(StartIndexing(libraryWithBooks(2))),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isCreatingIndex: false,
          isEconomy: true,
        ),
        const IndexingComplete(),
      ],
    );

    blocTest<IndexingBloc, IndexingState>(
      'SetEconomyIndexing מעביר את הדגל ל-repository ומשתקף ב-state',
      seed: () => inProgress,
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(const SetEconomyIndexing(true)),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 3,
          totalBooks: 10,
          isCreatingIndex: true,
          isEconomy: true,
        ),
      ],
      verify: (bloc) => expect(repositoryOf(bloc).economyValues, [true]),
    );

    blocTest<IndexingBloc, IndexingState>(
      'SetEconomyIndexing באותו ערך אינו פולט state כפול',
      seed: () => inProgress,
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc
        ..add(const SetEconomyIndexing(true))
        ..add(const SetEconomyIndexing(true)),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 3,
          totalBooks: 10,
          isCreatingIndex: true,
          isEconomy: true,
        ),
      ],
      verify: (bloc) => expect(repositoryOf(bloc).economyValues, [true]),
    );

    blocTest<IndexingBloc, IndexingState>(
      'כשל בהחלפת המנוע אינו משנה את המצב המוצג',
      seed: () => inProgress,
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..economyError = StateError('engine failed'),
      ),
      act: (bloc) => bloc.add(const SetEconomyIndexing(true)),
      expect: () => <IndexingState>[],
      verify: (bloc) => expect(repositoryOf(bloc).economyValues, [true]),
    );

    test('בקשות מצב חסכוני ממתינות לקודמת להן', () async {
      final gate = Completer<void>();
      final repository = _FakeIndexingRepository()..economyGate = gate;
      final bloc = _FakeIndexingBloc(repository);

      bloc
        ..add(const SetEconomyIndexing(true))
        ..add(const SetEconomyIndexing(false));
      await Future<void>.delayed(Duration.zero);
      expect(repository.economyValues, [true]);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.economyValues, [true, false]);
      await bloc.close();
    });

    blocTest<IndexingBloc, IndexingState>(
      'המצב החסכוני מחוץ לריצה נשמר ומשתקף בריצה הבאה',
      build: _FakeIndexingBloc.new,
      act: (bloc) async {
        bloc.add(const SetEconomyIndexing(true));
        await Future<void>.delayed(Duration.zero);
        bloc.add(StartIndexing(libraryWithBooks(2)));
      },
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isCreatingIndex: false,
          isEconomy: true,
        ),
        const IndexingComplete(),
      ],
      verify: (bloc) => expect(repositoryOf(bloc).economyValues, [true]),
    );

    blocTest<IndexingBloc, IndexingState>(
      'ריצה חדשה אחרי השהיה מתחילה ללא השהיה',
      seed: () => inProgress,
      build: _FakeIndexingBloc.new,
      act: (bloc) async {
        bloc.add(PauseIndexing());
        await Future<void>.delayed(Duration.zero);
        bloc.add(StartIndexing(libraryWithBooks(2)));
      },
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 3,
          totalBooks: 10,
          isCreatingIndex: true,
          isPaused: true,
        ),
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isCreatingIndex: false,
        ),
        const IndexingComplete(),
      ],
      verify: (bloc) => expect(repositoryOf(bloc).resumeCalls, 1),
    );
  });
}

class _FakeIndexingBloc extends IndexingBloc {
  _FakeIndexingBloc([_FakeIndexingRepository? repository])
    : this._(repository ?? _FakeIndexingRepository());

  _FakeIndexingBloc._(this.repository)
    : super(
        repository,
        reportFailures: (result, _) => repository.reportedResults.add(result),
      );

  final _FakeIndexingRepository repository;
}

class _FakeIndexingRepository extends IndexingRepository {
  _FakeIndexingRepository() : super(_UnusedTantivyDataProvider());

  IndexingRunResult result = const IndexingRunResult.completed(
    processedBooks: 1,
    totalBooks: 1,
    indexedBooks: 1,
  );
  Object? error;
  bool allBooksIndexed = false;
  final indexedBooks = <Book>{};
  bool manualReindex = false;
  Completer<void>? compatibilityGate;
  Completer<void>? statusGate;
  int statusChecks = 0;
  Completer<void>? clearGate;
  final reportedResults = <IndexingRunResult>[];
  final runs =
      <({List<Book>? books, List<Book> changedBooks, IndexCheckScope check})>[];
  int get indexAllCalls => runs.where((run) => run.books == null).length;
  int get indexBooksCalls => runs.where((run) => run.books != null).length;
  final rememberedChanged = <Book>[];
  bool rememberedLibraryCheck = false;

  /// כשהוא מסופק — כל ריצה ממתינה לו לפני שהיא מתחילה.
  Completer<void>? runGate;
  int dropOrphanedCalls = 0;
  int dropHiddenCalls = 0;
  bool dropHiddenSucceeded = true;
  bool dropBookSucceeded = true;
  bool dropBookThrows = false;
  int cancelCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  @override
  bool isEconomyIndexing = false;
  final economyValues = <bool>[];
  Object? economyError;
  Completer<void>? economyGate;

  /// כשהוא מסופק — הריצה מדווחת על שלב האיחוד ונעצרת בו עד לשחרור.
  Completer<void>? finalizeGate;

  /// דיווחי onScanProgress ששלב הבדיקה יפלוט לפני הסיום.
  List<(int, int)> scanProgressReports = const [];
  int clearCalls = 0;

  /// מספר הריצות שכבר התחילו ברגע המחיקה האחרונה.
  int? runsAtClear;
  int awaitReadyCalls = 0;

  Future<IndexingRunResult> _finish(
    void Function(int processed, int total) onProgress,
    int workCount,
  ) async {
    final thrown = error;
    if (thrown != null) throw thrown;
    if (workCount > 0) onProgress(result.processedBooks, result.totalBooks);
    return result;
  }

  @override
  Future<IndexingRunResult> runIndexing(
    Library library, {
    List<Book>? books,
    List<Book> changedBooks = const [],
    IndexCheckScope check = IndexCheckScope.none,
    bool includePdfBooks = true,
    void Function(int processed, int total)? onScanProgress,
    void Function(int total)? onWorkListReady,
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
    void Function()? onFinalizing,
  }) async {
    runs.add((books: books, changedBooks: changedBooks, check: check));
    final gateBeforeRun = runGate;
    if (gateBeforeRun != null) await gateBeforeRun.future;
    for (final (processed, total) in scanProgressReports) {
      onScanProgress?.call(processed, total);
    }
    final total = allBooksIndexed
        ? 0
        : (books ?? library.getIndexableBooks()).length + changedBooks.length;
    if (total > 0) onWorkListReady?.call(total);
    final gate = finalizeGate;
    final IndexingRunResult runResult;
    if (gate != null) {
      onFinalizing?.call();
      await gate.future;
      runResult = result;
    } else {
      runResult = await _finish(onProgress, total);
    }
    if (runResult.isClean) {
      indexedBooks.addAll([
        ...(books ?? library.getIndexableBooks()),
        ...changedBooks,
      ]);
    }
    return runResult;
  }

  final syncedOrders = <Library>[];

  @override
  Future<void> syncBookOrder(Library library) async =>
      syncedOrders.add(library);

  @override
  Future<void> rememberChangedBooks(
    List<Book> books, {
    bool checkLibrary = false,
  }) async {
    rememberedChanged.addAll(books);
    rememberedLibraryCheck |= checkLibrary;
  }

  @override
  Future<int> dropOrphanedIndexEntries(
    Library library, {
    List<CustomFolder>? customFolders,
    Set<String>? preservedHiddenUserBookKeys,
    List<AttachedLibrary>? attachedLibraries,
    String? libraryRoot,
  }) async {
    dropOrphanedCalls++;
    return 0;
  }

  @override
  Future<bool> dropHiddenIndexEntries(Library library) async {
    dropHiddenCalls++;
    return dropHiddenSucceeded;
  }

  @override
  Future<bool> dropBookIndexEntries(Iterable<Book> books) async {
    if (dropBookThrows) throw StateError('drop failed');
    return dropBookSucceeded;
  }

  @override
  Future<void> awaitReady() async {
    awaitReadyCalls++;
  }

  @override
  Future<bool> requiresManualReindex(Library library) async {
    await compatibilityGate?.future;
    return manualReindex;
  }

  @override
  bool isBookIndexed(Book book) =>
      allBooksIndexed || indexedBooks.contains(book);

  @override
  Future<bool> hasUnindexedBooks(Library library) async {
    statusChecks++;
    await statusGate?.future;
    return rememberedLibraryCheck ||
        rememberedChanged.isNotEmpty ||
        library.getIndexableBooks().any((book) => !isBookIndexed(book));
  }

  @override
  bool isIndexing() => true;

  @override
  void cancelIndexing() {
    cancelCalls++;
  }

  @override
  void pauseIndexing() {
    pauseCalls++;
    super.pauseIndexing();
  }

  @override
  void resumeIndexing() {
    resumeCalls++;
    super.resumeIndexing();
  }

  @override
  Future<void> setEconomyIndexing(bool enabled) async {
    economyValues.add(enabled);
    await economyGate?.future;
    final error = economyError;
    if (error != null) throw error;
    isEconomyIndexing = enabled;
  }

  @override
  Future<bool> clearIndex() async {
    clearCalls++;
    await clearGate?.future;
    runsAtClear = runs.length;
    manualReindex = false;
    indexedBooks.clear();
    return true;
  }
}

class _UnusedTantivyDataProvider implements TantivyDataProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected provider call: $invocation');
  }
}
