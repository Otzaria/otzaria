import 'package:equatable/equatable.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

abstract class IndexingEvent extends Equatable {
  const IndexingEvent();

  @override
  List<Object?> get props => [];
}

abstract class IndexingWorkEvent extends IndexingEvent {
  final void Function()? onSettled;

  const IndexingWorkEvent({this.onSettled});
}

/// אות סיום לכל עבודת האינדוקס שנשלחה לפניו לתור הסדרתי.
class IndexingWorkBarrier extends IndexingWorkEvent {
  const IndexingWorkBarrier({super.onSettled});
}

class StartIndexing extends IndexingWorkEvent {
  final Library library;

  const StartIndexing(this.library, {super.onSettled});

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
/// עם [books] הסריקה מוגבלת לספרים אלה (למשל ספרי מסד מצורף שהקובץ שלו השתנה).
class ReconcileIndex extends IndexingWorkEvent {
  final Library library;
  final List<Book>? books;

  const ReconcileIndex(this.library, {this.books});

  @override
  List<Object?> get props => [library, books];
}

/// ניקוי רשומות יתומות מהאינדקס — ספרים שכבר אינם בספרייה (ספר אישי
/// שנמחק, תיקייה מותאמת שהוסרה). רץ בתור העבודה הסדרתי, בלי UI התקדמות.
class DropOrphanedIndexEntries extends IndexingWorkEvent {
  final Library library;

  const DropOrphanedIndexEntries(this.library);

  @override
  List<Object?> get props => [library];
}

/// מסנכרן רשומות מוסתרות באינדקס; לפי בקשה מאנדקס גם ספרים שחזרו להיות גלויים.
class ReconcileHiddenIndex extends IndexingWorkEvent {
  final Library library;
  final bool indexVisible;
  final bool clearRestoreMarker;
  final bool clearVisibilityMarker;
  final int? visibilityRevision;

  const ReconcileHiddenIndex(
    this.library, {
    super.onSettled,
    this.indexVisible = false,
    this.clearRestoreMarker = false,
    this.clearVisibilityMarker = false,
    this.visibilityRevision,
  });

  @override
  List<Object?> get props => [
    library,
    indexVisible,
    clearRestoreMarker,
    clearVisibilityMarker,
    visibilityRevision,
  ];
}

class ApplyHiddenIndexDelta extends IndexingWorkEvent {
  final Library library;
  final List<Book> newlyHidden;
  final List<Book> newlyVisible;
  final void Function(bool success)? onCompleted;
  final int? visibilityRevision;

  const ApplyHiddenIndexDelta(
    this.library, {
    required this.newlyHidden,
    required this.newlyVisible,
    this.onCompleted,
    this.visibilityRevision,
  });

  @override
  List<Object?> get props => [library, newlyHidden, newlyVisible];
}

class CheckIndexStatus extends IndexingEvent {
  final Library library;

  const CheckIndexStatus(this.library);

  @override
  List<Object?> get props => [library];
}

class ClearIndex extends IndexingEvent {}

class CancelIndexing extends IndexingEvent {}

class PauseIndexing extends IndexingEvent {}

class ResumeIndexing extends IndexingEvent {}

/// הפעלה/כיבוי של מצב אינדוקס חסכוני — תקציב writer מוקטן במנוע.
class SetEconomyIndexing extends IndexingEvent {
  final bool enabled;

  const SetEconomyIndexing(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class ActualIndexingStarted extends IndexingEvent {
  final int workId;

  const ActualIndexingStarted(this.workId);

  @override
  List<Object?> get props => [workId];
}

/// כל הספרים אונדקסו; המנוע מאחד כעת את קבצי האינדקס.
class IndexingFinalizing extends IndexingEvent {
  final int workId;

  const IndexingFinalizing(this.workId);

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
