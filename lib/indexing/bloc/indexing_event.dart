import 'package:equatable/equatable.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

abstract class IndexingEvent extends Equatable {
  const IndexingEvent();

  @override
  List<Object?> get props => [];
}

abstract class IndexingWorkEvent extends IndexingEvent {
  const IndexingWorkEvent();
}

class StartIndexing extends IndexingWorkEvent {
  final Library library;

  const StartIndexing(this.library);

  @override
  List<Object?> get props => [library];
}

class IndexSpecificBooks extends IndexingWorkEvent {
  final List<Book> books;
  final Library library;

  const IndexSpecificBooks(this.books, this.library);

  @override
  List<Object?> get props => [books, library];
}

/// אינדוקס מחדש של ספרים שתוכנם השתנה — רשומותיהם הישנות מוסרות תחילה.
class ReindexChangedBooks extends IndexingWorkEvent {
  final List<Book> books;
  final Library library;

  const ReindexChangedBooks(this.books, this.library);

  @override
  List<Object?> get props => [books, library];
}

/// השוואת טביעות-האצבע שבאינדקס מול תוכן הספרייה, ואינדוקס מחדש של
/// הספרים שנמצאו שונים — למסלולים בהם איש לא דיווח מה השתנה (הורדה מלאה).
class ReconcileIndex extends IndexingWorkEvent {
  final Library library;

  const ReconcileIndex(this.library);

  @override
  List<Object?> get props => [library];
}

/// ניקוי רשומות יתומות מהאינדקס — ספרים שכבר אינם בספרייה (ספר אישי
/// שנמחק, תיקייה מותאמת שהוסרה). רץ בתור העבודה הסדרתי, בלי UI התקדמות.
class DropOrphanedIndexEntries extends IndexingWorkEvent {
  final Library library;

  const DropOrphanedIndexEntries(this.library);

  @override
  List<Object?> get props => [library];
}

class CheckIndexStatus extends IndexingEvent {
  final Library library;

  const CheckIndexStatus(this.library);

  @override
  List<Object?> get props => [library];
}

class ClearIndex extends IndexingEvent {}

class CancelIndexing extends IndexingEvent {}

class ActualIndexingStarted extends IndexingEvent {
  final int workId;

  const ActualIndexingStarted(this.workId);

  @override
  List<Object?> get props => [workId];
}

class UpdateIndexingProgress extends IndexingEvent {
  final int workId;
  final int processed;
  final int total;

  const UpdateIndexingProgress({
    required this.workId,
    required this.processed,
    required this.total,
  });

  @override
  List<Object?> get props => [
        workId,
        processed,
        total,
      ];
}
