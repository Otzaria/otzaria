import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';

/// שומר קובץ דרך דיאלוג המערכת ומבטיח שהנתיב מקבל את הסיומת המבוקשת.
///
/// מחזיר את מיקום הקובץ שנשמר, או `null` אם המשתמש ביטל.
///
/// [fileName] חייב לכלול את הסיומת — הדיאלוג גוזר ממנה את סיומת ברירת המחדל
/// (`type`/`allowedExtensions` של `saveFile` אינם מועברים הלאה ב-file_picker).
Future<String?> saveFileWithExtension({
  required String fileName,
  required String extension,
  required Uint8List bytes,
  String? dialogTitle,
  String? initialDirectory,
  BuildContext? context,
}) async {
  final effectiveContext = context ?? navigatorKey.currentContext;
  if (effectiveContext != null && !effectiveContext.mounted) return null;
  // לפני ההמתנה: הבעלים הוא החלון שביקש, גם אם הפוקוס עבר בינתיים.
  final windowsOptions = modalWindowsOptions(effectiveContext);
  if (effectiveContext != null &&
      !await verifySaferModePassword(effectiveContext)) {
    return null;
  }
  if (effectiveContext != null && !effectiveContext.mounted) return null;
  final uri = await withFilePickerOwner(
    effectiveContext,
    (picker) => picker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: initialDirectory,
      bytes: bytes,
      mimeType: 'application/octet-stream',
      windowsOptions: windowsOptions,
      linuxOptions: kModalLinuxOptions,
    ),
  );
  if (uri == null) return null;
  // ב-Android השמירה חוזרת כ-content:// — אין נתיב מקומי לתקן, אבל היא הצליחה.
  if (uri.scheme != 'file') return uri.toString();
  return ensureFileExtension(uri.toFilePath(), extension);
}

/// אם הקובץ שנכתב ב-[path] חסר את הסיומת [extension] — משנה את שמו בהתאם.
///
/// מחזיר את הנתיב הסופי של הקובץ (המקורי אם הסיומת כבר קיימת).
Future<String> ensureFileExtension(String path, String extension) async {
  final normalizedExtension = extension.replaceFirst(RegExp(r'^\\.+'), '');
  if (normalizedExtension.isEmpty) {
    throw ArgumentError.value(extension, 'extension', 'Must not be empty');
  }
  final suffix = '.${normalizedExtension.toLowerCase()}';
  if (path.toLowerCase().endsWith(suffix)) return path;

  final file = File(path);
  if (!await file.exists()) return path;

  final target = '$path.$normalizedExtension';
  final targetFile = File(target);
  if (await targetFile.exists()) {
    await targetFile.delete();
  }
  await file.rename(target);
  return target;
}
