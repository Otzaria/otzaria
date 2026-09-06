import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/indexing/services/indexing_failure_reporter.dart';
import 'package:otzaria/indexing/services/indexing_wakelock.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

class IndexingBloc extends Bloc<IndexingEvent, IndexingState> {
  final IndexingRepository _repository;
  final void Function(IndexingRunResult result, Duration elapsed)
  _reportFailures;
  int _nextWorkId = 0;
  int? _activeWorkId;
  bool _isPaused = false;
  bool _isEconomy = false;
  bool _isFinalizing = false;
  double? _finalizingProgress;

  IndexingBloc(
    this._repository, {
    void Function(IndexingRunResult result, Duration elapsed)? reportFailures,
  }) : _reportFailures = reportFailures ?? IndexingFailureReporter.write,
       super(IndexingInitial()) {
    on<IndexingWorkEvent>(_onIndexingWork, transformer: sequential());
    on<CheckIndexStatus>(_onCheckIndexStatus);
    on<CancelIndexing>(_onCancelIndexing);
    on<PauseIndexing>(_onPauseIndexing);
    on<ResumeIndexing>(_onResumeIndexing);
    on<SetEconomyIndexing>(_onSetEconomyIndexing, transformer: sequential());
    on<ActualIndexingStarted>(_onActualIndexingStarted);
    on<IndexingFinalizing>(_onFinalizing);
    on<IndexingFinalizeProgress>(_onFinalizeProgress);
    on<UpdateIndexingProgress>(_onUpdateProgress);
    on<ClearIndex>(_onEraseIndex);
  }

  /// Factory constructor that creates an IndexingBloc with a default repository
  factory IndexingBloc.create() {
    IndexingWakelock.instance.attach(TantivyDataProvider.instance.isIndexing);
    return IndexingBloc(
      IndexingRepository(TantivyDataProvider.instance),
    );
  }

  /// כל מצבי ההתקדמות נפלטים דרך כאן כדי שדגלי ההשהיה והמצב החסכוני
  /// יישמרו על פני כל עדכון התקדמות.
  IndexingInProgress _inProgress({
    int? booksProcessed,
    int? totalBooks,
    bool isCreatingIndex = false,
    bool isScanning = false,
  }) => IndexingInProgress(
    booksProcessed: booksProcessed,
    totalBooks: totalBooks,
    isCreatingIndex: isCreatingIndex,
    isScanning: isScanning,
    isPaused: _isPaused,
    isEconomy: _isEconomy,
    isFinalizing: _isFinalizing,
    finalizingProgress: _finalizingProgress,
  );

  Future<void> _onIndexingWork(
    IndexingWorkEvent event,
    Emitter<IndexingState> emit,
  ) async {
    if (_rejectIndexMutationInSecondaryWindow(emit)) return;

    _isFinalizing = false;
    _finalizingProgress = null;
    // ריצה חדשה מתחילה ללא השהיה; המצב החסכוני נשמר בין ריצות.
    if (_isPaused) {
      _isPaused = false;
      _repository.resumeIndexing();
    }

    if (event is StartIndexing) {
      await _onStartIndexing(event, emit);
      return;
    }

    if (event is IndexSpecificBooks) {
      await _onBooksWork(event.books, event.library, emit, reindex: false);
      return;
    }

    if (event is ReindexChangedBooks) {
      await _onBooksWork(event.books, event.library, emit, reindex: true);
      return;
    }

    if (event is ReconcileIndex) {
      await _onReconcileIndex(event, emit);
      return;
    }

    if (event is DropOrphanedIndexEntries) {
      // עבודת רקע שקטה — בלי מצבי התקדמות; כשל אינו קריטי (ינוקה ברענון הבא).
      try {
        await _repository.dropOrphanedIndexEntries(event.library);
      } catch (e) {
        debugPrint('⚠️ ניקוי רשומות יתומות מהאינדקס נכשל: $e');
      }
    }
  }

