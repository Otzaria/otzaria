import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  setUp(() => WindowRole.isSecondary = false);
  tearDown(() => WindowRole.isSecondary = false);

  group('StartIndexing', () {
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
      'התקדמות האיחוד נפלטת כשבר על גבי מצב האיחוד',
      build: () {
        final repository = _FakeIndexingRepository()
          ..finalizeGate = Completer<void>()
          ..finalizeFractions = const [0.25, 0.75];
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
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isFinalizing: true,
          finalizingProgress: 0.25,
        ),
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isFinalizing: true,
          finalizingProgress: 0.75,
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
      'ספרייה ריקה נשארת במצב התחלתי ואינה קוראת ל-repository',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(StartIndexing(Library(categories: []))),
      expect: () => [isA<IndexingInitial>()],
      verify: (bloc) => expect(repositoryOf(bloc).indexAllCalls, 0),
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

  group('חלון משני', () {
    setUp(() => WindowRole.isSecondary = true);

    blocTest<IndexingBloc, IndexingState>(
      'אינדוקס מלא אינו מגיע למאגר',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(StartIndexing(libraryWithBooks())),
      verify: (bloc) => expect(repositoryOf(bloc).indexAllCalls, 0),
    );

    blocTest<IndexingBloc, IndexingState>(
      'אינדוקס ספרים חדשים אינו מגיע למאגר',
      build: _FakeIndexingBloc.new,
      act: (bloc) {
        final library = libraryWithBooks();
        bloc.add(IndexSpecificBooks(library.books, library));
      },
      verify: (bloc) => expect(repositoryOf(bloc).indexBooksCalls, 0),
    );

    blocTest<IndexingBloc, IndexingState>(
      'אינדוקס ספרים שהשתנו אינו מגיע למאגר',
      build: _FakeIndexingBloc.new,
      act: (bloc) {
        final library = libraryWithBooks();
        bloc.add(ReindexChangedBooks(library.books, library));
      },
      verify: (bloc) => expect(repositoryOf(bloc).reindexCalls, 0),
    );

    blocTest<IndexingBloc, IndexingState>(
      'התאמת האינדקס אינה מגיעה למאגר',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(ReconcileIndex(libraryWithBooks())),
      verify: (bloc) => expect(repositoryOf(bloc).reconcileCalls, 0),
    );

    blocTest<IndexingBloc, IndexingState>(
      'ניקוי רשומות יתומות אינו מגיע למאגר',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(DropOrphanedIndexEntries(libraryWithBooks())),
      verify: (bloc) => expect(repositoryOf(bloc).dropOrphanedCalls, 0),
    );

    blocTest<IndexingBloc, IndexingState>(
      'איפוס האינדקס אינו מגיע למאגר',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(ClearIndex()),
      verify: (bloc) => expect(repositoryOf(bloc).clearCalls, 0),
    );
  });

  group('עבודות אינדוקס נוספות', () {
    blocTest<IndexingBloc, IndexingState>(
      'IndexSpecificBooks מפיץ כשל מפורט',
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
        bloc.add(IndexSpecificBooks(library.books, library));
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
      'ReindexChangedBooks משתמש במסלול reindex ולא במסלול ספרים חדשים',
      build: _FakeIndexingBloc.new,
      act: (bloc) {
        final library = libraryWithBooks();
        bloc.add(ReindexChangedBooks(library.books, library));
      },
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 1,
          isCreatingIndex: false,
        ),
        const IndexingComplete(),
      ],
      verify: (bloc) {
        expect(repositoryOf(bloc).reindexCalls, 1);
        expect(repositoryOf(bloc).indexBooksCalls, 0);
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'ReconcileIndex מעביר כשל לדוח ולמצב הסופי',
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
      act: (bloc) => bloc.add(ReconcileIndex(libraryWithBooks())),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 1,
          isCreatingIndex: false,
          isScanning: true,
        ),
        const IndexingComplete(failures: [failure]),
      ],
      verify: (bloc) {
        expect(repositoryOf(bloc).reconcileCalls, 1);
        expect(repositoryOf(bloc).reportedResults, hasLength(1));
      },
    );

    blocTest<IndexingBloc, IndexingState>(
      'שלב הסריקה של ReconcileIndex נפלט עם isScanning להצגה בחיווי',
      build: () => _FakeIndexingBloc(
        _FakeIndexingRepository()..scanProgressReports = [(1, 2), (2, 2)],
      ),
      act: (bloc) => bloc.add(ReconcileIndex(libraryWithBooks(2))),
      expect: () => [
        const IndexingInProgress(
          booksProcessed: 0,
          totalBooks: 2,
          isScanning: true,
        ),
        const IndexingInProgress(
          booksProcessed: 1,
          totalBooks: 2,
          isScanning: true,
        ),
        const IndexingInProgress(
          booksProcessed: 2,
          totalBooks: 2,
          isScanning: true,
        ),
        const IndexingComplete(),
      ],
    );

    blocTest<IndexingBloc, IndexingState>(
      'רשימת ספרים ריקה אינה מתחילה עבודה',
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(
        IndexSpecificBooks(const [], Library(categories: [])),
      ),
      expect: () => <IndexingState>[],
      verify: (bloc) => expect(repositoryOf(bloc).indexBooksCalls, 0),
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

    blocTest<IndexingBloc, IndexingState>(
      'ClearIndex מנקה ומחזיר למצב התחלתי',
      seed: () => IndexingStopped(),
      build: _FakeIndexingBloc.new,
      act: (bloc) => bloc.add(ClearIndex()),
      expect: () => [isA<IndexingInitial>()],
      verify: (bloc) => expect(repositoryOf(bloc).clearCalls, 1),
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
  bool manualReindex = false;
  final reportedResults = <IndexingRunResult>[];
  int indexAllCalls = 0;
  int indexBooksCalls = 0;
  int reindexCalls = 0;
  int reconcileCalls = 0;
  int dropOrphanedCalls = 0;
  int cancelCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  final economyValues = <bool>[];
  Object? economyError;
  Completer<void>? economyGate;

  /// כשהוא מסופק — הריצה מדווחת על שלב האיחוד ונעצרת בו עד לשחרור.
  Completer<void>? finalizeGate;
  List<double> finalizeFractions = const [];

  /// דיווחי onScanProgress שהסריקה ב-reconcile תפלוט לפני הסיום.
  List<(int, int)> scanProgressReports = const [];
  int clearCalls = 0;
  int awaitReadyCalls = 0;

  Future<IndexingRunResult> _finish(
    void Function(int processed, int total) onProgress,
  ) async {
    final thrown = error;
    if (thrown != null) throw thrown;
    onProgress(result.processedBooks, result.totalBooks);
    return result;
  }

  @override
  Future<IndexingRunResult> indexAllBooks(
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
    void Function()? onFinalizing,
    void Function(double fraction)? onFinalizingProgress,
    bool includePdfBooks = true,
  }) async {
    indexAllCalls++;
    final gate = finalizeGate;
    if (gate != null) {
      onFinalizing?.call();
      for (final fraction in finalizeFractions) {
        onFinalizingProgress?.call(fraction);
      }
      await gate.future;
      return result;
    }
    return _finish(onProgress);
  }

  @override
  Future<IndexingRunResult> indexBooks(
    List<Book> books,
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
  }) {
    indexBooksCalls++;
    return _finish(onProgress);
  }

  @override
  Future<IndexingRunResult> reindexChangedBooks(
    List<Book> changedBooks,
    Library library, {
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
  }) {
    reindexCalls++;
    return _finish(onProgress);
  }

  @override
  Future<IndexingRunResult> reconcileIndexWithLibrary(
    Library library, {
    void Function(int processed, int total)? onScanProgress,
    void Function()? onActualIndexingStarted,
    required void Function(int processed, int total) onProgress,
    Future<String?> Function(TextBook book)? loadText,
    Future<BigInt> Function(TextBook book, String text)? fingerprintOf,
  }) {
    reconcileCalls++;
    for (final (processed, total) in scanProgressReports) {
      onScanProgress?.call(processed, total);
    }
    return _finish(onProgress);
  }

  @override
  Future<int> dropOrphanedIndexEntries(Library library) async {
    dropOrphanedCalls++;
    return 0;
  }

  @override
  Future<void> awaitReady() async {
    awaitReadyCalls++;
  }

  @override
  Future<bool> requiresManualReindex(Library library) async => manualReindex;

  @override
  bool isBookIndexed(Book book) => allBooksIndexed;

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
  }

  @override
  Future<bool> clearIndex() async {
    clearCalls++;
    return true;
  }
}

class _UnusedTantivyDataProvider implements TantivyDataProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected provider call: $invocation');
  }
}
