import 'dart:io';
import 'dart:isolate';

import 'package:convert/convert.dart';
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
    // user_books.db מגיע לכמה מאות MB; גיבוב ודחיסה ב-isolate הראשי תוקעים את ה-UI.
    final hex = await Isolate.run(() => sha256.convert(bytes).toString());
    final target = File(_pathForHash(hex));
    if (await target.exists()) return '$hashPrefix$hex';

    await target.parent.create(recursive: true);
    final tmp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final compressed = await Isolate.run(() => gzip.encode(bytes));
    await tmp.writeAsBytes(compressed, flush: true);
    try {
      await tmp.rename(target.path);
    } catch (_) {
      // מופע אחר כתב את אותו blob במקביל — התוכן זהה לפי הגדרה.
      if (!await target.exists()) rethrow;
      await tmp.delete();
    }
    return '$hashPrefix$hex';
  }

  /// שומר קובץ במחסן במקטעים ומחזיר את ההפניה לתוכנו.
  Future<String> putFile(File source) {
    final absoluteSource = source.absolute;
    final storePath = Directory(objectsPath).absolute.path;
    return Isolate.run(() => _putFile(absoluteSource, storePath));
  }

  static Future<String> _putFile(File source, String storePath) async {
    final store = BackupStore(storePath);
    final input = await source.open();
    try {
      final initialHash = (await sha256.bind(_readChunks(input)).single)
          .toString();
      if (await File(store._pathForHash(initialHash)).exists()) {
        return '$hashPrefix$initialHash';
      }

      final parent = await Directory(storePath).create(recursive: true);
      final staging = await parent.createTemp('.backup-');
      final tmp = File(p.join(staging.path, 'blob.tmp'));
      try {
        await input.setPosition(0);
        final hex = await _writeCompressedFile(input, tmp);
        final ref = '$hashPrefix$hex';
        final target = File(store._pathForHash(hex));
        if (await target.exists()) return ref;

        await target.parent.create(recursive: true);
        try {
          await tmp.rename(target.path);
        } on FileSystemException {
          if (!await target.exists()) rethrow;
        }
        return ref;
      } finally {
        await staging.delete(recursive: true);
      }
    } finally {
      await input.close();
    }
  }

  static Stream<List<int>> _readChunks(RandomAccessFile input) async* {
    const chunkBytes = 256 * 1024;
    while (true) {
      final bytes = await input.read(chunkBytes);
      if (bytes.isEmpty) return;
      yield bytes;
    }
  }

  static Future<String> _writeCompressedFile(
    RandomAccessFile input,
    File target,
  ) async {
    // הקובץ יכול להשתנות בין הקריאות, ולכן ההפניה נקבעת בזמן הדחיסה.
    final digest = AccumulatorSink<Digest>();
    final hasher = sha256.startChunkedConversion(digest);
    final chunks = _readChunks(input).map((chunk) {
      hasher.add(chunk);
      return chunk;
    });
    final output = await target.open(mode: FileMode.write);
    try {
      await for (final compressed in gzip.encoder.bind(chunks)) {
        await output.writeFrom(compressed);
      }
      hasher.close();
      await output.flush();
      return digest.events.single.toString();
    } finally {
      await output.close();
    }
  }

  /// קורא blob לפי הפניה ומאמת את ה-hash. מחזיר null אם חסר או פגום.
  Future<List<int>?> getBytes(String hashRef) async {
    if (!isHashRef(hashRef)) return null;
    final hex = hashRef.substring(hashPrefix.length);
    final file = File(_pathForHash(hex));
    if (!await file.exists()) return null;
    try {
      final compressed = await file.readAsBytes();
      final (bytes, actual) = await Isolate.run(() {
        final bytes = gzip.decode(compressed);
        return (bytes, sha256.convert(bytes).toString());
      });
      if (actual != hex) {
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
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } on FileSystemException {
        // putBytes או sweep הזיזו את הקובץ אחרי שנמנה.
      }
    }
    return total;
  }

  /// Mark & Sweep: מוחק blobs שאינם ב-[referenced] וגילם עולה על [grace].
  ///
  /// ה-grace מגן מפני מחיקת blob שנכתב זה עתה ע"י מופע/מחשב אחר החולק את
  /// תיקיית הגיבוי (למשל תיקייה מסונכרנת לענן), לפני שהמניפסט שלו הגיע.
  /// מחזיר את מספר הבייטים שהתפנו.
  Future<int> sweep(
    Set<String> referenced, {
    Duration grace = const Duration(days: 30),
  }) async {
    final dir = Directory(objectsPath);
    if (!await dir.exists()) return 0;

    final cutoff = DateTime.now().subtract(grace);
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
        freedBytes += size;
      } catch (e) {
        _logger.warning('Failed to sweep blob $name: $e');
      }
    }
    return freedBytes;
  }

  /// אוסף את כל הפניות ה-blob ממניפסט גיבוי (סעיפי `files`/`data` בתוספים,
  /// ו-user_books.db).
  static Set<String> collectRefs(Map<String, dynamic> manifest) {
    final refs = <String>{};
    final userBooks = manifest['userBooks'];
    if (userBooks is String && isHashRef(userBooks)) refs.add(userBooks);
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
