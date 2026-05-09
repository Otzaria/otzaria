import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';

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
      await _onIndexSpecificBooks(event, emit);
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
    emit(IndexingInProgress(
      booksProcessed: 0,
      totalBooks: totalBooks,
      booksDone: _repository.getIndexedBooks(),
      isCreatingIndex: false,
    ));

    try {
      final completed = await _repository.indexAllBooks(
        event.library,
        onActualIndexingStarted: () {
          add(ActualIndexingStarted(workId));
        },
        onProgress: (processed, total) {
          // Update progress through event
          add(UpdateIndexingProgress(
            workId: workId,
            processed: processed,
            total: total,
          ));
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
      emit(IndexingError(e.toString(),
          booksProcessed: state.booksProcessed,
          totalBooks: state.totalBooks,
          booksDone: _repository.getIndexedBooks()));
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

    emit(IndexingInProgress(
      booksProcessed: currentState.booksProcessed,
      totalBooks: currentState.totalBooks,
      booksDone: currentState.booksDone,
      isCreatingIndex: true,
    ));
  }

  /// Handles the IndexSpecificBooks event
  Future<void> _onIndexSpecificBooks(
    IndexSpecificBooks event,
    Emitter<IndexingState> emit,
  ) async {
    final workId = ++_nextWorkId;
    _activeWorkId = workId;

    if (event.books.isEmpty) {
      _activeWorkId = null;
      return;
    }

    final totalBooks = event.books.length;
    emit(IndexingInProgress(
      booksProcessed: 0,
      totalBooks: totalBooks,
      booksDone: _repository.getIndexedBooks(),
      isCreatingIndex: false,
    ));

    try {
      final completed = await _repository.indexBooks(
        event.books,
        event.library,
        onActualIndexingStarted: () {
          add(ActualIndexingStarted(workId));
        },
        onProgress: (processed, total) {
          add(UpdateIndexingProgress(
            workId: workId,
            processed: processed,
            total: total,
          ));
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
      emit(IndexingError(e.toString(),
          booksProcessed: state.booksProcessed,
          totalBooks: state.totalBooks,
          booksDone: _repository.getIndexedBooks()));
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

    final indexedSet = Set<String>.from(_repository.getIndexedBooks());
    final allIndexed = indexableBooks.every(
      (book) => indexedSet.contains(IndexingRepository.catalogueOrderKey(book)),
    );
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
      ClearIndex event, Emitter<IndexingState> emit) async {
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

    // If indexing is complete
    if (event.processed >= event.total) {
      emit(const IndexingComplete());
    } else if (!_repository.isIndexing()) {
      emit(IndexingInitial());
    } else {
      // Update progress state
      emit(IndexingInProgress(
        booksProcessed: event.processed,
        totalBooks: event.total,
        booksDone: state.booksDone,
        isCreatingIndex: state.isCreatingIndex,
      ));
    }
  }
}
