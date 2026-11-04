import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// סוג חשבון המשתמש שמריץ את התוכנה.
enum UserAccountType {
  /// החשבון חבר בקבוצת המנהלים.
  administrator,

  /// חשבון משתמש רגיל.
  standard,

  /// לא ניתן לקבוע (פלטפורמה שאינה תומכת, או שהבדיקה נכשלה).
  unknown,
}

/// סוג החשבון והאם התהליך רץ בהרשאות מוגברות.
class SystemAccountInfo {
  final UserAccountType accountType;

  /// האם התהליך עצמו רץ elevated (Windows: High/System integrity;
  /// POSIX: uid 0). null כשלא ניתן לקבוע.
  final bool? isElevated;

  const SystemAccountInfo({
    this.accountType = UserAccountType.unknown,
    this.isElevated,
  });
}

/// חתימת מריץ תהליכים — ניתנת להזרקה בבדיקות.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// מזהה את סוג חשבון המשתמש הנוכחי.
///
/// הזיהוי מריץ תהליך חד-פעמי (`whoami` / `id`) ולכן נקרא רק לפי דרישה —
/// כשמבקשים דוח מידע — ולא בעליית האפליקציה.
///
/// שמות ההרצה מוסמכים לנתיב מוחלט: `Process.run` עם שם לא מוסמך מחפש קודם
/// בתיקיית ה-exe וב-CWD, ובהתקנה פר-משתמש התיקייה כתיבה למשתמש — כך
/// `whoami.exe` מושתל היה רץ בכל בקשת דוח, שקישור `otzaria://info` מפעיל.
class SystemAccountProbe {
  /// SID של קבוצת המנהלים המובנית ב-Windows. מופיע גם ב-token מפוצל (לא
  /// elevated) עם "deny only", ולכן קיומו מעיד על סוג החשבון ולא על הרשאות.
  static const String _administratorsSid = 'S-1-5-32-544';

  /// דרגות שלמות שמעידות על תהליך elevated (High ו-System).
  static const List<String> _elevatedIntegritySids = [
    'S-1-16-12288',
    'S-1-16-16384',
  ];

  static const List<String> _posixAdminGroups = ['sudo', 'wheel', 'admin'];

  const SystemAccountProbe._();

  /// `whoami.exe` מתוך System32.
  @visibleForTesting
  static String get whoamiExecutable => p.join(
    Platform.environment['SystemRoot'] ?? r'C:\Windows',
    'System32',
    'whoami.exe',
  );

  /// `id` מנתיב מוחלט; בהיעדרו נופלים לשם הפקודה.
  @visibleForTesting
  static String get idExecutable {
    for (final candidate in const ['/usr/bin/id', '/bin/id']) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'id';
  }

  static Future<SystemAccountInfo> detect({ProcessRunner? runProcess}) async {
    final run = runProcess ?? runOffMainIsolate;
    try {
      if (Platform.isWindows) return await detectWindows(run);
      if (Platform.isLinux || Platform.isMacOS) return await detectPosix(run);
    } catch (error, stackTrace) {
      debugPrint('SystemAccountProbe failed: $error\n$stackTrace');
    }
    return const SystemAccountInfo();
  }

  @visibleForTesting
  static Future<SystemAccountInfo> detectWindows(ProcessRunner run) async {
    // /fo csv /nh מבטיח פלט אחיד ללא כותרות ובלי תלות בשפת הממשק — ה-SID-ים
    // עצמם הם המפתח, שמות הקבוצות מתורגמים.
    final result = await run(whoamiExecutable, [
      '/groups',
      '/fo',
      'csv',
      '/nh',
    ]);
    if (result.exitCode != 0) return const SystemAccountInfo();

    final output = '${result.stdout}';
    return SystemAccountInfo(
      accountType: output.contains(_administratorsSid)
          ? UserAccountType.administrator
          : UserAccountType.standard,
      isElevated: _elevatedIntegritySids.any(output.contains),
    );
  }

  @visibleForTesting
  static Future<SystemAccountInfo> detectPosix(ProcessRunner run) async {
    final executable = idExecutable;
    final uidResult = await run(executable, ['-u']);
    final uid = uidResult.exitCode == 0
        ? int.tryParse('${uidResult.stdout}'.trim())
        : null;
    if (uid == 0) {
      return const SystemAccountInfo(
        accountType: UserAccountType.administrator,
        isElevated: true,
      );
    }

    final groupsResult = await run(executable, ['-Gn']);
    if (groupsResult.exitCode != 0) {
      // uid ידוע אבל החברות בקבוצות אינה — סוג החשבון נשאר unknown ולא
      // מדווח 'רגיל' בביטחון שאין לו בסיס.
      return SystemAccountInfo(isElevated: uid == null ? null : false);
    }

    final groups = '${groupsResult.stdout}'
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .toSet();
    return SystemAccountInfo(
      accountType: _posixAdminGroups.any(groups.contains)
          ? UserAccountType.administrator
          : UserAccountType.standard,
      isElevated: uid == null ? null : false,
    );
  }

  /// ב-Windows Process.run קורא ל-CreateProcess סינכרונית ב-thread של ה-isolate
  /// הקורא; ב-isolate הראשי זה ה-thread של הממשק.
  @visibleForTesting
  static Future<ProcessResult> runOffMainIsolate(
    String executable,
    List<String> arguments,
  ) => Isolate.run(() => Process.run(executable, arguments));
}
