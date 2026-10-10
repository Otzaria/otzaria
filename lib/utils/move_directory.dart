import 'dart:io';
import 'package:path/path.dart' as p;

/// Moves the contents of [source] directory to [destination].
/// Copies everything first; deletes source only after a successful copy.
///
/// When [includeOnly] is given, only top-level entries whose name is in the
/// set are moved — other files the user placed in the folder stay behind.
/// The source directory itself is deleted only if it ends up empty.
///
/// Existing files at the destination are never overwritten: a name collision
/// throws before anything is deleted, so destination data is preserved.
///
/// Returns null on full success.
/// Returns [source] path if deletion failed — caller should warn the user to
/// delete manually, but the path update should still proceed.
Future<String?> moveDirectory(
  String source,
  String destination, {
  Set<String>? includeOnly,
}) async {
  final sourceDir = Directory(source);
  if (!await sourceDir.exists()) {
    throw Exception('תיקיית המקור לא קיימת: $source');
  }

  if (p.equals(source, destination)) return null;

  // Guard: destination must not be inside source (would create infinite loop).
  if (p.isWithin(source, destination)) {
    throw Exception('תיקיית היעד לא יכולה להיות בתוך תיקיית המקור');
  }

  final created = <FileSystemEntity>[];
  try {
    await copyDirectoryEntries(
      source,
      destination,
      includeOnly: includeOnly,
      created: created,
    );
  } catch (_) {
    // מוחקים רק מה שההעתקה יצרה, ובסדר הפוך כדי שתיקייה תתרוקן לפני מחיקתה.
    for (final entity in created.reversed) {
      await entity.delete().catchError((_) => entity);
    }
    rethrow;
  }
  return deleteMovedEntries(source, includeOnly: includeOnly);
}

/// Copies the top-level entries of [source] into [destination], creating the
/// destination if needed. When [includeOnly] is given, copies only entries
/// whose name is in the set. Files and symbolic links that already exist at
/// the destination cause a collision exception (directories are merged).
/// Every entry this call creates is appended to [created].
Future<void> copyDirectoryEntries(
  String source,
  String destination, {
  Set<String>? includeOnly,
  void Function()? checkCancelled,
  List<FileSystemEntity>? created,
}) async {
  checkCancelled?.call();
  final destDir = Directory(destination);
  if (!await destDir.exists()) {
    await destDir.create(recursive: true);
    created?.add(destDir);
  }

  await for (final entity in Directory(source).list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (includeOnly != null && !includeOnly.contains(name)) continue;
    await _copyEntity(
      entity,
      p.join(destination, name),
      checkCancelled,
      created,
    );
  }
}

Future<void> _copyEntity(
  FileSystemEntity entity,
  String destPath,
  void Function()? checkCancelled,
  List<FileSystemEntity>? created,
) async {
  checkCancelled?.call();
  // Link נבדק לפני File/Directory — קישור לקובץ הוא גם FileSystemEntity של File.
  if (entity is Link) {
    if (await _entityExists(destPath)) {
      throw Exception('היעד כבר מכיל פריט בשם "${p.basename(destPath)}"');
    }
    final copied = await Link(destPath).create(
      await entity.target(),
      recursive: true,
    );
    created?.add(copied);
  } else if (entity is File) {
    if (await _entityExists(destPath)) {
      throw Exception('היעד כבר מכיל קובץ בשם "${p.basename(destPath)}"');
    }
    await File(destPath).parent.create(recursive: true);
    created?.add(File(destPath));
    await entity.copy(destPath);
  } else if (entity is Directory) {
    // יצירת תיקיית היעד גם כשהיא ריקה, ואז העתקה רקורסיבית של תכנה.
    final sub = Directory(destPath);
    if (!await sub.exists()) {
      final copied = await sub.create(recursive: true);
      created?.add(copied);
    }
    await for (final child in entity.list(followLinks: false)) {
      await _copyEntity(
        child,
        p.join(destPath, p.basename(child.path)),
        checkCancelled,
        created,
      );
    }
  }
}

Future<bool> _entityExists(String path) async =>
    await File(path).exists() ||
    await Directory(path).exists() ||
    await Link(path).exists();

/// Deletes the entries that were moved out of [source]; when [includeOnly] is
/// given, deletes only those entries. If the directory is left empty, it is
/// removed too. Returns null on success, or [source] if a deletion failed.
Future<String?> deleteMovedEntries(
  String source, {
  Set<String>? includeOnly,
}) async {
  final sourceDir = Directory(source);
  if (!await sourceDir.exists()) return null;
  try {
    await for (final entity in sourceDir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (includeOnly != null && !includeOnly.contains(name)) continue;
      await entity.delete(recursive: true);
    }
    if (await sourceDir.list(followLinks: false).isEmpty) {
      await sourceDir.delete();
    }
    return null;
  } catch (_) {
    return source;
  }
}
