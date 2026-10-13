import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/plugins/services/plugin_install_results_log.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

/// `otzaria_capabilities.json` בשורש הנתונים: מה הגרסה הזו של אוצריא יודעת,
/// כדי שהמעדכן הלא-מקוון לא ינחש. הקורא נופל להתנהגות הישנה כשהקובץ חסר.
class OtzariaCapabilities {
  static const String fileName = 'otzaria_capabilities.json';
  static const int formatVersion = 1;

  static Map<String, Object?> build({
    required PackageInfo packageInfo,
    required String arch,
    required bool portable,
    required String exePath,
    required String libraryDbPath,
  }) => {
    'formatVersion': formatVersion,
    'appVersion': appReleaseVersion(packageInfo),
    'buildNumber': int.tryParse(packageInfo.buildNumber.trim()),
    'arch': arch,
    'portable': portable,
    'exePath': exePath,
    'readableDbSchemaVersion': DatabaseConstants.readableDbSchemaVersion,
    'libraryDbPath': libraryDbPath,
    'reportsQueueFormat': kReportsQueueFormat,
    'pluginInstallResults': PluginInstallResultsLog.formatVersion,
  };

  /// ארכיטקטורת התהליך הרץ; ב-macOS החבילה אוניברסלית.
  static String currentArch() {
    if (Platform.isMacOS) return 'universal';
    return switch (Abi.current()) {
      Abi.windowsArm64 || Abi.linuxArm64 || Abi.androidArm64 => 'arm64',
      Abi.windowsX64 || Abi.linuxX64 || Abi.androidX64 => 'x64',
      final other => other.toString(),
    };
  }

  /// כותב את הקובץ באופן אטומי, רק כשהתוכן (מלבד writtenAt) השתנה.
  /// מחזיר `true` אם נכתב.
  static Future<bool> writeIfChanged(
    String dataRoot,
    Map<String, Object?> content, {
    DateTime? now,
  }) async {
    final file = File(p.join(dataRoot, fileName));
    if (await file.exists()) {
      try {
        final existing = jsonDecode(await file.readAsString());
        if (existing is Map<String, dynamic>) {
          existing.remove('writtenAt');
          if (jsonEncode(existing) == jsonEncode(content)) return false;
        }
      } on FormatException {
        // קובץ פגום נכתב מחדש.
      } on FileSystemException {
        // קובץ שאינו קריא (נעול, לא UTF-8) נכתב מחדש.
      }
    }
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...content,
        'writtenAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await tmp.rename(file.path);
    return true;
  }

  static Future<bool> writeForCurrentProcess() async => writeIfChanged(
    await AppPaths.getDataRootPath(),
    build(
      packageInfo: await PackageInfo.fromPlatform(),
      arch: currentArch(),
      portable: AppPaths.isPortable,
      exePath: Platform.resolvedExecutable,
      libraryDbPath: DatabaseConstants.getDatabasePath(),
    ),
  );
}
