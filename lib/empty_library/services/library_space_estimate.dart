import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/text/byte_size_text.dart';
import 'package:path/path.dart' as p;

/// גודל הקובץ המרבי ב-FAT32: 4GiB פחות בייט.
const int fat32MaxFileBytes = 0xFFFFFFFF;

/// יחסי התפיחה כשגודל הארכיון המלא אינו ידוע. נמדדו על
/// הגרסאות הנוכחיות ועוגלו כלפי מעלה; כולם נבדקים מול [measuredLibraryDownload].
abstract final class ExpansionFallback {
  /// seforim.db: נמדד 2.07 (1.807GB ← 3.739GB). גם ארכיון הספרייה של המסייע.
  static const double database = 2.5;

  /// אינדקס החיפוש המוכן: נמדד 1.40 (1.725GB ← 2.413GB).
  static const double searchIndex = 1.6;

  /// קטלוג אוצר הספרים: נמדד 6.3 (6MB ← 37.6MB).
  static const double catalog = 8;

  /// ארכיון PDF (תלמוד בבלי): כמעט אינו נדחס, נמדד 1.003.
  static const double pdfArchive = 1.1;
}

/// גודל דחוס וגודל אחרי חילוץ של נכס אחד.
typedef ArchiveSize = ({int compressed, int extracted});

/// seforim.db ב-release v38 (נובמבר 2026), כאשר אין גודל עדכני מהרשת.
const int measuredDatabaseBytes = 4418928640;

/// הנכסים של הורדה ראשונית בגדלים שנמדדו, כשגודל חסר במטא-דאטה.
const ArchiveSize measuredDatabaseArchive = (
  compressed: 2246741848,
  extracted: measuredDatabaseBytes,
);
const ArchiveSize measuredTalmudArchive = (
  compressed: 472000000,
  extracted: 473500000,
);
const ArchiveSize measuredCatalogArchive = (
  compressed: 6000000,
  extracted: 37600000,
);
const ArchiveSize measuredLexicalArchive = (
  compressed: 57000000,
  extracted: 57000000,
);

const List<ArchiveSize> measuredLibraryDownload = [
  measuredDatabaseArchive,
  measuredTalmudArchive,
  measuredCatalogArchive,
  measuredLexicalArchive,
];

/// `Frame_Content_Size` מכותרת ה-frame הראשון, או null כשאינו רשום
/// (דחיסה מצינור) או כשהבייטים אינם frame של zstd.
int? zstdFrameContentSize(List<int> header) {
  if (header.length < 5 ||
      header[0] != 0x28 ||
      header[1] != 0xB5 ||
      header[2] != 0x2F ||
      header[3] != 0xFD) {
    return null;
  }
  final descriptor = header[4];
  final fcsFlag = descriptor >> 6;
  final singleSegment = (descriptor >> 5) & 1 == 1;
  const dictionaryIdBytes = [0, 1, 2, 4];
  final fcsBytes = switch (fcsFlag) {
    0 => singleSegment ? 1 : 0,
    1 => 2,
    2 => 4,
    _ => 8,
  };
  if (fcsBytes == 0) return null;
  final offset =
      5 + (singleSegment ? 0 : 1) + dictionaryIdBytes[descriptor & 3];
  if (header.length < offset + fcsBytes) return null;
  var value = 0;
  for (var i = fcsBytes - 1; i >= 0; i--) {
    value = (value << 8) | header[offset + i];
  }
  // בשדה של שני בייטים הערך מוסט ב-256 לפי התקן.
  return fcsBytes == 2 ? value + 256 : value;
}

/// מגבלת הקריאה לבדיקת גודל מלא; ארכיונים גדולים נשארים בגדר אומדן.
const int zstdSizeProbeMaxBytes = 4 << 20;

/// גודל התוכן רק כשהארכיון כולו קטן ונקרא, ולכל frame יש גודל מפורש.
/// אין פענוח של התוכן ואין סריקה נוספת של ארכיונים גדולים.
Future<int?> readZstdArchiveContentSize(
  Stream<List<int>> stream, {
  required int compressedSize,
}) async {
  if (compressedSize <= 0 || compressedSize > zstdSizeProbeMaxBytes) {
    return null;
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > compressedSize) return null;
    bytes.add(chunk);
  }
  if (bytes.length != compressedSize) return null;
  return _zstdArchiveContentSize(bytes.takeBytes());
}

