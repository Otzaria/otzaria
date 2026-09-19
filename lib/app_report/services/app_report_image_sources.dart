import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// מקורות התמונות לטופס הדיווח: הלוח, בחירת קובץ וקבצים שנגררו.
class AppReportImageSources {
  const AppReportImageSources();

  /// התמונות שבלוח. [skipIfText] — לא לצרף כשבלוח יש גם טקסט, כדי שהדבקה
  /// לשדה טקסט מתוך Word/Excel תדביק את הטקסט בלבד.
  Future<List<AppReportImage>> readClipboard({bool skipIfText = false}) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return const [];
    final reader = await clipboard.read();
    if (skipIfText && reader.canProvide(Formats.plainText)) return const [];

    final images = <AppReportImage>[];
    // ב-Windows צילום של כלי החיתוך (DIB) ממומש כ-PNG, וקובץ שהועתק
    // בסייר מופיע גם הוא בפורמט התמונה שלו.
    for (final item in reader.items) {
      for (final (format, mimeType, extension) in const [
        (Formats.png, 'image/png', 'png'),
        (Formats.jpeg, 'image/jpeg', 'jpg'),
      ]) {
        if (!item.canProvide(format)) continue;
        final file = await _readFile(item, format);
        if (file == null) continue;
        images.add(
          AppReportImage(
            bytes: file.bytes,
            fileName: file.name ?? 'screenshot-${images.length + 1}.$extension',
            mimeType: mimeType,
          ),
        );
        break;
      }
    }
    return images;
  }

  static Future<({Uint8List bytes, String? name})?> _readFile(
    DataReader item,
    FileFormat format,
  ) {
    final completer = Completer<({Uint8List bytes, String? name})?>();
    final progress = item.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          completer.complete((bytes: bytes, name: file.fileName));
        } catch (error) {
          if (!completer.isCompleted) completer.completeError(error);
        }
      },
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    if (progress == null) completer.complete(null);
    return completer.future;
  }

  /// פותח את בוחר הקבצים. מחזיר רשימה ריקה בביטול.
  Future<List<AppReportImage>> pickFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppReportImage.supportedExtensions,
      windowsOptions: kModalWindowsOptions,
      linuxOptions: kModalLinuxOptions,
    );
    final images = <AppReportImage>[];
    for (final file in files) {
      final mimeType = AppReportImage.mimeTypeForPath(file.name);
      if (mimeType == null) continue;
      images.add(
        AppReportImage(
          bytes: await file.readAsBytes(),
          fileName: file.name,
          mimeType: mimeType,
        ),
      );
    }
    return images;
  }

  /// קורא את הקבצים שנגררו; קבצים שאינם תמונה נתמכת מדולגים.
  Future<List<AppReportImage>> readPaths(List<String> paths) async {
    final images = <AppReportImage>[];
    for (final path in paths) {
      final mimeType = AppReportImage.mimeTypeForPath(path);
      if (mimeType == null) continue;
      images.add(
        AppReportImage(
          bytes: await File(path).readAsBytes(),
          fileName: path.split(RegExp(r'[\\/]')).last,
          mimeType: mimeType,
        ),
      );
    }
    return images;
  }
}
