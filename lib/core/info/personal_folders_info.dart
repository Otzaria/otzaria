import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:otzaria/utils/file/document_converter.dart'
    show isSupportedBookFileByContent;
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/file_hidden_utils.dart';
import 'package:path/path.dart' as p;

/// אוסף את מקטע `folders` של דוח המידע: התיקיות שהמשתמש הגדיר כספרים
/// אישיים, וקובצי הספרים הנתמכים שנמצאים בהן בפועל.
///
/// הסריקה כאן היא **קריאה בלבד** ואינה נוגעת ב-DB, אך היא חוזרת על אותם
/// כללי מיון של סורק הספרייה ([`_collectBookFilesRecursive`] ב-
/// `database_library_provider.dart` ו-`_findNewFiles` ב-`file_sync_service.dart`):
/// דילוג על קבצים מוסתרים/מערכת, סיומת מתוך [kProductionBookFormats], ובדיקת
/// *תוכן* לסיומות הגנריות (‎.xml‎, ‎.wbk‎). בלי אותם כללים הדוח היה מדווח על
/// קבצים שהסורק לעולם לא יקלוט, והמשתמש היה מחפש ספר שאינו אמור להופיע.
class PersonalFoldersInfo {
  const PersonalFoldersInfo._();

  /// מספר הקבצים שמפורטים לכל תיקייה כשלא צוין `files=`.
  static const int defaultFileLimit = 50;

  /// עומק תיקיות מרבי. לולאת junction/symlink ב-Windows מייצרת נתיבים חדשים
  /// לאין קץ, ולכן מגבלת עומק היא הבלם היחיד שאינו דורש resolve לכל תיקייה.
  static const int maxDepth = 32;

  /// תקרת רשומות שנבדקות בתיקייה אחת. תיקייה חריגה תסומן `scanTruncated`
  /// במקום להשהות את הדוח (והפופאפ) ללא גבול.
  static const int maxEntriesPerFolder = 200000;

  /// אוסף את המקטע. [fileLimit] — מספר הקבצים שיפורטו לכל תיקייה; `0`
  /// מחזיר ספירות בלבד בלי רשימת קבצים.
  static Future<Map<String, dynamic>> collect({
    int fileLimit = defaultFileLimit,
    List<CustomFolder>? foldersOverride,
  }) async {
    final folders = foldersOverride ?? readConfiguredFolders();
    final mergeDefault =
        Settings.isInitialized &&
        (Settings.getValue<bool>(
              SettingsRepository.keyMergeUserBooksIntoLibrary,
              defaultValue: false,
            ) ??
            false);

    final reports = <Map<String, dynamic>>[];
    var totalFiles = 0;
    var totalSize = 0;
    var existingCount = 0;

    for (final folder in folders) {
      final scan = await scanFolder(folder.path, fileLimit: fileLimit);
      if (scan.exists) existingCount++;
      totalFiles += scan.fileCount;
      totalSize += scan.totalSizeBytes;
      reports.add({
        'path': folder.path,
        'name': folder.name,
        'exists': scan.exists,
        'addToDatabase': folder.addToDatabase,
        // הערך האפקטיבי, לא הגולמי: `null` פירושו "לך אחרי ההגדרה
        // הגלובלית", וצרכן חיצוני אינו יכול לפענח זאת בלי ההגדרה עצמה.
        'mergeIntoLibrary': folder.resolveMergeIntoLibrary(mergeDefault),
        'mergeIntoLibrarySource': folder.mergeIntoLibrary == null
            ? 'default'
            : 'folder',
        'hidden': folder.hidden,
        'addedAt': folder.addedAt.toUtc().toIso8601String(),
        'fileCount': scan.fileCount,
        'sizeBytes': scan.totalSizeBytes,
        'filesByType': scan.countByType,
        if (fileLimit > 0) 'files': scan.files,
        if (fileLimit > 0) 'filesTruncated': scan.fileCount > scan.files.length,
        if (scan.scanTruncated) 'scanTruncated': true,
        if (scan.error != null) 'scanError': scan.error,
      });
    }

    return {
      'configuredCount': folders.length,
      'existingCount': existingCount,
      'totalFiles': totalFiles,
      'totalSizeBytes': totalSize,
      'fileLimit': fileLimit,
      'supportedExtensions': kSupportedBookExtensions,
      'folders': reports,
    };
  }

