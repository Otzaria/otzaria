import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/responsa_bridge_client.dart';
import 'package:path/path.dart' as path;

/// מאתר ומפעיל את גשר פרויקט השו"ת.
///
/// **הגשר לעולם אינו מופעל בעליית אוצריא.** הוא עולה רק כשהמשתמש מבקש
/// לפתוח ספר, וגם אז רק אם ההגדרה מתירה זאת. הקטלוג עצמו אינו תלוי בו:
/// ספרי פרויקט השו"ת מופיעים בחיפוש מתוך SQLite מקומי גם כשהגשר כבוי.
class ResponsaBridgeLauncher {
  static const String executableName = 'responsa_bridge.exe';

  /// משתנה סביבה לעקיפת האיתור — נוח בפיתוח ובבדיקות שדה.
  static const String pathEnvironmentVariable = 'OTZARIA_RESPONSA_BRIDGE';

  /// כמה להמתין עד שהגשר כותב את קובץ ה-discovery ועונה.
  static const Duration readyTimeout = Duration(seconds: 45);

  final ResponsaBridgeClient client;

  /// עוקף את איתור קובץ ההרצה בבדיקות.
  @visibleForTesting
  String? executablePathOverride;

  ResponsaBridgeLauncher({required this.client});

  /// נתיב קובץ ההרצה של הגשר, או `null` אם אינו מותקן.
  String? resolveExecutable() {
    if (executablePathOverride case final override?) {
      return File(override).existsSync() ? override : null;
    }
    final configured = Platform.environment[pathEnvironmentVariable];
    if (configured != null &&
        configured.isNotEmpty &&
        File(configured).existsSync()) {
      return configured;
    }
    final beside = path.join(
      path.dirname(Platform.resolvedExecutable),
      executableName,
    );
    return File(beside).existsSync() ? beside : null;
  }

  bool get isInstalled => resolveExecutable() != null;

  /// מוודא שהגשר רץ ומוכן.
  ///
  /// מחזיר `null` בהצלחה, או קוד שגיאה יציב:
  /// `bridgeDisabled` / `bridgeNotInstalled` / `bridgeLaunchFailed` /
  /// `bridgeNotReady`.
  Future<String?> ensureRunning({required bool allowStart}) async {
    if (await client.isRunning()) return null;
    if (!allowStart) return 'bridgeDisabled';

    final executable = resolveExecutable();
    if (executable == null) return 'bridgeNotInstalled';

    try {
      await Process.start(
        executable,
        const ['serve'],
        workingDirectory: path.dirname(executable),
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      debugPrint('ResponsaBridgeLauncher: launch failed: $e');
      return 'bridgeLaunchFailed';
    }

    final deadline = DateTime.now().add(readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (await client.isRunning()) return null;
    }
    return 'bridgeNotReady';
  }
}