int? _zstdArchiveContentSize(List<int> bytes) {
  int littleEndian(int offset, int length) {
    var value = 0;
    for (var i = length - 1; i >= 0; i--) {
      value = (value << 8) | bytes[offset + i];
    }
    return value;
  }

  var offset = 0;
  var total = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 8) return null;
    final magic = littleEndian(offset, 4);
    if (magic & 0xFFFFFFF0 == 0x184D2A50) {
      offset += 8 + littleEndian(offset + 4, 4);
      if (offset > bytes.length) return null;
      continue;
    }
    if (magic != 0xFD2FB528) return null;
    final descriptor = bytes[offset + 4];
    if (descriptor & 8 != 0) return null;
    final singleSegment = descriptor & 0x20 != 0;
    final fcsBytes = switch (descriptor >> 6) {
      0 => singleSegment ? 1 : 0,
      1 => 2,
      2 => 4,
      _ => 8,
    };
    final headerBytes =
        5 +
        (singleSegment ? 0 : 1) +
        const [0, 1, 2, 4][descriptor & 3] +
        fcsBytes;
    if (offset + headerBytes > bytes.length) return null;
    final contentSize = zstdFrameContentSize(
      bytes.sublist(offset, offset + headerBytes),
    );
    if (contentSize == null || contentSize < 0 || total + contentSize < total) {
      return null;
    }
    total += contentSize;
    offset += headerBytes;
    var last = false;
    while (!last) {
      if (offset + 3 > bytes.length) return null;
      final block = littleEndian(offset, 3);
      last = block & 1 != 0;
      final type = (block >> 1) & 3;
      if (type == 3 || block >> 3 > 128 << 10) return null;
      offset += 3 + (type == 1 ? 1 : block >> 3);
      if (offset > bytes.length) return null;
    }
    if (descriptor & 4 != 0) offset += 4;
    if (offset > bytes.length) return null;
  }
  return total;
}

/// הגודל המלא כשידוע, אחרת אומדן לפי [fallbackRatio] — אינו גבול עליון.
int extractedSizeOf(
  int compressedSize, {
  int? archiveContentSize,
  required double fallbackRatio,
}) => archiveContentSize ?? (compressedSize * fallbackRatio).ceil();

/// גודל ה-DB לפי כותרת ה-frame הראשון. אם הפורמט ישתנה למספר frames,
/// הגודל המחולץ הכולל ידרוש מטא-דאטה נוספת; הרצפה כאן היא אומדן בלבד.
/// בהיעדר FCS נשאר אומדן שמרני התלוי בגודל ה-release, ולא בקבוע ישן.
int estimatedDatabaseExtractedSize(
  int compressedSize, {
  int? firstFrameSize,
}) {
  if (firstFrameSize != null && firstFrameSize > 0) {
    return math.max(firstFrameSize, (compressedSize * 1.9).ceil());
  }
  if (compressedSize <= 0) return measuredDatabaseBytes;
  return extractedSizeOf(
    compressedSize,
    fallbackRatio: ExpansionFallback.database,
  );
}

/// מרווח ביטחון: 5% ולא פחות מ-256MiB (מטא-דאטה של מערכת הקבצים, WAL).
int withSafetyMargin(int bytes) =>
    bytes <= 0 ? 0 : bytes + math.max(256 << 20, bytes ~/ 20);

/// השיא שהחילוץ מוסיף כשהארכיונים נמחקים בזה אחר זה: לפני נכס i כבר
/// חולצו הקודמים וקבציהם הדחוסים נמחקו, והדחוס של i עוד קיים.
int peakExtractionGrowth(List<ArchiveSize> items) {
  var peak = 0;
  var growth = 0;
  for (final item in items) {
    peak = math.max(peak, growth + item.extracted);
    growth += item.extracted - item.compressed;
  }
  return peak;
}

/// דרישת מקום של מיקום אחד. [volumeId] null — לא ידוע אם חולק כונן.
class VolumeSpaceNeed {
  const VolumeSpaceNeed({
    required this.label,
    required this.volumeId,
    required this.requiredBytes,
    required this.freeBytes,
  });

