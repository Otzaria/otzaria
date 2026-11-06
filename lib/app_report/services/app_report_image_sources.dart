import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// מקורות התמונות לטופס הדיווח: הלוח, בחירת קובץ וקבצים שנגררו.
class AppReportImageSources {
  const AppReportImageSources({this.clipboardReader});

  @visibleForTesting
  final Future<ClipboardReader?> Function()? clipboardReader;

  // A rejected oversized file needs only a size marker, never its full bytes.
  static final _oversized = Uint8List(AppReportImage.maxBytes + 1);

  /// התמונות שבלוח. [skipIfText] — לא לצרף כשבלוח יש גם טקסט, כדי שהדבקה
  /// לשדה טקסט מתוך Word/Excel תדביק את הטקסט בלבד.
  Future<List<AppReportImage>> readClipboard({bool skipIfText = false}) async {
    final reader = clipboardReader != null
        ? await clipboardReader!()
        : await SystemClipboard.instance?.read();
    if (reader == null) return const [];
    // Some Windows screenshot/history entries advertise text with no value.
    // Only actual text should take precedence in a text field.
    if (skipIfText && reader.canProvide(Formats.plainText)) {
      final text = await reader.readValue(Formats.plainText);
      if (text != null && text.isNotEmpty) return const [];
    }

    final images = <AppReportImage>[];
    // ב-Windows צילום של כלי החיתוך (DIB) ממומש כ-PNG, וקובץ שהועתק
    // בסייר מופיע גם הוא בפורמט התמונה שלו.
    for (final item in reader.items) {
      // GIF ראשון: פריט שמציע גם PNG מאבד בו את ההנפשה.
      for (final (format, mimeType, extension) in const [
        (Formats.gif, 'image/gif', 'gif'),
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
          final bytes = (file.fileSize ?? 0) > AppReportImage.maxBytes
              ? _oversized
              : await _readBounded(file.getStream());
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

  static Future<Uint8List> _readBounded(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > AppReportImage.maxBytes) {
        return _oversized;
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// פותח את בוחר הקבצים. מחזיר רשימה ריקה בביטול.
  Future<List<AppReportImage>> pickFiles({BuildContext? context}) async {
    final files =
        (await withFilePickerOwner(
          context,
          (picker) => picker.pickFiles(
            type: FileType.custom,
            allowedExtensions: AppReportImage.supportedExtensions,
            windowsOptions: modalWindowsOptions(context),
            linuxOptions: kModalLinuxOptions,
          ),
        )) ??
        [];
    final images = <AppReportImage>[];
    for (final file in files) {
      final mimeType = AppReportImage.mimeTypeForPath(file.name);
      if (mimeType == null) continue;
      images.add(
        AppReportImage(
          bytes: (await file.length() ?? 0) > AppReportImage.maxBytes
              ? _oversized
              : await _readBounded(file.readAsByteStream()),
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
          bytes: await File(path).length() > AppReportImage.maxBytes
              ? _oversized
              : await _readBounded(File(path).openRead()),
          fileName: path.split(RegExp(r'[\\/]')).last,
          mimeType: mimeType,
        ),
      );
    }
    return images;
  }
}
