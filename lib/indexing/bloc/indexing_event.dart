import 'package:equatable/equatable.dart';
import 'package:otzaria/indexing/models/index_check_scope.dart';
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

/// ריצת אינדוקס אחת: בדיקה ([check]) ← אינדוקס ספרים חדשים ושהשתנו יחד ←
/// commit ואיחוד אחד בסוף.
class RunIndexing extends IndexingWorkEvent {
  final Library library;

  /// הספרים החדשים לאינדוקס; null — כל ספרי הספרייה שחסרים באינדקס.
  final List<Book>? books;

  /// ספרים שתוכנם השתנה — מסמכיהם הישנים מוחלפים.
  final List<Book> changedBooks;

  final IndexCheckScope check;

  const RunIndexing(
    this.library, {
    this.books,
    this.changedBooks = const [],
    this.check = IndexCheckScope.none,
    super.onSettled,
  });

  @override
  List<Object?> get props => [library, books, changedBooks, check];
}

/// שומר שינויים לריצה הבאה ומרענן חיווי, בלי לאנדקס כשהעדכון האוטומטי כבוי.
class DeferIndexing extends IndexingWorkEvent {
  final Library library;
  final List<Book> changedBooks;
  final bool checkLibrary;

  const DeferIndexing(
    this.library, {
    required this.changedBooks,
    this.checkLibrary = false,
  });

  @override
  List<Object?> get props => [library, changedBooks, checkLibrary];
}

/// אינדוקס כל הספרייה בבקשת המשתמש או בעלייה.
class StartIndexing extends RunIndexing {
  const StartIndexing(super.library, {super.onSettled});
}

/// מחיקת האינדקס ואחריה אינדוקס מלא, באותו תור סדרתי — כדי שהאינדוקס
/// לא ירוץ לפני שהמחיקה הסתיימה.
class ResetAndIndex extends RunIndexing {
  const ResetAndIndex(super.library);
}

/// מעדכן במנוע את סדר הקטלוג והדורות של העץ המלא, בלי פליטת מצב.
class SyncBookOrder extends IndexingWorkEvent {
  final Library library;

  const SyncBookOrder(this.library);

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

/// הפעלה/כיבוי של מצב אינדוקס חסכוני — הכנת ספרים ו-writer בתקציבים חסכוניים.
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
