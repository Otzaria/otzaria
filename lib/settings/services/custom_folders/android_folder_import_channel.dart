import 'package:flutter/services.dart';

/// תיקייה שנבחרה בבורר התיקיות של המערכת.
class PickedFolder {
  const PickedFolder({required this.uri, required this.name});

  /// ה-URI של העץ (`content://…/tree/…`) — משמש רק בקריאות לערוץ.
  final String uri;
  final String name;
}

/// ספירת קבצי הספרים בתיקייה, לפני העתקה.
class FolderScan {
  const FolderScan({required this.fileCount, required this.totalBytes});

  final int fileCount;
  final int totalBytes;
}

/// קובץ שלא הועתק; [path] יחסי לתיקייה שנבחרה.
class FolderCopyError {
  const FolderCopyError({required this.path, required this.message});

  final String path;
  final String message;
}

class FolderCopyResult {
  const FolderCopyResult({
    required this.copiedPaths,
    required this.errors,
    this.cancelled = false,
  });

  /// נתיבים מלאים של הקבצים שהועתקו ליעד.
  final List<String> copiedPaths;
  final List<FolderCopyError> errors;

  /// ההעתקה נעצרה ב-[AndroidFolderImportChannel.cancelCopy]; מה שהועתק נשאר.
  final bool cancelled;
}

/// ייבוא תיקייה שלמה באנדרואיד. ל-dart:io אין גישה לתיקייה שנבחרה דרך SAF,
/// ולכן המעבר על העץ וההעתקה נעשים בצד הנייטיב (`FolderImportChannel.kt`).
class AndroidFolderImportChannel {
  const AndroidFolderImportChannel();

  static const channel = MethodChannel('otzaria/folder_import');

  /// פותח את בורר התיקיות. מחזיר null אם המשתמש ביטל.
  Future<PickedFolder?> pickFolder() async {
    final result = await channel.invokeMapMethod<String, Object?>('pickTree');
    if (result == null) return null;
    return PickedFolder(
      uri: result['uri']! as String,
      name: (result['name'] as String?) ?? '',
    );
  }

  /// סופר את קבצי הספרים בעץ לפי [extensions] (בלי נקודה), בלי להעתיק.
  Future<FolderScan> scanFolder(String uri, List<String> extensions) async {
    final result = await channel.invokeMapMethod<String, Object?>(
      'scanTree',
      {'uri': uri, 'extensions': extensions},
    );
    return FolderScan(
      fileCount: result!['fileCount']! as int,
      totalBytes: result['totalBytes']! as int,
    );
  }

  /// מעתיק את קבצי הספרים לתוך [destDir] ושומר על מבנה תתי-התיקיות.
  /// קובץ קיים באותו נתיב נדרס.
  Future<FolderCopyResult> copyFolder(
    String uri,
    String destDir,
    List<String> extensions,
  ) async {
    final result = await channel.invokeMapMethod<String, Object?>(
      'copyTree',
      {'uri': uri, 'destDir': destDir, 'extensions': extensions},
    );
    return FolderCopyResult(
      copiedPaths: (result!['copied']! as List).cast<String>(),
      errors: [
        for (final error in (result['errors']! as List).cast<Map>())
          FolderCopyError(
            path: error['path'] as String,
            message: error['message'] as String,
          ),
      ],
      cancelled: result['cancelled'] as bool? ?? false,
    );
  }

  /// עוצר העתקה פעילה אחרי הקובץ הנוכחי; [copyFolder] חוזר עם `cancelled`.
  Future<void> cancelCopy() => channel.invokeMethod<void>('cancelCopy');
}