  /// התיקיות שהמשתמש הגדיר, מההגדרות. מקור אמת יחיד עם ה-bloc של ההגדרות —
  /// אין כאן פענוח JSON מקביל.
  ///
  /// כשההגדרות לא אותחלו (לא אמור לקרות באפליקציה ולא ב-CLI, שמאתחל תמיד
  /// דרך `SettingsSnapshot`) מוחזרת רשימה ריקה — `Settings.getValue` היה
  /// מפיל את המקטע ב-assert במקום להחזיר דוח חלקי.
  static List<CustomFolder> readConfiguredFolders() => Settings.isInitialized
      ? CustomFoldersManager.loadFolders(
          Settings.getValue<String>(SettingsRepository.keyCustomFolders),
        )
      : const [];

  /// סורק תיקייה אחת ומחזיר את קובצי הספרים שבה, לפי אותם כללים של הסורק.
  static Future<PersonalFolderScan> scanFolder(
    String folderPath, {
    int fileLimit = defaultFileLimit,
  }) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return const PersonalFolderScan(exists: false);
    }

    final files = <Map<String, dynamic>>[];
    final countByType = <String, int>{};
    var fileCount = 0;
    var totalSize = 0;
    var examined = 0;
    var truncated = false;
    String? error;

    Future<void> walk(Directory dir, int depth) async {
      if (depth > maxDepth || truncated) return;
      try {
        await for (final entity in dir.list()) {
          if (++examined > maxEntriesPerFolder) {
            truncated = true;
            return;
          }
          if (isHiddenOrSystem(entity.path)) continue;
          if (entity is Directory) {
            await walk(entity, depth + 1);
            if (truncated) return;
            continue;
          }
          if (entity is! File) continue;

          final format = documentFormatFromExtension(entity.path);
          if (format == null || !format.isProductionSupported) continue;
          // ‎.xml‎ ו-‎.wbk‎ נאספים רק אם תוכנם אכן מסמך — אותו שער שבסורק.
          if (format.needsContentSniffing &&
              !await isSupportedBookFileByContent(entity.path)) {
            continue;
          }

          FileStat? stat;
          try {
            stat = await entity.stat();
          } catch (_) {
            // קובץ נעול/נמחק תוך כדי סריקה — נספר בלי גודל ותאריך.
          }
          fileCount++;
          totalSize += stat?.size ?? 0;
          countByType[format.extension] =
              (countByType[format.extension] ?? 0) + 1;
          if (files.length < fileLimit) {
            files.add({
              'path': entity.path,
              'name': p.basename(entity.path),
              'fileType': format.extension,
              if (stat != null) 'sizeBytes': stat.size,
              if (stat != null)
                'modifiedAt': stat.modified.toUtc().toIso8601String(),
            });
          }
        }
      } on FileSystemException catch (e) {
        // הרשאות חסרות בתת-תיקייה אחת לא מבטלות את שאר הסריקה.
        error ??= e.osError?.message ?? e.message;
        debugPrint('PersonalFoldersInfo: ${dir.path} skipped: $e');
      }
    }

    await walk(directory, 0);

    // מיון לתצוגה בלבד. *אילו* קבצים נכנסו לרשימה נקבע לפי סדר הסריקה
    // (עומק-תחילה) ולא לפי הא"ב — הקיצוץ ל-[fileLimit] קורה תוך כדי המעבר
    // ולא בסופו, כדי לא להחזיק בזיכרון רשומה לכל קובץ בתיקייה ענקית.
    files.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));

    return PersonalFolderScan(
      exists: true,
      fileCount: fileCount,
      totalSizeBytes: totalSize,
      countByType: Map.fromEntries(
        countByType.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      files: files,
      scanTruncated: truncated,
      error: error,
    );
  }
}

/// תוצאת סריקה של תיקייה אישית אחת.
@immutable
class PersonalFolderScan {
  final bool exists;
  final int fileCount;
  final int totalSizeBytes;
  final Map<String, int> countByType;
  final List<Map<String, dynamic>> files;

  /// הסריקה נעצרה בתקרת הרשומות — הספירות חלקיות.
  final bool scanTruncated;

  /// שגיאת מערכת קבצים ראשונה שנתקלנו בה (הרשאות וכד'), אם הייתה.
  final String? error;

  const PersonalFolderScan({
    required this.exists,
    this.fileCount = 0,
    this.totalSizeBytes = 0,
    this.countByType = const {},
    this.files = const [],
    this.scanTruncated = false,
    this.error,
  });
}