  /// Handles the ReconcileIndex event — סריקת התאמה בין האינדקס לספרייה,
  /// ואינדוקס מחדש של הספרים שנמצאו שונים.
  Future<void> _onReconcileIndex(
    ReconcileIndex event,
    Emitter<IndexingState> emit,
  ) async {
    final workId = ++_nextWorkId;
    final runClock = Stopwatch()..start();
    _activeWorkId = workId;

    final totalCandidates = event.library
        .getAllBooks()
        .where((b) => IndexingRepository.isIndexableBook(b))
        .length;
    if (totalCandidates == 0) {
      _activeWorkId = null;
      return;
    }

    emit(
      _inProgress(
        booksProcessed: 0,
        totalBooks: totalCandidates,
        isScanning: true,
      ),
    );

    try {
      final result = await _repository.reconcileIndexWithLibrary(
        event.library,
        // שלב הסריקה מדווח דרך emit ישיר (ולא UpdateIndexingProgress) כדי
        // ש-processed==total בסוף הסריקה לא ייתפס כ"אינדוקס הושלם" לפני
        // שלב האינדוקס-מחדש.
        onScanProgress: (processed, total) {
          if (_activeWorkId != workId) return;
          emit(
            _inProgress(
              booksProcessed: processed,
              totalBooks: total,
              isCreatingIndex: state.isCreatingIndex,
              isScanning: true,
            ),
          );
        },
        onActualIndexingStarted: () {
          add(ActualIndexingStarted(workId));
        },
        onProgress: (processed, total) {
          add(
            UpdateIndexingProgress(
              workId: workId,
              processed: processed,
              total: total,
            ),
          );
        },
      );
      if (_activeWorkId != workId) {
        return;
      }
      _activeWorkId = null;
      _reportRunFailures(result, runClock.elapsed);
      if (result.completed) {
        emit(IndexingComplete(failures: result.failures));
      } else {
        emit(IndexingInitial());
      }
    } catch (e) {
      if (_activeWorkId != workId) {
        return;
      }
      _activeWorkId = null;
      emit(
        IndexingError(
          e.toString(),
          booksProcessed: state.booksProcessed,
          totalBooks: state.totalBooks,
        ),
      );
    }
  }

  /// Handles the StartIndexing event
  Future<void> _onStartIndexing(
    StartIndexing event,
    Emitter<IndexingState> emit,
  ) async {
    final workId = ++_nextWorkId;
    final runClock = Stopwatch()..start();
    _activeWorkId = workId;

    // Set initial state
    // מחשב מראש את totalBooks כדי לשדר אותו מיד
    final allBooks = event.library.getAllBooks();
    final totalBooks = allBooks.length;
    if (totalBooks == 0) {
      emit(IndexingInitial());
      return;
    }
    emit(_inProgress(booksProcessed: 0, totalBooks: totalBooks));

    try {
      final result = await _repository.indexAllBooks(
        event.library,
        onActualIndexingStarted: () {
          add(ActualIndexingStarted(workId));
        },
        onFinalizing: () {
          add(IndexingFinalizing(workId));
        },
        onFinalizingProgress: (fraction) {
          add(IndexingFinalizeProgress(workId, fraction));
        },
        onProgress: (processed, total) {
          // Update progress through event
          add(
            UpdateIndexingProgress(
              workId: workId,
              processed: processed,
              total: total,
            ),
          );
        },
      );
      if (_activeWorkId != workId) {
        return;
      }
      _activeWorkId = null;
      _reportRunFailures(result, runClock.elapsed);
      if (result.completed && totalBooks > 0) {
        emit(IndexingComplete(failures: result.failures));
      } else {
        emit(IndexingInitial());
      }
    } catch (e) {
      if (_activeWorkId != workId) {
        return;
      }
      _activeWorkId = null;
      emit(
        IndexingError(
          e.toString(),
          booksProcessed: state.booksProcessed,
          totalBooks: state.totalBooks,
        ),
      );
    }
  }

