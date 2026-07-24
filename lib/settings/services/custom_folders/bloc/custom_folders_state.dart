part of 'custom_folders_bloc.dart';

class CustomFoldersState extends Equatable {
  const CustomFoldersState({
    this.folders = const [],
    this.isSyncing = false,
    this.activePath,
    this.message,
    this.error,
  });

  final List<CustomFolder> folders;
  final bool isSyncing;

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
  }) {
    final newSyncing = isSyncing ?? this.isSyncing;
    return CustomFoldersState(
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
  List<Object?> get props => [folders, isSyncing, activePath, message, error];
}

const Object _sentinel = Object();
