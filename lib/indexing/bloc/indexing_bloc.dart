import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

class IndexingBloc extends Bloc<IndexingEvent, IndexingState> {
  final IndexingRepository _repository;
  int _nextWorkId = 0;
  int? _activeWorkId;

  IndexingBloc(this._repository) : super(IndexingInitial()) {
    on<IndexingWorkEvent>(_onIndexingWork, transformer: sequential());
    on<CheckIndexStatus>(_onCheckIndexStatus);
    on<CancelIndexing>(_onCancelIndexing);
    on<ActualIndexingStarted>(_onActualIndexingStarted);
    on<UpdateIndexingProgress>(_onUpdateProgress);
    on<ClearIndex>(_onEraseIndex);
  }

  /// Factory constructor that creates an IndexingBloc with a default repository
  factory IndexingBloc.create() {
    return IndexingBloc(
      IndexingRepository(TantivyDataProvider.instance),
    );
  }

  Future<void> _onIndexingWork(
    IndexingWorkEvent event,
    Emitter<IndexingState> emit,
  ) async {
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
      IndexingInProgress(
        booksProcessed: 0,
        totalBooks: totalCandidates,
        isCreatingIndex: false,
      ),
    );

    try {
      final completed = await _repository.reconcileIndexWithLibrary(
        event.library,
        // שלב הסריקה מדווח דרך emit ישיר (ולא UpdateIndexingProgress) כדי
        // ש-processed==total בסוף הסריקה לא ייתפס כ"אינדוקס הושלם" לפני
        // שלב האינדוקס-מחדש.
        onScanProgress: (processed, total) {
          if (_activeWorkId != workId) return;
          emit(
            IndexingInProgress(
              booksProcessed: processed,
              totalBooks: total,
              isCreatingIndex: state.isCreatingIndex,
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
      if (completed) {
        emit(const IndexingComplete());
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
    _activeWorkId = workId;

    // Set initial state
    // מחשב מראש את totalBooks כדי לשדר אותו מיד
    final allBooks = event.library.getAllBooks();
    final totalBooks = allBooks.length;
    if (totalBooks == 0) {
      emit(IndexingInitial());
      return;
    }
    emit(
      IndexingInProgress(
        booksProcessed: 0,
        totalBooks: totalBooks,
        isCreatingIndex: false,
      ),
    );

    try {
      final completed = await _repository.indexAllBooks(
        event.library,
        onActualIndexingStarted: () {
          add(ActualIndexingStarted(workId));
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
      if (completed && totalBooks > 0) {
        emit(const IndexingComplete());
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
      IndexingInProgress(
        booksProcessed: currentState.booksProcessed,
        totalBooks: currentState.totalBooks,
        isCreatingIndex: true,
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
    _activeWorkId = workId;

    if (books.isEmpty) {
      _activeWorkId = null;
      return;
    }

    final totalBooks = books.length;
    emit(
      IndexingInProgress(
        booksProcessed: 0,
        totalBooks: totalBooks,
        isCreatingIndex: false,
      ),
    );

    try {
      onActualIndexingStarted() => add(ActualIndexingStarted(workId));
      onProgress(int processed, int total) => add(
        UpdateIndexingProgress(
          workId: workId,
          processed: processed,
          total: total,
        ),
      );
      final completed = reindex
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
      if (completed) {
        emit(const IndexingComplete());
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
    _repository.cancelIndexing();
    emit(IndexingInitial());
  }

  /// Handles the EraseIndex event
  Future<void> _onEraseIndex(
    ClearIndex event,
    Emitter<IndexingState> emit,
  ) async {
    _activeWorkId = null;
    await _repository.clearIndex();
    emit(IndexingInitial());
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
        IndexingInProgress(
          booksProcessed: event.processed,
          totalBooks: event.total,
          isCreatingIndex: state.isCreatingIndex,
        ),
      );
    }
  }
}
