import 'package:equatable/equatable.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';

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
    this.isScanning = false,
    this.isPaused = false,
    this.isEconomy = false,
    this.isFinalizing = false,
    this.finalizingProgress,
  });

  /// שלב הסריקה של ReconcileIndex — השוואת טביעות-אצבע לפני אינדוקס-מחדש.
  /// שלב ארוך שרץ רק בבקשת עדכון מפורשת, ולכן מוצג בחיווי (issue #1056).
  final bool isScanning;

  /// האינדוקס מושהה — הלולאה ממתינה לפני הספר הבא.
  final bool isPaused;

  /// מצב חסכוני פעיל — המנוע רץ עם תקציב writer מוקטן.
  final bool isEconomy;

  /// כל הספרים אונדקסו והמנוע מאחד את קבצי האינדקס (commit ו-optimize).
  final bool isFinalizing;

  /// התקדמות איחוד הסגמנטים כשבר בין 0 ל-1. null עד שהדגימה הראשונה
  /// מגיעה, או כשלא ניתן למדוד — ואז החיווי נשאר בלתי-מוגדר.
  final double? finalizingProgress;

  @override
  List<Object?> get props => [
    ...super.props,
    isScanning,
    isPaused,
    isEconomy,
    isFinalizing,
    finalizingProgress,
  ];
}

class IndexingComplete extends IndexingState {
  const IndexingComplete({this.failures = const []});

  final List<IndexingFailure> failures;

  bool get isClean => failures.isEmpty;
  int get failureCount => failures.length;

  @override
  List<Object?> get props => [failures];
}

class IndexingStopped extends IndexingState {}

class IndexingError extends IndexingState {
  final String error;

  const IndexingError(this.error, {super.booksProcessed, super.totalBooks});

  @override
  List<Object?> get props => [error, booksProcessed, totalBooks];
}
