import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:path_provider/path_provider.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// מכין את SQLite להחלת עדכון הספרייה: תיקיית temp וגודלי cache לפי ה-RAM.
///
/// נקרא רק כשעדכון מתחיל, לא בעלייה — שני ערוצי פלטפורמה ב-mobile.
class LibraryUpdateSqliteSetup {
  LibraryUpdateSqliteSetup({
    bool? isMobile,
    bool? needsSqliteTempDirectory,
    Future<Directory> Function()? temporaryDirectory,
    Future<int?> Function()? physicalRamMb,
    String? Function()? readSqliteTempDirectory,
    void Function(String path)? writeSqliteTempDirectory,
  }) : _isMobile = isMobile ?? (Platform.isAndroid || Platform.isIOS),
       _needsTempDir = needsSqliteTempDirectory ?? Platform.isAndroid,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _physicalRamMb = physicalRamMb ?? _readPhysicalRamMb,
       _readTempDir = readSqliteTempDirectory ?? _readGlobalTempDir,
       _writeTempDir = writeSqliteTempDirectory ?? _writeGlobalTempDir;

  static final LibraryUpdateSqliteSetup instance = LibraryUpdateSqliteSetup();

  final bool _isMobile;
  // ב-iOS TMPDIR מוגדר ו-SQLite מוצא אותו בעצמו; כתיבה לגלובלי רק היכן שחסר.
  final bool _needsTempDir;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<int?> Function() _physicalRamMb;
  final String? Function() _readTempDir;
  final void Function(String path) _writeTempDir;

  Future<PatchApplier>? _applier;
  String? _preparedTempDirectory;
  bool _tempDirectoryInstallAttempted = false;

  bool get hasPendingTempDirectoryInstall =>
      _needsTempDir &&
      _preparedTempDirectory != null &&
      !_tempDirectoryInstallAttempted;

  /// ה-[PatchApplier] לכל ה-apply וה-verify של העדכון. ב-desktop — ברירות
  /// המחדל של ה-updater, שנמדדו שם.
  Future<PatchApplier> prepareApplier() => _applier ??= _prepare();

  Future<PatchApplier> _prepare() async {
    if (!_isMobile) return const PatchApplier(logicalSizeOf: _logicalSizeOf);
    if (_needsTempDir) await _prepareSqliteTempDirectory();
    int? ramMb;
    try {
      ramMb = await _physicalRamMb();
    } catch (error) {
      debugPrint('Library update: physical RAM unavailable: $error');
    }
    return applierForPhysicalRam(ramMb);
  }

  /// הגודל שמניחים כשה-RAM לא ידוע: הקצה התחתון של מכשירי היעד.
  static const int fallbackRamMb = 2048;

  /// 1/32 ו-1/128 של 8GB הם בדיוק 256MB ו-64MB, ברירות המחדל שנמדדו ב-desktop.
  /// מתחת ל-8GB שומרים על אותו יחס ל-RAM במקום על אותו גודל מוחלט.
  static const int _desktopReferenceRamMb = 8192;

  @visibleForTesting
  static PatchApplier applierForPhysicalRam(int? ramMb) {
    final ram = (ramMb == null || ramMb <= 0) ? fallbackRamMb : ramMb;
    if (ram >= _desktopReferenceRamMb) {
      return const PatchApplier(logicalSizeOf: _logicalSizeOf);
    }
    return PatchApplier(
      cacheSizeKib: ram * 1024 ~/ 32,
      hashCacheSizeKib: ram * 1024 ~/ 128,
      logicalSizeOf: _logicalSizeOf,
    );
  }

  /// מד האימות מחושב מגודל המסד; ב-zdb הקובץ קטן פי ~4 מהגודל ש-SQLite רואה.
  static int _logicalSizeOf(String dbPath) => libraryDbLogicalSizeOf(dbPath);

  Future<void> _prepareSqliteTempDirectory() async {
    try {
      final dir = await _temporaryDirectory();
      await dir.create(recursive: true);
      _preparedTempDirectory = dir.path;
    } catch (error, stackTrace) {
      // בלי תיקייה ה-updater נשאר ב-temp_store של ה-build (זיכרון).
      try {
        ErrorLogFile.append(
          title: 'Library Update: sqlite temp directory unavailable',
          error: error,
          stackTrace: stackTrace,
        );
      } catch (_) {}
    }
  }

  /// מתקין את הנתיב רק כשהאפליקציה משהה את כל חיבורי SQLite המקבילים.
  void installTempDirectoryWhenQuiesced() {
    if (!hasPendingTempDirectoryInstall) return;
    try {
      if (_readTempDir() == null) {
        _writeTempDir(_preparedTempDirectory!);
      }
    } catch (error, stackTrace) {
      try {
        ErrorLogFile.append(
          title: 'Library Update: sqlite temp directory unavailable',
          error: error,
          stackTrace: stackTrace,
        );
      } catch (_) {}
    } finally {
      _tempDirectoryInstallAttempted = true;
    }
  }

  static String? _readGlobalTempDir() => sqlite3.sqlite3.tempDirectory;

  static void _writeGlobalTempDir(String path) =>
      sqlite3.sqlite3.tempDirectory = path;

  static Future<int?> _readPhysicalRamMb() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await info.androidInfo).physicalRamSize;
    if (Platform.isIOS) return (await info.iosInfo).physicalRamSize;
    return null;
  }
}
