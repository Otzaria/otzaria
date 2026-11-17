/// עדכון עץ (macOS, Linux נייד): ההתקנה מועתקת לצידה, החבילה מוחלת על
/// העותק, והעותק מאומת מול העץ החדש המלא — symlinks והרשאות כלולים.
///
/// נטול תלות ב-Flutter: גם הבונה שב-`tool/release` מחיל ומאמת דרכו.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// קובץ בעץ החדש.
class TreeFile {
  const TreeFile({required this.size, required this.sha256, this.mode});

  final int size;
  final String sha256;

  /// ביטי ההרשאה (0-0777). `null` רק בעץ שאין בו הרשאות.
  final int? mode;
}

/// העץ המלא של הגרסה החדשה: כל קובץ וכל symlink, בנתיבים יחסיים עם `/`.
class TreeManifest {
  const TreeManifest({required this.files, required this.links});

  final Map<String, TreeFile> files;
  final Map<String, String> links;
}

/// מה שיש בפועל בעץ על הדיסק. תיקיות אינן נרשמות.
class TreeListing {
  const TreeListing({required this.files, required this.links});

  /// נתיב יחסי ← ביטי ההרשאה (`null` במערכת שאין בה כאלה).
  final Map<String, int?> files;

  /// נתיב יחסי ← יעד ה-symlink.
  final Map<String, String> links;
}

/// פעולות הקובץ שהעדכון צריך מעבר ל-`dart:io` הרגיל. מוזרק כדי שאפשר יהיה
/// לבדוק symlinks והרשאות גם במחשב שבו אי אפשר ליצור אותם.
abstract class TreeFileSystem {
  /// מעתיק את [from] ל-[to] (שאינו קיים) כולל symlinks והרשאות.
  Future<void> copyTree(String from, String to);

  Future<TreeListing> list(String root);

  Future<bool> isLink(String path);

  Future<void> createLink(String path, String target);

  Future<void> deleteLink(String path);

  /// נתיב מוחלט ← ביטי הרשאה.
  Future<void> setModes(Map<String, int> modes);

  Future<bool> isEmptyDirectory(String path);

  /// האם ההרשאות נשמרות בדיסק הזה. ב-Windows אין להן משמעות.
  bool get tracksModes;
}

/// המימוש על הדיסק האמיתי.
class LocalTreeFileSystem implements TreeFileSystem {
  const LocalTreeFileSystem();

  @override
  bool get tracksModes => !Platform.isWindows;

  @override
  Future<void> copyTree(String from, String to) async {
    if (Platform.isMacOS) {
      // clonefile ב-APFS: העותק כמעט חינם. בכרך אחר נופלים להעתקה רגילה.
      if (await _run('cp', ['-cRp', from, to])) return;
      await _deletePartial(to);
      if (await _run('cp', ['-Rp', from, to])) return;
    } else if (Platform.isLinux) {
      if (await _run('cp', ['-a', '--reflink=auto', from, to])) return;
    } else {
      await _copyWithDart(from, to);
      return;
    }
    await _deletePartial(to);
    throw FileSystemException('could not copy the install tree', from);
  }

