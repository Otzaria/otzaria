import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// מחסן תוכן לפי כתובת (Content-Addressable Store) עבור קבצי גיבוי.
///
/// כל blob נשמר פעם אחת תחת ה-sha256 של תוכנו (דחוס gzip), כך שקבצי תוסף
/// זהים בין גיבויים אינם נכתבים שוב. מניפסטים של גיבוי מפנים ל-blobs
/// באמצעות מחרוזת `sha256:<hex>`.
class BackupStore {
  static final Logger _logger = Logger('BackupStore');
  static const String hashPrefix = 'sha256:';

  /// תיקיית השורש של האובייקטים: `<backupDir>/store/objects`.
  final String objectsPath;

  BackupStore(this.objectsPath);

  /// יוצר store עבור תיקיית גיבוי נתונה.
  factory BackupStore.forBackupDir(String backupDir) =>
      BackupStore(p.join(backupDir, 'store', 'objects'));

  /// האם הערך הוא הפניה ל-blob (להבדיל מ-base64 מוטמע בפורמט v1).
  static bool isHashRef(String value) => value.startsWith(hashPrefix);

  String _pathForHash(String hex) =>
      p.join(objectsPath, hex.substring(0, 2), hex);

  /// שומר בייטים במחסן ומחזיר את ההפניה (`sha256:<hex>`).
  /// אם ה-blob כבר קיים — לא נכתב דבר (אידמפוטנטי).
  Future<String> putBytes(List<int> bytes) async {
    final hex = sha256.convert(bytes).toString();
    final target = File(_pathForHash(hex));
    if (await target.exists()) return '$hashPrefix$hex';

    await target.parent.create(recursive: true);
    final tmp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsBytes(gzip.encode(bytes), flush: true);
    try {
      await tmp.rename(target.path);
    } catch (_) {
      // מופע אחר כתב את אותו blob במקביל — התוכן זהה לפי הגדרה.
      if (!await target.exists()) rethrow;
      await tmp.delete();
    }
    return '$hashPrefix$hex';
  }

  /// קורא blob לפי הפניה ומאמת את ה-hash. מחזיר null אם חסר או פגום.
  Future<List<int>?> getBytes(String hashRef) async {
    if (!isHashRef(hashRef)) return null;
    final hex = hashRef.substring(hashPrefix.length);
    final file = File(_pathForHash(hex));
    if (!await file.exists()) return null;
    try {
      final bytes = gzip.decode(await file.readAsBytes());
      if (sha256.convert(bytes).toString() != hex) {
        _logger.warning('Corrupt blob (hash mismatch): $hex');
        return null;
      }
      return bytes;
    } catch (e) {
      _logger.warning('Failed to read blob $hex: $e');
      return null;
    }
  }

  Future<bool> exists(String hashRef) async {
    if (!isHashRef(hashRef)) return false;
    final hex = hashRef.substring(hashPrefix.length);
    return File(_pathForHash(hex)).exists();
  }

  /// גודל כולל של המחסן בבייטים (על הדיסק, אחרי דחיסה).
  Future<int> totalSize() async {
    final dir = Directory(objectsPath);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Mark & Sweep: מוחק blobs שאינם ב-[referenced] וגילם עולה על [grace].
  ///
  /// ה-grace מגן מפני מחיקת blob שנכתב זה עתה ע"י מופע/מחשב אחר החולק את
  /// תיקיית הגיבוי (למשל תיקייה מסונכרנת לענן), לפני שהמניפסט שלו הגיע.
  /// מחזיר (מספר קבצים שנמחקו, בייטים שהתפנו).
  Future<({int deleted, int freedBytes})> sweep(
    Set<String> referenced, {
    Duration grace = const Duration(days: 30),
  }) async {
    final dir = Directory(objectsPath);
    if (!await dir.exists()) return (deleted: 0, freedBytes: 0);

    final cutoff = DateTime.now().subtract(grace);
    var deleted = 0;
    var freedBytes = 0;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.tmp')) continue;
      if (referenced.contains('$hashPrefix$name')) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        final size = stat.size;
        await entity.delete();
        deleted++;
        freedBytes += size;
      } catch (e) {
        _logger.warning('Failed to sweep blob $name: $e');
      }
    }
    return (deleted: deleted, freedBytes: freedBytes);
  }

  /// אוסף את כל הפניות ה-blob ממניפסט גיבוי (סעיפי `files`/`data` בתוספים).
  static Set<String> collectRefs(Map<String, dynamic> manifest) {
    final refs = <String>{};
    final plugins = manifest['plugins'];
    if (plugins is! List) return refs;
    for (final entry in plugins) {
      if (entry is! Map) continue;
      for (final section in ['files', 'data']) {
        final files = entry[section];
        if (files is! Map) continue;
        for (final value in files.values) {
          if (value is String && isHashRef(value)) refs.add(value);
        }
      }
    }
    return refs;
  }
}
