import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// גרסת הפורמט הראשית של zdb ש-zvfs קורא. המיקום שלה בכותרת קבוע לתמיד,
/// וקורא דוחה כל major אחר — לכן בודקים אותה במניפסט עוד לפני ההורדה.
const int kSupportedZdbFormatMajor = 1;

/// יחס overlay/בסיס (בדיסק) שמעליו מורידים בסיס עדכני. overlay אינו מאט קריאות,
/// רק את הפתיחה הראשונה, ודחיסה מקומית יוצאת גדולה מבסיס טרי — ולכן היא גיבוי.
const double kZdbOverlayRebaseRatio = 0.5;

/// קובץ zdb שהורד או יובא אינו תואם למניפסט או לגרסה הצפויה.
class LibraryZdbVerificationException implements Exception {
  const LibraryZdbVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// שמות הקבצים שהתוכנה יוצרת ליד `seforim.zdb`.
abstract final class LibraryZdbFiles {
  static String zdbPathIn(String directory) =>
      p.join(directory, DatabaseConstants.zdbDatabaseFileName);

  /// יעד ההורדה, באותה תיקייה כדי שההתקנה תהיה rename. לא `.new`, שהוא
  /// הקובץ הזמני של הדחיסה ב-zvfs.
  static String downloadPathFor(String zdbPath) => '$zdbPath.download';

  static String compactionTempFor(String zdbPath) => '$zdbPath.new';
  static String installTempFor(String zdbPath) => '$zdbPath.install';

  /// seforim.db הרגיל ולוואיו.
  static const List<String> legacySuffixes = ['', '-journal', '-wal', '-shm'];

