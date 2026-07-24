part of 'library_update_bloc.dart';

enum LibraryUpdateStatus {
  /// מצב מנוחה — אין פעולה פעילה.
  idle,

  /// בודק זמינות עדכון מול GitHub.
  checking,

  /// מוריד קובץ patch.
  downloading,

  /// מאמת/מחיל את העדכון על ה-DB.
  applying,

  /// מרענן את ה-runtime וה-caches.
  refreshing,

  /// הסתיים — ראה [LibraryUpdateState.hasUpdate].
  completed,

  /// נדרש אישור משתמש להורדה מלאה גדולה.
  needsFullConfirmation,

  /// מצב חסום שדורש פעולה ידנית.
  blocked,

  /// שגיאה.
  error,
}

class LibraryUpdateState extends Equatable {
  final LibraryUpdateStatus status;
  final String message;

  /// `true` אם הוחל עדכון בפועל (לצורך הפעלת ריענון ספרייה/אינדוקס ב-UI).
  final bool hasUpdate;

  final int stepIndex;
  final int totalSteps;
  final int? bytesDownloaded;
  final int? bytesTotal;

  /// יחס התקדמות (0..1) בתוך שלב אימות ה-hash; null בשאר שלבי ה-apply.
  final double? applyProgress;

  /// התוכנית שנבחרה — זמינה במצב [LibraryUpdateStatus.needsFullConfirmation].
  final LibraryUpdatePlan? plan;

  /// מזהי ספרים (seforim.db) שתוכנם השתנה בעדכון דלתא — לרענון אינדקס החיפוש.
  final Set<int> changedBookIds;

  final String? errorMessage;

  const LibraryUpdateState({
    this.status = LibraryUpdateStatus.idle,
    this.message = 'בדוק עדכוני ספרייה',
    this.hasUpdate = false,
    this.stepIndex = 0,
    this.totalSteps = 0,
    this.bytesDownloaded,
    this.bytesTotal,
    this.applyProgress,
    this.plan,
    this.changedBookIds = const {},
    this.errorMessage,
  });

  bool get isBusy =>
      status == LibraryUpdateStatus.checking ||
      status == LibraryUpdateStatus.downloading ||
      status == LibraryUpdateStatus.applying ||
      status == LibraryUpdateStatus.refreshing;

  /// שינוי המשפיע על ריענון הספרייה. hasUpdate נבדק בנפרד מ-status כי ריצה
  /// שבוטלה יכולה להפוך אותו ל-true בזמן ש-status כבר completed.
  static bool hasRefreshRelevantChange(
    LibraryUpdateState previous,
    LibraryUpdateState current,
  ) =>
      previous.status != current.status ||
      previous.hasUpdate != current.hasUpdate;

  /// האם התוכנית שבוצעה היא הורדה מלאה — אז אין מידע מי השתנה, וה-UI
  /// מפעיל reconcile של האינדקס מול הספרייה במקום רשימת ספרים ידועה.
  bool get isFullDownloadPlan =>
      plan?.kind == LibraryUpdatePlanKind.fullDownload;

  static const _sentinel = Object();

  LibraryUpdateState copyWith({
    LibraryUpdateStatus? status,
    String? message,
    bool? hasUpdate,
    int? stepIndex,
    int? totalSteps,
    int? bytesDownloaded,
    int? bytesTotal,
    // sentinel ולא ??: null חייב *לנקות* ערך ישן, אחרת אירועי stage בלי מדידה
    // משאירים אחוז שאריתי מהאימות הקודם (למשל בין צעדי דלתא).
    Object? applyProgress = _sentinel,
    LibraryUpdatePlan? plan,
    Set<int>? changedBookIds,
    String? errorMessage,
  }) {
    return LibraryUpdateState(
      status: status ?? this.status,
      message: message ?? this.message,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      stepIndex: stepIndex ?? this.stepIndex,
      totalSteps: totalSteps ?? this.totalSteps,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      applyProgress: identical(applyProgress, _sentinel)
          ? this.applyProgress
          : applyProgress as double?,
      plan: plan ?? this.plan,
      changedBookIds: changedBookIds ?? this.changedBookIds,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    message,
    hasUpdate,
    stepIndex,
    totalSteps,
    bytesDownloaded,
    bytesTotal,
    applyProgress,
    plan,
    changedBookIds,
    errorMessage,
  ];
}
