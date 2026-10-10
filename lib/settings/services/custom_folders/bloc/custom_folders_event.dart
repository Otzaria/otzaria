part of 'custom_folders_bloc.dart';

sealed class CustomFoldersEvent extends Equatable {
  const CustomFoldersEvent();
}

class LoadCustomFolders extends CustomFoldersEvent {
  const LoadCustomFolders();
  @override
  List<Object> get props => [];
}

class AddCustomFolder extends CustomFoldersEvent {
  const AddCustomFolder(this.path);
  final String path;
  @override
  List<Object> get props => [path];
}

class RemoveCustomFolder extends CustomFoldersEvent {
  const RemoveCustomFolder(
    this.folder, {
    required this.deleteFromDb,
    this.completer,
  });
  final CustomFolder folder;
  final bool deleteFromDb;

  /// תוצאת ההסרה הזו בלבד: null בהצלחה, הודעת שגיאה בכישלון.
  final Completer<String?>? completer;
  @override
  List<Object> get props => [folder, deleteFromDb];
}

class ToggleAddToDatabase extends CustomFoldersEvent {
  const ToggleAddToDatabase(this.folder, this.value);
  final CustomFolder folder;
  final bool value;
  @override
  List<Object> get props => [folder, value];
}

/// קביעת חריגת מיזוג לתיקייה בודדת. [value] `null` מחזיר אותה לברירת
/// המחדל הגלובלית.
class SetFolderMergeMode extends CustomFoldersEvent {
  const SetFolderMergeMode(this.folder, this.value);
  final CustomFolder folder;
  final bool? value;
  @override
  List<Object?> get props => [folder, value];
}

/// הסתרת תיקייה מעץ הספרייה או החזרתה. הספרים נשארים ב-DB.
class SetFolderHidden extends CustomFoldersEvent {
  const SetFolderHidden(this.folder, this.hidden);
  final CustomFolder folder;
  final bool hidden;
  @override
  List<Object> get props => [folder, hidden];
}

class RescanCustomFolders extends CustomFoldersEvent {
  const RescanCustomFolders({
    this.showNoChangesMessage = true,
    this.onlyFolderPath,
    this.requestId,
  });
  final bool showNoChangesMessage;

  /// כשמסופק, נסרקת רק תיקייה זו — מייבוא ספרים אישיים, שם שאר התיקיות
  /// ממילא לא השתנו.
  final String? onlyFolderPath;

  /// מזהה בקשה שידווח ב-[CustomFoldersState.completedScan] בסיום הסריקה,
  /// בהצלחה או בכישלון. קיים כדי שקורא שאינו UI (כרגע
  /// `library.refreshUserBooks` של תוסף) יוכל לחכות לתוצאה של הסריקה שהוא
  /// עצמו ביקש. `null` = סריקה מהממשק, שתוצאתה מוצגת ב-message/error בלבד.
  final int? requestId;

  @override
  List<Object?> get props => [showNoChangesMessage, onlyFolderPath, requestId];
}

/// ייבוא ידני של קבצי דורות/קישורים שהמשתמש בחר (לצמיתות, בדריסה מצטברת).
class ImportUserContentFiles extends CustomFoldersEvent {
  const ImportUserContentFiles(this.paths);
  final List<String> paths;
  @override
  List<Object> get props => [paths];
}

/// מחיקת כל הדורות והקישורים המיובאים.
class ClearUserContent extends CustomFoldersEvent {
  const ClearUserContent();
  @override
  List<Object> get props => [];
}

/// טעינת רשימת קובצי הייבוא לתצוגה בהגדרות.
class LoadUserImportFiles extends CustomFoldersEvent {
  const LoadUserImportFiles();
  @override
  List<Object> get props => [];
}

/// השהיה או החזרה של קובץ ייבוא. הקובץ נשאר בספרייה בשני המקרים.
class SetUserImportFileEnabled extends CustomFoldersEvent {
  const SetUserImportFileEnabled(this.id, {required this.enabled});
  final int id;
  final bool enabled;
  @override
  List<Object> get props => [id, enabled];
}

/// הסרת קובץ ייבוא בודד מהספרייה, על הנתונים שהגיעו ממנו.
class RemoveUserImportFile extends CustomFoldersEvent {
  const RemoveUserImportFile(this.id);
  final int id;
  @override
  List<Object> get props => [id];
}