  void _onActualIndexingStarted(
    ActualIndexingStarted event,
    Emitter<IndexingState> emit,
  ) {
    if (_activeWorkId != event.workId) {
      return;
    }

    final currentState = state;
    if (currentState is! IndexingInProgress || currentState.isCreatingIndex) {
      return;
    }

    emit(
      _inProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: true,
      ),
    );
  }

  void _onFinalizing(IndexingFinalizing event, Emitter<IndexingState> emit) {
    if (_activeWorkId != event.workId) return;
    final currentState = state;
    if (currentState is! IndexingInProgress) return;
    _isFinalizing = true;
    emit(
      _inProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: currentState.isCreatingIndex,
      ),
    );
  }

  void _onFinalizeProgress(
    IndexingFinalizeProgress event,
    Emitter<IndexingState> emit,
  ) {
    if (_activeWorkId != event.workId) return;
    final currentState = state;
    if (currentState is! IndexingInProgress) return;
    _finalizingProgress = event.fraction;
    emit(
      _inProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: currentState.isCreatingIndex,
      ),
    );
  }

  /// מטפל באינדוקס של רשימת ספרים — חדשים (IndexSpecificBooks) או
  /// כאלה שתוכנם השתנה (ReindexChangedBooks, עם [reindex] פעיל).
  Future<void> _onBooksWork(
    List<Book> books,
    Library library,
    Emitter<IndexingState> emit, {
    required bool reindex,
  }) async {
    final workId = ++_nextWorkId;
    final runClock = Stopwatch()..start();
    _activeWorkId = workId;

    if (books.isEmpty) {
      _activeWorkId = null;
      return;
    }

    final totalBooks = books.length;
    emit(_inProgress(booksProcessed: 0, totalBooks: totalBooks));

    try {
      onActualIndexingStarted() => add(ActualIndexingStarted(workId));
      onProgress(int processed, int total) => add(
        UpdateIndexingProgress(
          workId: workId,
          processed: processed,
          total: total,
        ),
      );
      final result = reindex
          ? await _repository.reindexChangedBooks(
              books,
              library,
              onActualIndexingStarted: onActualIndexingStarted,
              onProgress: onProgress,
            )
          : await _repository.indexBooks(
              books,
              library,
              onActualIndexingStarted: onActualIndexingStarted,
              onProgress: onProgress,
            );
      if (_activeWorkId != workId) {
        return;
      }
      _activeWorkId = null;
      _reportRunFailures(result, runClock.elapsed);
      if (result.completed) {
        emit(IndexingComplete(failures: result.failures));
      } else {
        emit(IndexingInitial());
      }
    } catch (e) {
      if (_activeWorkId != workId) {
        return;
      }
      _activeWorkId = null;
      emit(
        IndexingError(
          e.toString(),
          booksProcessed: state.booksProcessed,
          totalBooks: state.totalBooks,
        ),
      );
    }
  }

  void _reportRunFailures(IndexingRunResult result, Duration elapsed) {
    if (result.failures.isNotEmpty ||
        IndexingFailureReporter.isSlowRun(elapsed)) {
      _reportFailures(result, elapsed);
    }
  }

  Future<void> _onCheckIndexStatus(
    CheckIndexStatus event,
    Emitter<IndexingState> emit,
  ) async {
    if (state is IndexingInProgress) return;

    await _repository.awaitReady();

    if (state is IndexingInProgress) return;

    if (await _repository.requiresManualReindex(event.library)) {
      emit(IndexingInitial());
      return;
    }

    final indexableBooks = event.library
        .getAllBooks()
        .where(IndexingRepository.isIndexableBook)
        .toList();

    if (indexableBooks.isEmpty) {
      emit(const IndexingComplete());
      return;
    }

    final allIndexed = indexableBooks.every(_repository.isBookIndexed);
    emit(allIndexed ? const IndexingComplete() : IndexingInitial());
  }

  /// Handles the CancelIndexing event
  void _onCancelIndexing(
    CancelIndexing event,
    Emitter<IndexingState> emit,
  ) {
    _activeWorkId = null;
    _isPaused = false;
    _repository.cancelIndexing();
    emit(IndexingStopped());
  }

  void _onPauseIndexing(PauseIndexing event, Emitter<IndexingState> emit) {
    if (state is! IndexingInProgress || _isPaused) return;
    _isPaused = true;
    _repository.pauseIndexing();
    _reemitProgressFlags(emit);
  }

  void _onResumeIndexing(ResumeIndexing event, Emitter<IndexingState> emit) {
    if (!_isPaused) return;
    _isPaused = false;
    _repository.resumeIndexing();
    _reemitProgressFlags(emit);
  }

  Future<void> _onSetEconomyIndexing(
    SetEconomyIndexing event,
    Emitter<IndexingState> emit,
  ) async {
    if (_isEconomy == event.enabled) return;
    try {
      await _repository.setEconomyIndexing(event.enabled);
      _isEconomy = event.enabled;
      _reemitProgressFlags(emit);
    } catch (e) {
      debugPrint('⚠️ החלפת מצב אינדוקס חסכוני נכשלה: $e');
    }
  }

  /// פליטה מחדש של מצב ההתקדמות הנוכחי עם דגלי ההשהיה/החיסכון העדכניים.
  void _reemitProgressFlags(Emitter<IndexingState> emit) {
    final currentState = state;
    if (currentState is! IndexingInProgress) return;
    emit(
      _inProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: currentState.isCreatingIndex,
        isScanning: currentState.isScanning,
      ),
    );
  }

  /// Handles the EraseIndex event
  Future<void> _onEraseIndex(
    ClearIndex event,
    Emitter<IndexingState> emit,
  ) async {
    if (_rejectIndexMutationInSecondaryWindow(emit)) return;
    _activeWorkId = null;
    if (!await _repository.clearIndex()) return;
    emit(IndexingInitial());
  }

  bool _rejectIndexMutationInSecondaryWindow(Emitter<IndexingState> emit) {
    if (!WindowRole.isSecondary) return false;
    UiSnack.show(WindowMessages.indexingOnlyInMainWindow);
    emit(IndexingInitial());
    return true;
  }

  /// Handles the UpdateIndexingProgress event
  void _onUpdateProgress(
    UpdateIndexingProgress event,
    Emitter<IndexingState> emit,
  ) {
    if (_activeWorkId != event.workId) {
      return;
    }

    // processed==total כאן פירושו "בעבודה על הספר האחרון" — ההשלמה נפלטת
    // ממטפל העבודה עצמו אחרי שה-repository מסיים (כולל commit ו-optimize).
    if (!_repository.isIndexing()) {
      emit(IndexingInitial());
    } else {
      emit(
        _inProgress(
          booksProcessed: event.processed,
          totalBooks: event.total,
          isCreatingIndex: state.isCreatingIndex,
        ),
      );
    }
  }
}
