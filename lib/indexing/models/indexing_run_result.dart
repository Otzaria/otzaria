import 'package:equatable/equatable.dart';

enum IndexingFailureKind {
  partialPdf(isRetryable: false, preventedIndexing: false),
  passwordProtected(isRetryable: false, preventedIndexing: true),
  pdfUnsupported(isRetryable: false, preventedIndexing: true),
  permissionDenied(isRetryable: false, preventedIndexing: true),
  // מסמך שהמבנה שלו שבור או שהפורמט אינו נתמך — ניסיון חוזר לא יעזור.
  unreadableDocument(isRetryable: false, preventedIndexing: true),
  crashedApp(isRetryable: false, preventedIndexing: true),
  // timeout חולף מטבעו (עומס רגעי, worker שנתקע). סימונו כקבוע היה מחשיב
  // ספר תקין כמאונדקס בלי תוכן, עד אינדוקס מלא ידני.
  timeout(isRetryable: true, preventedIndexing: true),
  engineWrite(isRetryable: true, preventedIndexing: true),
  unknown(isRetryable: true, preventedIndexing: true);

  const IndexingFailureKind({
    required this.isRetryable,
    required this.preventedIndexing,
  });

  final bool isRetryable;
  final bool preventedIndexing;
}

class IndexingFailure extends Equatable {
  const IndexingFailure({
    required this.bookTitle,
    required this.bookPath,
    required this.kind,
    required this.error,
    this.stackTrace,
  });

  final String bookTitle;
  final String bookPath;
  final IndexingFailureKind kind;
  final String error;
  final String? stackTrace;

  bool get isRetryable => kind.isRetryable;
  bool get preventedIndexing => kind.preventedIndexing;

  @override
  List<Object?> get props => [bookTitle, bookPath, kind, error, stackTrace];
}

class IndexingRunResult extends Equatable {
  const IndexingRunResult.completed({
    required this.processedBooks,
    required this.totalBooks,
    required this.indexedBooks,
    this.failures = const [],
  }) : cancelled = false;

  const IndexingRunResult.cancelled({
    required this.processedBooks,
    required this.totalBooks,
    required this.indexedBooks,
    this.failures = const [],
  }) : cancelled = true;

  final int processedBooks;
  final int totalBooks;
  final int indexedBooks;
  final bool cancelled;
  final List<IndexingFailure> failures;

  bool get completed => !cancelled;
  bool get isClean => completed && failures.isEmpty;

  Iterable<IndexingFailure> get retryableFailures =>
      failures.where((failure) => failure.isRetryable);

  int get blockingFailureCount =>
      failures.where((failure) => failure.preventedIndexing).length;

  int get warningCount =>
      failures.where((failure) => !failure.preventedIndexing).length;

  @override
  List<Object?> get props => [
    processedBooks,
    totalBooks,
    indexedBooks,
    cancelled,
    failures,
  ];
}
