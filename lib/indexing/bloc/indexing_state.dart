import 'package:equatable/equatable.dart';

sealed class IndexingState extends Equatable {
  final int? booksProcessed;
  final int? totalBooks;
  final bool isCreatingIndex;

  const IndexingState({
    this.booksProcessed,
    this.totalBooks,
    this.isCreatingIndex = false,
  });

  @override
  List<Object?> get props => [booksProcessed, totalBooks, isCreatingIndex];
}

class IndexingInitial extends IndexingState {}

class IndexingInProgress extends IndexingState {
  const IndexingInProgress({
    super.booksProcessed,
    super.totalBooks,
    super.isCreatingIndex,
  });
}

class IndexingComplete extends IndexingState {
  const IndexingComplete();
}

class IndexingError extends IndexingState {
  final String error;

  const IndexingError(this.error, {super.booksProcessed, super.totalBooks});

  @override
  List<Object?> get props => [error, booksProcessed, totalBooks];
}
