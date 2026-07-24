import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/services/backup/backup_merge.dart';
import 'package:otzaria/settings/services/backup/backup_rotation.dart';
import 'package:otzaria/settings/services/backup/backup_store.dart';

/// סיכום ריצת תחזוקה — מוצג למשתמש אחרי "נקה עכשיו".
class BackupMaintenanceResult {
  final int mergedIntoArchive;
  final int deletedBackups;
  final int sweptBlobs;
  final int freedBytes;

  const BackupMaintenanceResult({
    this.mergedIntoArchive = 0,
    this.deletedBackups = 0,
    this.sweptBlobs = 0,
    this.freedBytes = 0,
  });
}

/// תמונת מצב של תיקיית הגיבויים — למסך ההגדרות.
class BackupOverview {
  final int backupCount;
  final bool archiveExists;
  final int totalBytes;

  const BackupOverview({
    required this.backupCount,
    required this.archiveExists,
    required this.totalBytes,
  });
}

/// תחזוקת תיקיית הגיבויים: רוטציית דורות, מיזוג גיבויים שפג תוקפם לארכיון
/// מתגלגל, ואיסוף blobs שאינם מופנים עוד (Mark & Sweep).
///
/// סדר הפעולות עמיד לקריסה: הארכיון החדש נכתב ומאומת לפני מחיקת המקור,
/// וה-GC מוחק רק blobs שאינם מופנים משום מניפסט שנותר.
class BackupMaintenance {
  static final Logger _logger = Logger('BackupMaintenance');

  static const String archiveFileName = 'otzaria_archive.json';
  static const String keyRetentionProfile = 'key-backup-retention-profile';

  /// מפרק שם קובץ גיבוי ל-timestamp ודגל ידני. מחזיר null אם אינו קובץ גיבוי.
  static BackupEntryInfo? parseBackupFileName(String path) {
    final name = p.basename(path);
    final match = RegExp(
      r'^otzaria_backup_(.+?)(_manual)?\.json$',
    ).firstMatch(name);
    if (match == null) return null;
    final timestamp = BackupMerge.parseManifestTimestamp(match.group(1));
    if (timestamp == null) return null;
    return BackupEntryInfo(
      path: path,
      timestamp: timestamp,
      isManual: match.group(2) != null,
    );
  }

  /// כל קבצי הגיבוי בתיקייה (ללא הארכיון), ממוינים מהחדש לישן.
  static Future<List<BackupEntryInfo>> listBackups(String backupDir) async {
    final dir = Directory(backupDir);
    if (!await dir.exists()) return [];
    final entries = <BackupEntryInfo>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final info = parseBackupFileName(entity.path);
      if (info != null) entries.add(info);
    }
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  static Future<BackupOverview> getOverview() async {
    final backupDir = await AppPaths.getBackupPath();
    final backups = await listBackups(backupDir);
    final archive = File(p.join(backupDir, archiveFileName));
    final archiveExists = await archive.exists();

    var totalBytes = 0;
    for (final backup in backups) {
      try {
        totalBytes += await File(backup.path).length();
      } catch (_) {}
    }
    if (archiveExists) totalBytes += await archive.length();
    totalBytes += await BackupStore.forBackupDir(backupDir).totalSize();

    return BackupOverview(
      backupCount: backups.length,
      archiveExists: archiveExists,
      totalBytes: totalBytes,
    );
  }

  /// מריץ מחזור תחזוקה מלא. נקרא אחרי גיבוי אוטומטי מוצלח ומכפתור "נקה עכשיו".
  static Future<BackupMaintenanceResult> runMaintenance() async {
    final backupDir = await AppPaths.getBackupPath();
    final store = BackupStore.forBackupDir(backupDir);
    final profile = RetentionProfile.fromName(
      Settings.getValue<String>(keyRetentionProfile),
    );

    final backups = await listBackups(backupDir);
    final expired = BackupRotation.selectExpired(
      backups,
      profile,
      DateTime.now(),
    )..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    var deleted = 0;
    var mergedPaths = const <String>[];

    if (expired.isNotEmpty) {
      mergedPaths = await _mergeExpiredIntoArchive(backupDir, store, expired);
      // מחיקת המקור רק אחרי שהארכיון נכתב ואומת בהצלחה.
      for (final path in mergedPaths) {
        try {
          await File(path).delete();
          deleted++;
        } catch (e) {
          _logger.warning('Failed to delete expired backup $path: $e');
        }
      }
    }

    final sweepResult = await _garbageCollect(backupDir, store);

    return BackupMaintenanceResult(
      mergedIntoArchive: mergedPaths.length,
      deletedBackups: deleted,
      sweptBlobs: sweepResult.deleted,
      freedBytes: sweepResult.freedBytes,
    );
  }