  final String label;
  final String? volumeId;
  final int requiredBytes;

  /// -1 כשלא ניתן לקבוע; אז המיקום אינו נחסם.
  final int freeBytes;

  bool get isShort => freeBytes >= 0 && freeBytes < requiredBytes;

  String describe() =>
      '$label: נדרש ${formatMegabytesLtr(requiredBytes, fractionDigits: 0)}, '
      'פנוי ${formatMegabytesLtr(freeBytes, fractionDigits: 0)}.';
}

/// מאחד דרישות של מיקומים על אותו כונן ומחזיר את אלה שאין בהם די מקום.
List<VolumeSpaceNeed> spaceShortfalls(List<VolumeSpaceNeed> needs) {
  final merged = <VolumeSpaceNeed>[];
  for (final need in needs.where((n) => n.requiredBytes > 0)) {
    final index = need.volumeId == null
        ? -1
        : merged.indexWhere((m) => m.volumeId == need.volumeId);
    if (index < 0) {
      merged.add(need);
      continue;
    }
    final existing = merged[index];
    merged[index] = VolumeSpaceNeed(
      label: '${existing.label} + ${need.label} (אותו כונן)',
      volumeId: existing.volumeId,
      requiredBytes: existing.requiredBytes + need.requiredBytes,
      freeBytes: existing.freeBytes,
    );
  }
  return merged.where((n) => n.isShort).toList();
}

/// הודעה לכל מיקום שחסר בו מקום, או null כשהכול מספיק.
String? insufficientSpaceMessage(List<VolumeSpaceNeed> needs) {
  final shortfalls = spaceShortfalls(needs);
  if (shortfalls.isEmpty) return null;
  return 'אין מספיק מקום פנוי.\n'
      '${shortfalls.map((n) => n.describe()).join('\n')}\n'
      'יש לפנות מקום ולנסות שוב.';
}

/// FAT32 חוסם רק קובץ יחיד מעל 4GiB-1. גודל לא ידוע אינו חוסם — הכתיבה
/// עצמה תיכשל אם הוא בכל זאת גדול מדי.
bool exceedsFat32FileLimit(int? largestFileBytes) =>
    largestFileBytes != null && largestFileBytes > fat32MaxFileBytes;

/// כרך בלי תמיכה בקבצים גדולים (FAT32) נחסם רק כשהקובץ הגדול חורג.
bool volumeCanHoldLibrary({
  required bool supportsLargeFiles,
  required int? largestFileBytes,
}) => supportsLargeFiles || !exceedsFat32FileLimit(largestFileBytes);

/// גודל seforim.db שבתיקיית הספרים, או [measuredDatabaseBytes] כשאינו קיים.
Future<int> installedDatabaseBytes(String booksPath) async {
  if (booksPath.isEmpty) return measuredDatabaseBytes;
  final db = File(p.join(booksPath, DatabaseConstants.databaseFileName));
  try {
    return await db.length();
  } on FileSystemException {
    return measuredDatabaseBytes;
  }
}

final _androidInternalPath = RegExp(
  r'^/(data|storage/emulated|storage/self|sdcard)(/|$)',
);

/// מזהה כונן להשוואה. באנדרואיד `/data` ו-`/storage/emulated` הם אותו אחסון
/// פנימי, אך df מדווח עליהם מערכות קבצים שונות (FUSE מעל `/data/media`).
String? comparableVolumeId(
  String path,
  String? volumeId, {
  required bool isAndroid,
}) {
  if (volumeId == null || !isAndroid) return volumeId;
  return _androidInternalPath.hasMatch(path) ? 'android-internal' : volumeId;
}

/// האם [a] ו-[b] על אותו כונן, לפי [comparableVolumeId].
bool isSameVolume(
  String a,
  DiskSpaceInfo aInfo,
  String b,
  DiskSpaceInfo bInfo, {
  required bool isAndroid,
}) {
  final aId = comparableVolumeId(a, aInfo.volumeId, isAndroid: isAndroid);
  return aId != null &&
      aId == comparableVolumeId(b, bInfo.volumeId, isAndroid: isAndroid);
}