  Future<void> _deletePartial(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _copyWithDart(String from, String to) async {
    await Directory(to).create(recursive: true);
    await for (final entity in Directory(
      from,
    ).list(recursive: true, followLinks: false)) {
      final target = p.join(to, p.relative(entity.path, from: from));
      if (entity is Link) {
        await Link(target).create(await entity.target(), recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
      } else if (entity is Directory) {
        await Directory(target).create(recursive: true);
      }
    }
  }

  @override
  Future<TreeListing> list(String root) async {
    final files = <String, int?>{};
    final links = <String, String>{};
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      final relative = p
          .relative(entity.path, from: root)
          .replaceAll(r'\', '/');
      if (entity is Link) {
        links[relative] = await entity.target();
      } else if (entity is File) {
        files[relative] = tracksModes
            ? (await entity.stat()).mode & 0x1FF
            : null;
      }
    }
    return TreeListing(files: files, links: links);
  }

  @override
  Future<bool> isLink(String path) => FileSystemEntity.isLink(path);

  @override
  Future<void> createLink(String path, String target) async {
    await Link(path).create(target, recursive: true);
  }

  @override
  Future<void> deleteLink(String path) => Link(path).delete();

  @override
  Future<void> setModes(Map<String, int> modes) async {
    if (!tracksModes || modes.isEmpty) return;
    final byMode = <int, List<String>>{};
    modes.forEach((path, mode) => (byMode[mode] ??= []).add(path));
    for (final entry in byMode.entries) {
      final paths = entry.value;
      for (var i = 0; i < paths.length; i += 200) {
        final chunk = paths.sublist(i, (i + 200).clamp(0, paths.length));
        final ok = await _run('chmod', [
          entry.key.toRadixString(8),
          ...chunk,
        ]);
        if (!ok) throw FileSystemException('chmod failed', chunk.first);
      }
    }
  }

  @override
  Future<bool> isEmptyDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    return dir.list().isEmpty;
  }

  static Future<bool> _run(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}

/// מחזיר את הסיבה שיעד ה-symlink ב-[path] אינו בטוח, או null. היעד יחסי
/// ונשאר בתוך העץ — symlink מוחלט היה מפנה מחוץ להתקנה אצל המשתמש.
String? linkTargetError(String path, String target) {
  if (target.isEmpty) return 'link target is empty';
  if (target.contains('\\')) return 'link target must use forward slashes';
  if (target.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(target)) {
    return 'link target must be relative';
  }
  final resolved = path.split('/')..removeLast();
  for (final segment in target.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (resolved.isEmpty) return 'link target escapes the root';
      resolved.removeLast();
    } else {
      resolved.add(segment);
    }
  }
  if (resolved.isEmpty) return 'link target is the root';
  return null;
}

/// שגיאות בנתיבים שעוברים דרך symlink: קובץ כזה היה נכתב אל יעד הקישור
/// ולא אל הנתיב שהמניפסט מתאר.
List<String> pathsThroughLinksErrors(
  Iterable<String> paths,
  Set<String> linkPaths,
) {
  final errors = <String>[];
  for (final path in paths) {
    final segments = path.split('/');
    for (var i = 1; i < segments.length; i++) {
      final prefix = segments.take(i).join('/');
      if (linkPaths.contains(prefix)) {
        errors.add('$path: the path passes through the symlink $prefix');
        break;
      }
    }
  }
  return errors;
}

/// ההשוואה היא על ביט ההרצה בלבד: חילוץ ב-tar מחיל את ה-umask של המשתמש
/// על שאר הביטים, ו-codesign אינו חותם עליהם.
bool sameExecutableBit(int? actual, int expected) =>
    actual != null && (actual & 0x40) == (expected & 0x40);

/// כשל בפעולת עץ. הקורא ממיר אותו לנסיגה למסלול המלא.
class TreeUpdateException implements Exception {
  TreeUpdateException(this.message);
  final String message;
  @override
  String toString() => 'TreeUpdateException: $message';
}

/// מסיר מהעותק symlinks וקבצים שאינם בגרסה החדשה, ומנקה תיקיות שהתרוקנו.
/// תיקייה ריקה שנשארת (framework ישן) נחשבת ב-codesign לקוד לא חתום.
Future<void> removeFromTree({
  required TreeFileSystem fs,
  required String root,
  required Iterable<String> linkRemovals,
  required Iterable<String> fileRemovals,
}) async {
  final touchedDirs = <String>{};
  for (final path in linkRemovals) {
    final absolute = p.join(root, path);
    if (await fs.isLink(absolute)) {
      await fs.deleteLink(absolute);
    } else if (await FileSystemEntity.type(absolute, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw TreeUpdateException('$path: expected a symlink to remove');
    }
    touchedDirs.add(p.normalize(p.dirname(absolute)));
  }
  for (final path in fileRemovals) {
    final absolute = p.join(root, path);
    if (await fs.isLink(absolute)) {
      throw TreeUpdateException('$path: expected a file to remove');
    }
    final file = File(absolute);
    if (await file.exists()) await file.delete();
    touchedDirs.add(p.normalize(p.dirname(absolute)));
  }
  final rootPath = p.normalize(root);
  // העמוקות קודם, כדי שהורה יתרוקן אחרי ילדיו.
  final ordered = touchedDirs.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (var dir in ordered) {
    while (p.isWithin(rootPath, dir) && await fs.isEmptyDirectory(dir)) {
      await Directory(dir).delete();
      dir = p.dirname(dir);
    }
  }
}

/// יוצר את ה-symlinks החדשים ומיישר את ההרשאות של כל קובץ לעץ החדש.
Future<void> completeTree({
  required TreeFileSystem fs,
  required String root,
  required Map<String, String> links,
  required TreeManifest newTree,
}) async {
  for (final entry in links.entries) {
    final absolute = p.join(root, entry.key);
    if (await fs.isLink(absolute)) await fs.deleteLink(absolute);
    await fs.createLink(absolute, entry.value);
  }
  if (!fs.tracksModes) return;
  final listing = await fs.list(root);
  final modes = <String, int>{};
  newTree.files.forEach((path, file) {
    final mode = file.mode;
    if (mode != null && !sameExecutableBit(listing.files[path], mode)) {
      modes[p.join(root, path)] = mode;
    }
  });
  await fs.setModes(modes);
}

/// משווה את העץ על הדיסק לעץ החדש: כל קובץ בגודל, בתוכן ובהרשאות, כל
/// symlink ביעדו. [allowUnmanaged] מתיר קבצים נוספים (Linux); ב-bundle של
/// macOS קובץ נוסף שובר את החותם. מחזיר רשימת שגיאות (ריקה = תקין).
/// הפונקציה [hashFile] חייבת להיות ניתנת להעברה ל-isolate.
Future<List<String>> verifyTree({
  required TreeFileSystem fs,
  required String root,
  required TreeManifest newTree,
  required bool allowUnmanaged,
  Future<String> Function(String) hashFile = _hashFile,
}) async {
  final errors = <String>[];
  final listing = await fs.list(root);
  final toHash = <String>[];
  newTree.files.forEach((path, file) {
    if (!listing.files.containsKey(path)) {
      errors.add('$path: the file is missing');
      return;
    }
    final mode = listing.files[path];
    if (fs.tracksModes &&
        file.mode != null &&
        !sameExecutableBit(mode, file.mode!)) {
      errors.add(
        '$path: mode ${mode?.toRadixString(8)} is not '
        '${file.mode!.toRadixString(8)}',
      );
    }
    toHash.add(path);
  });
  newTree.links.forEach((path, target) {
    final actual = listing.links[path];
    if (actual == null) {
      errors.add('$path: the symlink is missing');
    } else if (actual != target) {
      errors.add('$path: the symlink points to $actual, not $target');
    }
  });
  for (final path in listing.links.keys) {
    if (!newTree.links.containsKey(path)) {
      errors.add('$path: an unexpected symlink');
    }
  }
  if (!allowUnmanaged) {
    for (final path in listing.files.keys) {
      if (!newTree.files.containsKey(path)) {
        errors.add('$path: an unexpected file');
      }
    }
  }

  final fileChecks = [
    for (final path in toHash)
      (path: p.join(root, path), expected: newTree.files[path]!),
  ];
  // מאות מגה-בתים: הגיבוב מחוץ ל-isolate הראשי כדי שהממשק לא ייתקע.
  final matches = await Isolate.run(() => _filesMatch(fileChecks, hashFile));
  for (var i = 0; i < toHash.length; i++) {
    if (!matches[i]) {
      errors.add('${toHash[i]}: the content does not match');
    }
  }
  return errors;
}

Future<List<bool>> _filesMatch(
  List<({String path, TreeFile expected})> files,
  Future<String> Function(String) hashFile,
) async {
  final matches = <bool>[];
  for (final (:path, :expected) in files) {
    final size = await File(path).length();
    matches.add(
      size == expected.size && await hashFile(path) == expected.sha256,
    );
  }
  return matches;
}

Future<String> _hashFile(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