  static String legacyPathIn(String directory) =>
      p.join(directory, DatabaseConstants.databaseFileName);
}

/// זורק [LibraryZdbVerificationException] כשהגרסה הזו אינה יכולה לקרוא את
/// ה-zdb שבמניפסט. נבדק לפני ההורדה, כדי לא להוריד ~2GB לשווא.
void checkZdbManifestSupported(FullDbManifest manifest) {
  if (manifest.zdb.formatMajor != kSupportedZdbFormatMajor) {
    throw LibraryZdbVerificationException(
      'קובץ הספרייה בפורמט zdb ${manifest.zdb.formatMajor}, '
      'שהגרסה הזו אינה קוראת — נדרש עדכון אפליקציה',
    );
  }
  const readable = DatabaseConstants.readableDbSchemaVersion;
  if (manifest.dbSchemaVersion > readable) {
    throw LibraryZdbVerificationException(
      'קובץ הספרייה בסכמה ${manifest.dbSchemaVersion}, חדשה מהנתמכת '
      '($readable) — נדרש עדכון אפליקציה',
    );
  }
}

/// מאמת את [candidatePath] מול [manifest] (כשיש) ואת הגרסה שבתוכו, בלי פענוח
/// מלא. הכותרת והגרסה נקראות ב-isolate: הפתיחה חוסמת את מי שמבצע אותה.
Future<void> verifyZdbCandidate(
  String candidatePath, {
  FullDbManifest? manifest,
  int? expectedDbVersion,
}) async {
  if (manifest != null) {
    final size = await File(candidatePath).length();
    if (size != manifest.size) {
      throw LibraryZdbVerificationException(
        'גודל קובץ הספרייה ($size) אינו תואם למניפסט (${manifest.size})',
      );
    }
  }
  final expected = manifest == null
      ? null
      : (
          formatMajor: manifest.zdb.formatMajor,
          fileUuid: manifest.zdb.fileUuid,
          contentXxh64: manifest.zdb.contentXxh64,
          logicalSize: manifest.zdb.logicalSize,
          pageSize: manifest.zdb.pageSize,
          dictId: manifest.zdb.dictId,
          dbVersion: manifest.dbVersion,
          dbSchemaVersion: manifest.dbSchemaVersion,
        );
  final version = expectedDbVersion ?? manifest?.dbVersion;
  final mismatches = await Isolate.run(
    () => _candidateMismatches(candidatePath, expected, version),
  );
  if (mismatches.isNotEmpty) {
    throw LibraryZdbVerificationException(
      'קובץ הספרייה אינו תואם לצפוי: ${mismatches.join(', ')}',
    );
  }
}

typedef _ExpectedZdb = ({
  int formatMajor,
  String fileUuid,
  String contentXxh64,
  int logicalSize,
  int pageSize,
  int dictId,
  int dbVersion,
  int dbSchemaVersion,
});

List<String> _candidateMismatches(
  String path,
  _ExpectedZdb? expected,
  int? expectedDbVersion,
) {
  final header = readLibraryZdbHeader(path);
  final mismatches = <String>{
    if (header.formatMajor != kSupportedZdbFormatMajor)
      'formatMajor=${header.formatMajor}',
  };
  if (expected != null) {
    mismatches.addAll([
      if (header.formatMajor != expected.formatMajor)
        'formatMajor=${header.formatMajor}',
      if (header.fileUuidHex != expected.fileUuid)
        'fileUuid=${header.fileUuidHex}',
      if (header.contentXxh64Hex != expected.contentXxh64)
        'contentXxh64=${header.contentXxh64Hex}',
      if (header.logicalSize != expected.logicalSize)
        'logicalSize=${header.logicalSize}',
      if (header.pageSize != expected.pageSize) 'pageSize=${header.pageSize}',
      if (header.dictId != expected.dictId) 'dictId=${header.dictId}',
    ]);
  }
  // כותרת שאינה תואמת לא נפתחת ב-SQLite — הפתיחה משאירה -zlck לידה.
  if (mismatches.isNotEmpty) return mismatches.toList();
  ensureLibraryVfs();
  final LocalDbVersion version;
  try {
    version = const LocalDbVersionReader().read(path);
  } finally {
    // ה-candidate סגור כעת, וה-zlck שלו אינו שייך לשום מסד פתוח.
    _deleteQuietlySync('$path-zlck');
  }
  const readable = DatabaseConstants.readableDbSchemaVersion;
  final schema = version.schemaVersion;
  return <String>{
    if (expectedDbVersion != null && version.dbVersion != expectedDbVersion)
      'dbVersion=${version.dbVersion}',
    if (expected != null && schema != expected.dbSchemaVersion)
      'dbSchemaVersion=$schema',
    if (schema != null && schema > readable) 'dbSchemaVersion=$schema',
  }.toList();
}

/// היחס בין גודל ה-overlay לגודל הבסיס בדיסק; 0 בלי overlay, null כשאין בסיס.
Future<double?> zdbOverlayRatio(String zdbPath) async {
  try {
    final base = File(zdbPath);
    if (!await base.exists()) return null;
    final baseSize = await base.length();
    if (baseSize <= 0) return null;
    final overlay = File('$zdbPath-zovl');
    if (!await overlay.exists()) return 0;
    return await overlay.length() / baseSize;
  } on FileSystemException {
    return null;
  }
}

/// מוחק את seforim.db הרגיל ולוואיו מ-[directory]. זורק כשקובץ נשאר, כדי
/// שהקורא ידע שהעותק הישן עדיין תופס מקום.
Future<void> deleteLegacyLibraryDb(String directory) async {
  final legacy = LibraryZdbFiles.legacyPathIn(directory);
  FileSystemException? failure;
  // הלוואים קודם: journal שנשאר ליד בסיס שנמחק היה משוחזר על מסד חדש.
  for (final suffix in LibraryZdbFiles.legacySuffixes.reversed) {
    try {
      final file = File('$legacy$suffix');
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      failure ??= error;
    }
  }
  if (failure != null) throw failure;
}

/// מנקה שאריות הורדה/התקנה/דחיסה ליד seforim.zdb, ואת seforim.db כשיש zdb תקין.
/// לא נוגע ב-`-zlck`; הורדה עם קובץ resume נשמרת לבדיקת העדכון הבאה.
Future<void> cleanUpZdbLeftovers(String directory) async {
  final zdb = LibraryZdbFiles.zdbPathIn(directory);
  await _deleteQuietly(LibraryZdbFiles.compactionTempFor(zdb));
  await _deleteQuietly('${LibraryZdbFiles.compactionTempFor(zdb)}-zlck');
  await _deleteQuietly(LibraryZdbFiles.installTempFor(zdb));
  final download = LibraryZdbFiles.downloadPathFor(zdb);
  if (!await File(PatchDownloader.resumeSidecarPath(download)).exists()) {
    await _deleteQuietly(download);
  }
  if (!await File(download).exists()) await _deleteQuietly('$download-zlck');

  final legacy = LibraryZdbFiles.legacyPathIn(directory);
  if (!await File(legacy).exists() || !await File(zdb).exists()) return;
  // מוחקים גיגה-בייטים רק אחרי אימות הכותרת, לא לפי ה-magic בלבד.
  try {
    await Isolate.run(() => readLibraryZdbHeader(zdb));
  } catch (error) {
    debugPrint('[zdb cleanup] keeping ${p.basename(legacy)}: $error');
    return;
  }
  await deleteLegacyLibraryDb(directory);
}

Future<void> _deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException catch (error) {
    debugPrint('[zdb cleanup] $path: $error');
  }
}

void _deleteQuietlySync(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException catch (error) {
    debugPrint('[zdb cleanup] $path: $error');
  }
}
