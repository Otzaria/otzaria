import 'package:equatable/equatable.dart';

abstract class EmptyLibraryEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class PickDirectoryRequested extends EmptyLibraryEvent {}

class DownloadLibraryRequested extends EmptyLibraryEvent {
  /// מיקום היעד שאליו תורד הספרייה. null → נתיב ברירת המחדל של האפליקציה.
  final String? targetPath;

  DownloadLibraryRequested({this.targetPath});

  @override
  List<Object?> get props => [targetPath];
}

/// עדכון ספרייה קיימת (מההגדרות) עם גיבוי בטוח של ה-DB הישן.
/// ה-DB הישן ב-[existingLibraryPath] מגובה, ונמחק לצמיתות רק בהצלחה (ומשוחזר
/// בכישלון). [isDownload] → הורדה מחדש; אחרת [sourceFolder] הוא תיקייה עם
/// seforim.db (כש-[isArchive] false) או קובץ ארכיון ZIP/ZST (כש-true).
class UpdateLibraryRequested extends EmptyLibraryEvent {
  final bool isDownload;
  final String? sourceFolder;
  final String targetPath;
  final String existingLibraryPath;
  final bool isArchive;

  UpdateLibraryRequested({
    required this.isDownload,
    this.sourceFolder,
    required this.targetPath,
    required this.existingLibraryPath,
    this.isArchive = false,
  });

  @override
  List<Object?> get props =>
      [isDownload, sourceFolder, targetPath, existingLibraryPath, isArchive];
}

/// ייבוא ספרייה מתיקייה שנבחרה: מזהה אוטומטית את נכסי הספרייה שבתוכה (seforim.db,
/// קטלוג, מילון, תלמוד בבלי) בגרסה דחוסה או רגילה, ומחלץ/מעתיק כל אחד אל היעד.
/// [backupExistingPath] — כשמסופק (עדכון במקום), ה-DB הישן בנתיב זה מגובה
/// ומשוחזר בכישלון.
class ImportLibraryFolderRequested extends EmptyLibraryEvent {
  final String sourceFolder;
  final String targetPath;
  final String? backupExistingPath;

  ImportLibraryFolderRequested({
    required this.sourceFolder,
    required this.targetPath,
    this.backupExistingPath,
  });

  @override
  List<Object?> get props => [sourceFolder, targetPath, backupExistingPath];
}

/// ייבוא ספרייה קיימת אל [targetPath]: העתקת תיקיית DB או חילוץ ארכיון.
class ImportExistingLibraryRequested extends EmptyLibraryEvent {
  /// המקור שנבחר — תיקייה המכילה seforim.db, או קובץ דחוס (zip/zst).
  final String sourcePath;

  /// מיקום היעד שאליו יועתקו/יחולצו קבצי הספרייה.
  final String targetPath;

  /// true → [sourcePath] הוא קובץ דחוס; false → תיקייה עם DB קיים.
  final bool isArchive;

  ImportExistingLibraryRequested({
    required this.sourcePath,
    required this.targetPath,
    required this.isArchive,
  });

  @override
  List<Object?> get props => [sourcePath, targetPath, isArchive];
}

/// בודק מקום פנוי בהתקנה וקובע אם כפתור ההורדה זמין.
/// נשלח בעת טעינת המסך.
class CheckDiskSpaceRequested extends EmptyLibraryEvent {}

/// בחירת מיקום אחסון הספרייה ב-Android (אחסון פנימי או כרטיס SD).
/// [libraryRoot] ריק/null => אחסון פנימי. הבחירה נשמרת ובדיקת המקום הפנוי
/// מורצת מחדש עבור היעד החדש.
class StorageLocationSelected extends EmptyLibraryEvent {
  final String? libraryRoot;

  StorageLocationSelected(this.libraryRoot);

  @override
  List<Object?> get props => [libraryRoot];
}

class DeleteZipAnswered extends EmptyLibraryEvent {
  final bool shouldDelete;
  final String zipPath;
  final String extractedPath;

  DeleteZipAnswered({
    required this.shouldDelete,
    required this.zipPath,
    required this.extractedPath,
  });

  @override
  List<Object?> get props => [shouldDelete, zipPath, extractedPath];
}

/// בחירת קובץ seforim.db ישירות דרך file picker (SAF-aware).
/// משמש כאשר הגישה לנתיב הפיזי נכשלת ב-Android Scoped Storage.
class PickDbFileRequested extends EmptyLibraryEvent {
  /// תיקיית הספרייה שנבחרה (תישמר ב-keyLibraryPath)
  final String libraryPath;

  /// הנתיב הפנימי שאליו יועתק הקובץ
  final String internalDbPath;

  /// הנתיב החיצוני המקורי של seforim.db (למחיקה אם shouldMove == true)
  final String externalDbPath;

  /// אם true — ינסה למחוק את הקובץ החיצוני המקורי לאחר ההעתקה.
  final bool shouldMove;

  PickDbFileRequested({
    required this.libraryPath,
    required this.internalDbPath,
    required this.externalDbPath,
    this.shouldMove = false,
  });

  @override
  List<Object?> get props =>
      [libraryPath, internalDbPath, externalDbPath, shouldMove];
}
