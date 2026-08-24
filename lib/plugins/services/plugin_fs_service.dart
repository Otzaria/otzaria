import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/services/plugin_path_safety.dart';

/// רשומה במרחב הפרטי של תוסף — קובץ או תיקייה, עם נתיב **יחסי** לשורש בלבד.
/// הנתיב המוחלט אינו נחשף לתוסף (הוא מכיל את שם המשתמש במערכת).
class PluginWorkspaceEntry {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  const PluginWorkspaceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modified,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'type': isDirectory ? 'dir' : 'file',
    'size': size,
    'modified': modified?.toUtc().toIso8601String(),
  };
}

/// שירות פעולות קבצים עבור גשר התוספים: חילוץ ZIP, מחיקת קובץ, והמרחב הפרטי.
///
/// משמש את ה-RPC `fs.extractZip` ו-`fs.deleteFile`. כל הפעולות מתבצעות בצד
/// אוצריא (Flutter), מכיוון שה-WebView של התוסף נטען מ-origin `file://` ואינו
/// יכול לכתוב/למחוק בדיסק.
///
/// **גבול אבטחה:** ב-[extractZip] ו-[deleteFile] השירות מבצע את הפעולה על
/// הנתיב שמועבר אליו כפי שהוא. האחריות לוודא שהנתיב נמצא בתוך תיקייה שהמשתמש
/// אישר במפורש (דרך `ui.pickFolder`) מוטלת על הקורא — `PluginBridgeAdapter`.
/// בנוסף, [extractZip] אוכף תקרות גודל ומספר רשומות ומדלג על רשומות שיוצאות
/// מתיקיית היעד (path-traversal) או על symlinks.
///
/// פעולות **המרחב הפרטי** (`workspace*`) הן ההיפך: הן מקבלות שורש ונתיב יחסי,
/// ואוכפות בעצמן את הגבול דרך [resolveWithinRoot] — כל נתיב שיוצא מהשורש נדחה
/// ב-`error.forbidden`, גם דרך `..` וגם דרך symlink.
class PluginFsService {
  /// תקרת הגודל הכולל (לא דחוס) שמותר לחלץ. חילוץ שחורג ממנה נקטע
  /// ב-`error.too_large` — הגנת zip bomb (ארכיון דחוס קטן שמתרחב לגיגה-בייטים).
  final int maxUncompressedBytes;

  /// תקרת מספר הרשומות בארכיון. חוסמת ארכיון עם המוני רשומות זעירות.
  final int maxEntries;

  /// מכסת הדיסק של המרחב הפרטי של תוסף אחד. תיקיית הנתונים של התוסף נכנסת
  /// בשלמותה לכל ארכיון גיבוי, ולכן המכסה גם חוסמת ניפוח של הגיבויים.
  final int maxWorkspaceBytes;

  /// תקרת הגודל של קריאה/כתיבה בודדת דרך ערוץ ה-RPC. הגשר מעביר את התוכן
  /// כמחרוזת JSON; לקבצים גדולים יש את שרת הקבצים ואת `ui.pickFolder`.
  final int maxTransferBytes;

  /// תקרת מספר הרשומות במרחב הפרטי. קובץ ריק ותיקייה אינם צורכים בתים, ולכן
  /// המכסה לבדה מתירה מאות אלפי רשומות — שמייקרות כל סריקה ואת הגיבוי.
  final int maxWorkspaceEntries;

  /// תקרת עומק הנתיב במרחב הפרטי, ביחס לשורש.
  final int maxWorkspaceDepth;

  PluginFsService({
    this.maxUncompressedBytes = 2 * 1024 * 1024 * 1024,
    this.maxEntries = 50000,
    this.maxWorkspaceBytes = 100 * 1024 * 1024,
    this.maxTransferBytes = 10 * 1024 * 1024,
    this.maxWorkspaceEntries = 10000,
    this.maxWorkspaceDepth = 32,
  });

