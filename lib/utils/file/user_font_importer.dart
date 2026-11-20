import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

enum UserFontImportStatus {
  /// הקובץ הועתק לתיקיית האפליקציה והרשימה רועננה.
  imported,

  /// אותו קובץ כבר יובא בעבר; לא נוצר עותק.
  alreadyImported,

  /// לא קובץ גופן (סיומת או תוכן).
  notAFont,

  /// גופן תקין אבל בלי אותיות עבריות.
  noHebrew,

  /// גדול מהמגבלה.
  tooLarge,

  /// קריאה או כתיבה נכשלו.
  failed,
}

class UserFontImportResult {
  final UserFontImportStatus status;

  /// משפחות הגופן העבריות שבקובץ (ריק כשהייבוא לא הצליח).
  final List<String> families;

  const UserFontImportResult(this.status, [this.families = const []]);

  bool get succeeded =>
      status == UserFontImportStatus.imported ||
      status == UserFontImportStatus.alreadyImported;
}

/// מייבא קובץ גופן שהמשתמש בחר: מאמת אותו, ומעתיק לתיקיית האפליקציה שאותה
/// סורק סורק הגופנים כמו כל תיקיית גופנים אחרת (כולל אוספי `.ttc`/`.otc`).
///
/// אין כאן תלות בממשק או בפלטפורמה: [inspect] מחזיר את המשפחות העבריות שבקובץ
/// ו-[onChanged] מרענן את הרשימה. כך הבדיקות רצות על קבצים אמיתיים בלי isolate.
class UserFontImporter {
  static const int defaultMaxBytes = 64 * 1024 * 1024;
  static const Set<String> _extensions = {'.ttf', '.otf', '.ttc', '.otc'};

  final String directory;
  final Future<List<String>> Function(String path) inspect;
  final Future<void> Function() onChanged;
  final int maxBytes;

  const UserFontImporter({
    required this.directory,
    required this.inspect,
    required this.onChanged,
    this.maxBytes = defaultMaxBytes,
  });

  Future<UserFontImportResult> importFile(String sourcePath) async {
    final source = File(sourcePath);
    try {
      if (!_extensions.contains(p.extension(sourcePath).toLowerCase())) {
        return const UserFontImportResult(UserFontImportStatus.notAFont);
      }
      final length = await source.length();
      if (length > maxBytes) {
        return const UserFontImportResult(UserFontImportStatus.tooLarge);
      }
      if (!await _hasFontSignature(source)) {
        return const UserFontImportResult(UserFontImportStatus.notAFont);
      }
      final families = await inspect(sourcePath);
      if (families.isEmpty) {
        return const UserFontImportResult(UserFontImportStatus.noHebrew);
      }
      final bytes = await source.readAsBytes();
      final target = _targetFor(sourcePath, bytes);
      if (target.existing) {
        return UserFontImportResult(
          UserFontImportStatus.alreadyImported,
          families,
        );
      }
      await _writeAtomically(target.file, bytes);
      await onChanged();
      return UserFontImportResult(UserFontImportStatus.imported, families);
    } on FileSystemException {
      return const UserFontImportResult(UserFontImportStatus.failed);
    }
  }

  /// TrueType (0x00010000 או "true"), OpenType CFF ("OTTO"), אוסף ("ttcf").
  static Future<bool> _hasFontSignature(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(4);
      if (head.length < 4) return false;
      final tag = String.fromCharCodes(head);
      return tag == 'OTTO' ||
          tag == 'true' ||
          tag == 'ttcf' ||
          (head[0] == 0 && head[1] == 1 && head[2] == 0 && head[3] == 0);
    } finally {
      await raf.close();
    }
  }

  /// שם בטוח לנתיב. קובץ באותו שם ובאותו תוכן נחשב כבר מיובא; באותו שם ותוכן
  /// אחר נשמר בשם עם מספר, כדי לא לדרוס גופן קיים.
  ({File file, bool existing}) _targetFor(String sourcePath, Uint8List bytes) {
    final extension = p.extension(sourcePath).toLowerCase();
    var base = p
        .basenameWithoutExtension(sourcePath)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (!RegExp('[A-Za-z0-9]').hasMatch(base)) base = 'font';
    for (var n = 1; ; n++) {
      final name = n == 1 ? '$base$extension' : '${base}_$n$extension';
      final file = File(p.join(directory, name));
      if (!file.existsSync()) return (file: file, existing: false);
      if (file.lengthSync() == bytes.length &&
          _sameBytes(file.readAsBytesSync(), bytes)) {
        return (file: file, existing: true);
      }
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _writeAtomically(File target, Uint8List bytes) async {
    await Directory(directory).create(recursive: true);
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } on FileSystemException {
      if (temporary.existsSync()) temporary.deleteSync();
      rethrow;
    }
  }
}
