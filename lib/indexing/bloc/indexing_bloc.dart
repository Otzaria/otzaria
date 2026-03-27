import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';

class IndexingBloc extends Bloc<IndexingEvent, IndexingState> {
  final IndexingRepository _repository;

  IndexingBloc(this._repository) : super(IndexingInitial()) {
    on<StartIndexing>(_onStartIndexing);
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

  /// Handles the StartIndexing event
  Future<void> _onStartIndexing(
    StartIndexing event,
    Emitter<IndexingState> emit,
  ) async {
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
          add(ActualIndexingStarted());
        },
        onProgress: (processed, total) {
          // Update progress through event
          add(UpdateIndexingProgress(
            processed: processed,
            total: total,
          ));
        },
      );
      if (completed && totalBooks > 0) {
        emit(const IndexingComplete());
      } else {
        emit(IndexingInitial());
      }
    } catch (e) {
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

  /// Handles the CancelIndexing event
  void _onCancelIndexing(
    CancelIndexing event,
    Emitter<IndexingState> emit,
  ) {
    _repository.cancelIndexing();
    emit(IndexingInitial());
  }

  /// Handles the EraseIndex event
  Future<void> _onEraseIndex(
      ClearIndex event, Emitter<IndexingState> emit) async {
    await _repository.clearIndex();
    emit(IndexingInitial());
  }

  /// Handles the UpdateIndexingProgress event
  void _onUpdateProgress(
    UpdateIndexingProgress event,
    Emitter<IndexingState> emit,
  ) {
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