  /// ממזג את הגיבויים שפג תוקפם (מהישן לחדש) לתוך הארכיון וכותב אותו אטומית.
  /// מחזיר את נתיבי הגיבויים שמוזגו בפועל — ריק אם כתיבת הארכיון נכשלה.
  static Future<List<String>> _mergeExpiredIntoArchive(
    String backupDir,
    BackupStore store,
    List<BackupEntryInfo> expiredAscending,
  ) async {
    final archiveFile = File(p.join(backupDir, archiveFileName));

    Map<String, dynamic> archive = const {};
    DateTime archiveTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    if (await archiveFile.exists()) {
      try {
        archive =
            json.decode(await archiveFile.readAsString())
                as Map<String, dynamic>;
        archiveTimestamp =
            BackupMerge.parseManifestTimestamp(
              archive['timestamp']?.toString(),
            ) ??
            archiveTimestamp;
      } catch (e) {
        // ארכיון פגום אינו נדרס בשקט: התחזוקה נעצרת והגיבויים נשארים בעינם.
        _logger.severe('Archive file is corrupt, skipping merge: $e');
        return const [];
      }
    }

    final mergedPaths = <String>[];
    for (final backup in expiredAscending) {
      Map<String, dynamic> manifest;
      try {
        manifest =
            json.decode(await File(backup.path).readAsString())
                as Map<String, dynamic>;
      } catch (e) {
        _logger.warning('Skipping unreadable backup ${backup.path}: $e');
        continue;
      }

      // מיגרציה עצלה: גיבוי v1 עם base64 מוטמע מפורק ל-blobs לפני המיזוג.
      await convertManifestToRefs(manifest, store);

      archive = BackupMerge.merge(
        archive,
        manifest,
        olderTimestamp: archiveTimestamp,
        newerTimestamp: backup.timestamp,
        now: DateTime.now(),
      );
      archiveTimestamp = backup.timestamp;
      mergedPaths.add(backup.path);
    }

    if (mergedPaths.isEmpty) return const [];

    if (!await _writeArchiveVerified(archiveFile, archive, store)) {
      return const [];
    }
    return mergedPaths;
  }

  /// כותב את הארכיון לקובץ זמני, מאמת (JSON תקין + כל ה-blobs קיימים),
  /// ורק אז מחליף את הקובץ הקיים. מחזיר האם ההחלפה הצליחה.
  static Future<bool> _writeArchiveVerified(
    File archiveFile,
    Map<String, dynamic> archive,
    BackupStore store,
  ) async {
    final tmp = File('${archiveFile.path}.tmp');
    try {
      await tmp.writeAsString(json.encode(archive), flush: true);

      final reread =
          json.decode(await tmp.readAsString()) as Map<String, dynamic>;
      for (final ref in BackupStore.collectRefs(reread)) {
        if (!await store.exists(ref)) {
          _logger.severe('Archive verification failed: missing blob $ref');
          await tmp.delete();
          return false;
        }
      }

      // גיבוי הארכיון הישן ל-.bak לפני ההחלפה; אם ה-rename ייכשל נשחזר ממנו.
      File? oldBackup;
      if (await archiveFile.exists()) {
        oldBackup = File('${archiveFile.path}.bak');
        if (await oldBackup.exists()) await oldBackup.delete();
        await archiveFile.rename(oldBackup.path);
      }
      try {
        await tmp.rename(archiveFile.path);
      } catch (_) {
        if (oldBackup != null) await oldBackup.rename(archiveFile.path);
        rethrow;
      }
      if (oldBackup != null) await oldBackup.delete();
      return true;
    } catch (e) {
      _logger.severe('Failed to write archive: $e');
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return false;
    }
  }

  /// ממיר סעיפי תוספים במניפסט מ-base64 מוטמע (v1) להפניות store (v2),
  /// בתוך המפה עצמה. ערכים שכבר הפניות נשארים כמות שהם.
  static Future<void> convertManifestToRefs(
    Map<String, dynamic> manifest,
    BackupStore store,
  ) async {
    final plugins = manifest['plugins'];
    if (plugins is! List) return;
    for (final entry in plugins) {
      if (entry is! Map) continue;
      for (final section in ['files', 'data']) {
        final files = entry[section];
        if (files is! Map) continue;
        for (final key in files.keys.toList()) {
          final value = files[key];
          if (value is! String || BackupStore.isHashRef(value)) continue;
          try {
            files[key] = await store.putBytes(base64Decode(value));
          } catch (e) {
            _logger.warning('Failed to convert plugin file $key to blob: $e');
          }
        }
      }
    }
    manifest['version'] = '2.0';
  }

  /// Mark & Sweep: אוסף הפניות מכל המניפסטים שנותרו (גיבויים + ארכיון)
  /// ומוחק blobs יתומים שגילם מעל תקופת החסד.
  static Future<({int deleted, int freedBytes})> _garbageCollect(
    String backupDir,
    BackupStore store,
  ) async {
    final referenced = <String>{};

    final manifests = [
      ...(await listBackups(backupDir)).map((b) => b.path),
      p.join(backupDir, archiveFileName),
    ];
    for (final path in manifests) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final manifest =
            json.decode(await file.readAsString()) as Map<String, dynamic>;
        referenced.addAll(BackupStore.collectRefs(manifest));
      } catch (e) {
        // מניפסט לא קריא: מדלגים על ה-GC כולו — עדיף blobs יתומים ממחיקת
        // blob שאולי עדיין מופנה ממנו.
        _logger.warning('Unreadable manifest $path — skipping GC: $e');
        return (deleted: 0, freedBytes: 0);
      }
    }

    return store.sweep(referenced);
  }
}
