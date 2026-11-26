part of 'custom_folders_bloc.dart';

/// תוצאת סריקה שהתבקשה עם [RescanCustomFolders.requestId], לדיווח חזרה לקורא
/// שיזם אותה. הודעות ה-UI (`message`/`error`) הן טקסט לתצוגה; זה המבנה שקורא
/// תוכנתי — `library.refreshUserBooks` של תוסף — מקבל.
class CustomFoldersScanOutcome extends Equatable {
  const CustomFoldersScanOutcome({
    required this.requestId,
    this.addedBooks = 0,
    this.updatedBooks = 0,
    this.errors = const [],
    this.failureMessage,
  });

  final int requestId;
  final int addedBooks;
  final int updatedBooks;

  /// כשלים חלקיים — קבצים בודדים שלא נסרקו. הסריקה עצמה הצליחה.
  final List<String> errors;

  /// כשהסריקה כולה נכשלה. `null` = הצליחה.
  final String? failureMessage;

  bool get isSuccess => failureMessage == null;

  @override
  List<Object?> get props => [
    requestId,
    addedBooks,
    updatedBooks,
    errors,
    failureMessage,
  ];
}

class CustomFoldersState extends Equatable {
  const CustomFoldersState({
    this.folders = const [],
    this.isSyncing = false,
    this.activePath,
    this.message,
    this.error,
    this.completedScan,
    this.importFiles = const [],
    this.hasUserContent = false,
  });

  final List<CustomFolder> folders;
  final bool isSyncing;

  /// קובצי הייבוא השמורים, לניהול בהגדרות. ריק עד שנטענו.
  final List<UserImportFile> importFiles;

  /// האם יש נתונים מיובאים ש"נקה הכל" ימחק. false עד שנטענו.
  final bool hasUserContent;

  /// תוצאת הסריקה האחרונה שהתבקשה עם `requestId`. מתאפסת בתחילת כל סריקה
  /// חדשה, כדי שתוצאה ישנה לא תיקלט כתשובה לבקשה אחרת.
  final CustomFoldersScanOutcome? completedScan;

  /// נתיב התיקייה היחידה שמתבצעת עליה כעת פעולה (הוספה / החלפת מצב אחסון).
  /// כשהוא null — הפעולה גלובלית (כגון סריקה מחדש של כל התיקיות) ומוצגת על
  /// כולן. מתאפס אוטומטית כש-[isSyncing] חוזר ל-false.
  final String? activePath;

  final String? message;
  final String? error;

  CustomFoldersState copyWith({
    List<CustomFolder>? folders,
    bool? isSyncing,
    Object? activePath = _sentinel,
    Object? message = _sentinel,
    Object? error = _sentinel,
    Object? completedScan = _sentinel,
    List<UserImportFile>? importFiles,
    bool? hasUserContent,
  }) {
    final newSyncing = isSyncing ?? this.isSyncing;
    return CustomFoldersState(
      completedScan: identical(completedScan, _sentinel)
          ? this.completedScan
          : completedScan as CustomFoldersScanOutcome?,
      importFiles: importFiles ?? this.importFiles,
      hasUserContent: hasUserContent ?? this.hasUserContent,
      folders: folders ?? this.folders,
      isSyncing: newSyncing,
      // כשהסנכרון מסתיים אין תיקייה פעילה — מאפסים כדי שהספינר ייעלם מכולן.
      activePath: !newSyncing
          ? null
          : (identical(activePath, _sentinel)
                ? this.activePath
                : activePath as String?),
      message: identical(message, _sentinel)
          ? this.message
          : message as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  @override
  List<Object?> get props => [
    folders,
    isSyncing,
    activePath,
    message,
    error,
    completedScan,
    importFiles,
    hasUserContent,
  ];
}

const Object _sentinel = Object();