  /// מחלצת את ארכיון ה-ZIP שב-[zipPath] אל [destFolder].
  ///
  /// יוצרת את [destFolder] אם אינה קיימת. החילוץ מתבצע ב-streaming רשומה-רשומה
  /// (ללא טעינת הארכיון כולו לזיכרון), כשבכל רשומה נאכפות התקרות
  /// [maxUncompressedBytes] ו-[maxEntries] — כך תוסף לא-מהימן אינו יכול למלא
  /// את הדיסק או לתקוע את ה-RPC עם zip bomb.
  ///
  /// זורקת [Exception] אם הקובץ ב-[zipPath] אינו קיים, אם החילוץ נכשל, או
  /// `error.too_large` אם הארכיון חורג מאחת התקרות.
  Future<void> extractZip(String zipPath, String destFolder) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('error.not_found: zip file does not exist');
    }
    await Directory(destFolder).create(recursive: true);

    final realDest = Directory(destFolder).resolveSymbolicLinksSync();
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      var entryCount = 0;
      var totalBytes = 0;
      for (final file in archive) {
        if (++entryCount > maxEntries) {
          throw Exception('error.too_large: archive has too many entries');
        }
        if (file.isSymbolicLink) {
          continue;
        }

        final outPath = p.join(destFolder, p.normalize(file.name));
        // הנתיב הקנוני האמיתי (כולל פתרון symlink-תיקייה קיים ביעד) חייב
        // להישאר בתוך היעד — נבדק *לפני* כל יצירת תיקייה, כדי שגם רשומת תיקייה
        // או אב של קובץ לא ייצרו תיקיות מחוץ ליעד דרך symlink, וגם `../` נחסם.
        final canonical = canonicalizeNearestExisting(outPath);
        if (canonical == null ||
            (!p.equals(canonical, realDest) &&
                !p.isWithin(realDest, canonical))) {
          continue;
        }

        if (file.isDirectory) {
          await Directory(outPath).create(recursive: true);
          continue;
        }

        // בדיקה מקדימה לפי הגודל המוצהר — חוסמת קובץ ענק עוד לפני כתיבתו.
        if (totalBytes + file.size > maxUncompressedBytes) {
          throw Exception('error.too_large: extracted size exceeds limit');
        }
        await File(outPath).parent.create(recursive: true);
        // קובץ-symlink קיים ייכתב דרכו אל היעד שלו; מוחקים כדי לכתוב קובץ רגיל.
        if (FileSystemEntity.isLinkSync(outPath)) {
          Link(outPath).deleteSync();
        }
        final output = OutputFileStream(outPath);
        try {
          file.writeContent(output);
        } finally {
          await output.close();
        }
        // הגודל המוצהר עלול לשקר; סופרים את מה שנכתב בפועל ובודקים שוב.
        totalBytes += output.length;
        if (totalBytes > maxUncompressedBytes) {
          throw Exception('error.too_large: extracted size exceeds limit');
        }
      }
    } finally {
      await input.close();
    }
  }

  /// מוחקת את הקובץ ב-[path].
  ///
  /// אם הקובץ אינו קיים — מסתיימת בשקט (idempotent), כך שניקוי חוזר אינו
  /// נכשל. אם [path] מצביע על תיקייה — זורקת, מכיוון ש-`fs.deleteFile`
  /// מיועדת לקבצים בלבד.
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    if (await Directory(path).exists()) {
      throw Exception('error.invalid_params: path is a directory');
    }
    // הקובץ אינו קיים — אין מה למחוק, פעולה idempotent ללא שגיאה.
  }

  // ================================================================
  // המרחב הפרטי של התוסף
  // ================================================================

  /// פותרת [relativePath] בתוך [root], או זורקת `error.forbidden` אם הוא יוצא
  /// מהשורש. כל פעולה במרחב הפרטי עוברת דרך כאן — זהו הגבול היחיד.
  String _resolve(String root, String relativePath) {
    final resolved = resolveWithinRoot(root, relativePath);
    if (resolved == null) {
      throw Exception('error.forbidden: path escapes the plugin workspace');
    }
    return resolved;
  }

  /// יוצרת את שורש המרחב הפרטי אם אינו קיים, ומחזירה אותו.
  Future<String> ensureWorkspace(String root) async {
    await Directory(root).create(recursive: true);
    return root;
  }

  /// סך הבתים התפוסים במרחב. symlinks אינם נספרים — הם אינם צורכים מכסה,
  /// והתוכן שהם מצביעים אליו אינו של התוסף.
  ///
  /// התוצאה נשמרת במונה מתוחזק ומתעדכנת בכל מוטציה, כדי שכתיבה לא תסרוק את
  /// המרחב כולו — סריקה בכל כתיבה הפכה את הפעולה לריבועית.
  Future<int> workspaceUsedBytes(String root) async =>
      (await _usageOf(root)).bytes;

  /// מספר הרשומות (קבצים ותיקיות) במרחב.
  Future<int> workspaceEntryCount(String root) async =>
      (await _usageOf(root)).entries;

  /// שורשים שאינם בשימוש עוד — הנתונים נמחקו או שהתוסף הוסר.
  static void forgetWorkspace(String root) {
    _usageCache.remove(canonicalizeNearestExisting(root) ?? root);
  }

  static final Map<String, _WorkspaceUsage> _usageCache = {};
  static final Map<String, Future<void>> _locks = {};

  String _usageKey(String root) => canonicalizeNearestExisting(root) ?? root;

  Future<_WorkspaceUsage> _usageOf(String root) async {
    final key = _usageKey(root);
    final cached = _usageCache[key];
    if (cached != null) return cached;
    return _usageCache[key] = await _scanUsage(root);
  }

  Future<_WorkspaceUsage> _scanUsage(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) return _WorkspaceUsage();
    final usage = _WorkspaceUsage();
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (await FileSystemEntity.isLink(entity.path)) continue;
      usage.entries++;
      if (entity is File) usage.bytes += await entity.length();
    }
    return usage;
  }

  /// מסרלת פעולות על אותו מרחב. בלי זה חישוב התפוסה והכתיבה שאחריו אינם
  /// אטומיים, ומטח כתיבות מקבילות עובר את המכסה כאילו כל אחת היחידה.
  Future<T> _locked<T>(String root, Future<T> Function() action) async {
    final key = _usageKey(root);
    final previous = _locks[key];
    final gate = Completer<void>();
    _locks[key] = gate.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (_locks[key] == gate.future) _locks.remove(key);
      gate.complete();
    }
  }

  /// עומק [relativePath] ביחס לשורש, לאכיפת [maxWorkspaceDepth].
  void _checkDepth(String relativePath) {
    final segments = p
        .split(p.normalize(relativePath))
        .where((s) => s.isNotEmpty && s != '.');
    if (segments.length > maxWorkspaceDepth) {
      throw Exception('error.too_large: path is nested too deeply');
    }
  }

  /// כותבת [bytes] אל [relativePath] במרחב הפרטי ומחזירה את גודל הקובץ שנוצר.
  ///
  /// [append] מוסיף לסוף קובץ קיים. התקרות נאכפות כאן ולא בקורא: גם
  /// [maxTransferBytes] על הקטע הבודד, גם [maxWorkspaceBytes] על סך המרחב וגם
  /// [maxWorkspaceEntries] — כולן תחת מנעול, כך שמטח כתיבות מקבילות אינו עוקף
  /// אותן.
  Future<int> writeWorkspaceFile({
    required String root,
    required String relativePath,
    required List<int> bytes,
    bool append = false,
  }) async {
    if (bytes.length > maxTransferBytes) {
      throw Exception('error.too_large: content exceeds the RPC size limit');
    }
    _checkDepth(relativePath);
    await ensureWorkspace(root);
    return _locked(root, () async {
      final target = _resolve(root, relativePath);
      if (p.equals(target, canonicalizeNearestExisting(root) ?? root)) {
        throw Exception('error.invalid_params: path required');
      }
      if (await Directory(target).exists()) {
        throw Exception('error.invalid_params: path is a directory');
      }
      final file = File(target);
      final isNew = !await file.exists();
      final existing = isNew ? 0 : await file.length();
      final usage = await _usageOf(root);
      final projected = append
          ? usage.bytes + bytes.length
          : usage.bytes - existing + bytes.length;
      if (projected > maxWorkspaceBytes) {
        throw Exception('error.too_large: plugin storage quota exceeded');
      }
      final newDirs = await _missingParentCount(root, file.parent.path);
      if (isNew && usage.entries + newDirs + 1 > maxWorkspaceEntries) {
        throw Exception('error.too_large: plugin storage entry limit exceeded');
      }
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        bytes,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
      final size = await file.length();
      usage.bytes += size - existing;
      usage.entries += newDirs + (isNew ? 1 : 0);
      return size;
    });
  }

  /// כמה תיקיות אב יש עוד ליצור עד [dirPath] — נספרות במכסת הרשומות.
  Future<int> _missingParentCount(String root, String dirPath) async {
    final canonicalRoot = canonicalizeNearestExisting(root) ?? root;
    var count = 0;
    var current = dirPath;
    while (!p.equals(current, canonicalRoot) &&
        p.isWithin(canonicalRoot, current)) {
      if (await Directory(current).exists()) break;
      count++;
      current = p.dirname(current);
    }
    return count;
  }

  /// קוראת את הקובץ ב-[relativePath] במרחב הפרטי.
  Future<Uint8List> readWorkspaceFile({
    required String root,
    required String relativePath,
  }) async {
    final target = _resolve(root, relativePath);
    final file = File(target);
    if (!await file.exists()) {
      throw Exception('error.not_found: file does not exist');
    }
    if (await file.length() > maxTransferBytes) {
      throw Exception('error.too_large: file exceeds the RPC size limit');
    }
    return file.readAsBytes();
  }

  /// מפרטת את תוכן התיקייה ב-[relativePath] (ריק = שורש המרחב).
  /// symlinks מדולגים — התוכן שמעבר להם אינו חלק מהמרחב הפרטי.
  Future<List<PluginWorkspaceEntry>> listWorkspaceDir({
    required String root,
    required String relativePath,
  }) async {
    await ensureWorkspace(root);
    final target = _resolve(root, relativePath);
    final dir = Directory(target);
    if (!await dir.exists()) {
      throw Exception('error.not_found: directory does not exist');
    }
    final entries = <PluginWorkspaceEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (await FileSystemEntity.isLink(entity.path)) continue;
      entries.add(await _entryOf(root, entity));
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return entries;
  }

  /// יוצרת תיקייה (וכל האבות שלה) במרחב הפרטי. idempotent.
  Future<void> makeWorkspaceDir({
    required String root,
    required String relativePath,
  }) async {
    _checkDepth(relativePath);
    await ensureWorkspace(root);
    return _locked(root, () async {
      final target = _resolve(root, relativePath);
      if (await File(target).exists()) {
        throw Exception('error.invalid_params: path is a file');
      }
      final usage = await _usageOf(root);
      final missing = await _missingParentCount(root, target);
      if (usage.entries + missing > maxWorkspaceEntries) {
        throw Exception('error.too_large: plugin storage entry limit exceeded');
      }
      await Directory(target).create(recursive: true);
      usage.entries += missing;
    });
  }

  /// מוחקת קובץ או תיקייה במרחב הפרטי. idempotent — נתיב שאינו קיים מחזיר
  /// `false`. מחיקת תיקייה לא-ריקה דורשת [recursive].
  Future<bool> deleteWorkspaceEntry({
    required String root,
    required String relativePath,
    bool recursive = false,
  }) async {
    return _locked(root, () async {
      final target = _resolve(root, relativePath);
      final canonicalRoot = canonicalizeNearestExisting(root);
      if (canonicalRoot != null && p.equals(target, canonicalRoot)) {
        throw Exception(
          'error.invalid_params: cannot delete the workspace root',
        );
      }
      final usage = await _usageOf(root);
      if (await FileSystemEntity.isLink(target)) {
        await Link(target).delete();
        return true;
      }
      final file = File(target);
      if (await file.exists()) {
        final size = await file.length();
        await file.delete();
        usage.bytes -= size;
        usage.entries--;
        return true;
      }
      final dir = Directory(target);
      if (await dir.exists()) {
        if (!recursive && await dir.list().isEmpty) {
          await dir.delete();
          usage.entries--;
          return true;
        }
        if (!recursive) {
          throw Exception('error.invalid_params: directory is not empty');
        }
        final removed = await _scanUsage(target);
        await dir.delete(recursive: true);
        usage.bytes -= removed.bytes;
        usage.entries -= removed.entries + 1;
        return true;
      }
      return false;
    });
  }

  /// מחזירה את פרטי הרשומה ב-[relativePath], או `null` אם אינה קיימת.
  Future<PluginWorkspaceEntry?> statWorkspaceEntry({
    required String root,
    required String relativePath,
  }) async {
    final target = _resolve(root, relativePath);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type == FileSystemEntityType.directory) {
      return _entryOf(root, Directory(target));
    }
    if (type == FileSystemEntityType.file) return _entryOf(root, File(target));
    return null; // symlink או socket — אינם חלק מהמרחב הפרטי
  }

  Future<PluginWorkspaceEntry> _entryOf(
    String root,
    FileSystemEntity entity,
  ) async {
    final canonicalRoot = canonicalizeNearestExisting(root) ?? root;
    final relative = p
        .relative(entity.path, from: canonicalRoot)
        .replaceAll(r'\', '/');
    final isDir = entity is Directory;
    DateTime? modified;
    try {
      modified = (await entity.stat()).modified;
    } catch (_) {
      modified = null; // נמחק בין הסריקה לקריאת ה-stat
    }
    return PluginWorkspaceEntry(
      path: relative == '.' ? '' : relative,
      name: p.basename(entity.path),
      isDirectory: isDir,
      size: isDir || entity is! File ? 0 : await entity.length(),
      modified: modified,
    );
  }
}

/// התפוסה של מרחב אחד — מונה מתוחזק, לא סריקה בכל קריאה.
class _WorkspaceUsage {
  int bytes = 0;
  int entries = 0;
}
