import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// מיקום אחסון אפשרי לספרייה ב-Android.
///
/// [libraryRoot] הוא שורש הספרייה שיישמר; `null` פירושו אחסון פנימי (ברירת
/// מחדל). מיקומים חיצוניים (כרטיס SD) הם תיקיית האפליקציה הייעודית על הכרך,
/// שנגישה ל-sqlite3 native ואינה דורשת הרשאות.
@immutable
class AndroidStorageOption {
  final String label;
  final String? libraryRoot;
  final int freeBytes;
  final bool isRemovable;

  /// false = הכרך מפורמט ב-FAT32 (מגבלת 4GB לקובץ) ולא יכול להכיל את
  /// seforim.db; ה-UI מציג את המיקום כלא-נתמך.
  final bool supportsLargeFiles;

  const AndroidStorageOption({
    required this.label,
    required this.libraryRoot,
    required this.freeBytes,
    required this.isRemovable,
    this.supportsLargeFiles = true,
  });
}

/// גילוי מיקומי אחסון זמינים ב-Android עבור בחירת מיקום הספרייה בהתקנה.
class AndroidStorageService {
  const AndroidStorageService._();

  /// מחזיר את מיקומי האחסון הזמינים. כשאין כרטיס SD (אין ברירה אמיתית) —
  /// מחזיר רשימה ריקה, וה-UI לא מציג בורר.
  static Future<List<AndroidStorageOption>> listStorageOptions() async {
    if (!Platform.isAndroid) return const [];

    final internalDir = await getApplicationDocumentsDirectory();
    final primaryExternalDir = await getExternalStorageDirectory();
    final externals = await getExternalStorageDirectories() ?? const [];
    final removablePaths = removableStoragePaths(
      externals.map((directory) => directory.path).toList(),
      primaryPath: primaryExternalDir?.path,
    );
    if (removablePaths.isEmpty) return const [];

    final options = <AndroidStorageOption>[
      AndroidStorageOption(
        label: 'אחסון פנימי',
        libraryRoot: null,
        freeBytes: await _freeBytes(internalDir.path),
        isRemovable: false,
      ),
    ];
    for (final path in removablePaths) {
      options.add(
        AndroidStorageOption(
          label: 'כרטיס SD',
          libraryRoot: path,
          freeBytes: await _freeBytes(path),
          isRemovable: true,
          supportsLargeFiles: await volumeSupportsLargeFiles(path),
        ),
      );
    }
    return options;
  }

  /// מסיר מרשימת נפחי האחסון את הנפח הראשי ומשאיר את כל הנפחים המשניים.
  /// אם הנפח הראשי אינו זמין, כל הנתיבים שהוחזרו נחשבים משניים.
  @visibleForTesting
  static List<String> removableStoragePaths(
    List<String> volumePaths, {
    required String? primaryPath,
  }) => volumePaths
      .where((volumePath) => volumePath != primaryPath)
      .toList(growable: false);

  /// האם הכרך שעליו יושב [dirPath] תומך בקבצים מעל 4GB (seforim.db גדול מכך).
  /// fail-open: כשלא ניתן לקבוע מחזיר true — הכשל האמיתי יעלה בכתיבה עצמה.
  static Future<bool> volumeSupportsLargeFiles(String dirPath) async {
    if (!Platform.isAndroid) return true;
    try {
      final mounts = await File('/proc/mounts').readAsString();
      return largeFileSupportFromMounts(mounts, dirPath) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// מפענח את /proc/mounts וקובע תמיכה בקבצים גדולים עבור [dirPath].
  /// מחזיר null כשלא ניתן לקבוע (הכרך אינו מופיע, או שנראית רק שכבת
  /// ה-FUSE/sdcardfs ולא מערכת הקבצים האמיתית).
  @visibleForTesting
  static bool? largeFileSupportFromMounts(String mounts, String dirPath) {
    final volume = RegExp(
      r'^/storage/([^/]+)/',
    ).firstMatch('$dirPath/')?.group(1);
    // אחסון פנימי (או נתיב שאינו תחת /storage) — ext4/f2fs, תומך תמיד.
    if (volume == null || volume == 'emulated' || volume == 'self') {
      return true;
    }

    String? fsTypeAt(String mountPoint) {
      for (final line in mounts.split('\n')) {
        final parts = line.split(' ');
        if (parts.length >= 3 && parts[1] == mountPoint) return parts[2];
      }
      return null;
    }

    // /storage/<VOL> הוא שכבת FUSE/sdcardfs; מערכת הקבצים האמיתית של הכרטיס
    // נמצאת במאונט התחתון /mnt/media_rw/<VOL>.
    final fsType =
        fsTypeAt('/mnt/media_rw/$volume') ?? fsTypeAt('/storage/$volume');
    if (fsType == null) return null;
    final lower = fsType.toLowerCase();
    if (const {'vfat', 'msdos', 'fat'}.contains(lower)) return false;
    if (const {'fuse', 'sdcardfs', 'esdfs'}.contains(lower)) return null;
    return true;
  }

  /// מקום פנוי בבייטים לנתיב נתון, או -1 אם לא ניתן לקבוע. משתמש ב-df,
  /// הנתמך גם ב-toybox של Android; הדגל -k (בלוקים של 1024B) נייד בין המימושים.
  static Future<int> _freeBytes(String dirPath) async {
    try {
      final result = await Process.run('df', [
        '-k',
        dirPath,
      ], runInShell: false);
      if (result.exitCode != 0) return -1;
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return -1;
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return -1;
      final availableKb = int.tryParse(parts[3]);
      return availableKb == null ? -1 : availableKb * 1024;
    } catch (_) {
      return -1;
    }
  }
}
