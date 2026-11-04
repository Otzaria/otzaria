import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/system_account_info.dart';
import 'package:path/path.dart' as p;

void main() {
  ProcessRunner whoamiReturning(String stdout, {int exitCode = 0}) {
    return (executable, arguments) async =>
        ProcessResult(0, exitCode, stdout, '');
  }

  ProcessRunner idReturning({required String uid, required String groups}) {
    return (executable, arguments) async {
      if (p.basename(executable) != 'id') return ProcessResult(0, 1, '', '');
      return ProcessResult(0, 0, arguments.contains('-u') ? uid : groups, '');
    };
  }

  group('SystemAccountProbe.detectWindows', () {
    test('SID של קבוצת המנהלים מזהה חשבון מנהל', () async {
      // token מפוצל: ה-SID מופיע כ-deny only והתהליך אינו elevated.
      final info = await SystemAccountProbe.detectWindows(
        whoamiReturning(
          '"BUILTIN\\Administrators","S-1-5-32-544","Group used for deny only"\n'
          '"Mandatory Label\\Medium Mandatory Level","S-1-16-8192","Label"',
        ),
      );

      expect(info.accountType, UserAccountType.administrator);
      expect(info.isElevated, isFalse);
    });

    test('דרגת שלמות High מסמנת ריצה elevated', () async {
      final info = await SystemAccountProbe.detectWindows(
        whoamiReturning(
          '"BUILTIN\\Administrators","S-1-5-32-544","Enabled group"\n'
          '"Mandatory Label\\High Mandatory Level","S-1-16-12288","Label"',
        ),
      );

      expect(info.accountType, UserAccountType.administrator);
      expect(info.isElevated, isTrue);
    });

    test('דרגת שלמות System מסמנת elevated', () async {
      final info = await SystemAccountProbe.detectWindows(
        whoamiReturning(
          '"Mandatory Label\\System Mandatory Level","S-1-16-16384","Label"',
        ),
      );

      expect(info.isElevated, isTrue);
    });

    test('חשבון בלי SID של מנהלים הוא חשבון רגיל', () async {
      final info = await SystemAccountProbe.detectWindows(
        whoamiReturning(
          '"Everyone","S-1-1-0","Mandatory group"\n'
          '"Mandatory Label\\Medium Mandatory Level","S-1-16-8192","Label"',
        ),
      );

      expect(info.accountType, UserAccountType.standard);
      expect(info.isElevated, isFalse);
    });

    test('כשל בהרצת whoami מחזיר unknown', () async {
      final info = await SystemAccountProbe.detectWindows(
        whoamiReturning('', exitCode: 1),
      );

      expect(info.accountType, UserAccountType.unknown);
      expect(info.isElevated, isNull);
    });
  });

  group('SystemAccountProbe.detectPosix', () {
    test('uid 0 מזוהה כמנהל ו-elevated', () async {
      final info = await SystemAccountProbe.detectPosix(
        idReturning(uid: '0', groups: 'root'),
      );

      expect(info.accountType, UserAccountType.administrator);
      expect(info.isElevated, isTrue);
    });

    test('חברות ב-sudo מזוהה כמנהל בלי הרשאות מוגברות', () async {
      final info = await SystemAccountProbe.detectPosix(
        idReturning(uid: '1000', groups: 'users sudo docker'),
      );

      expect(info.accountType, UserAccountType.administrator);
      expect(info.isElevated, isFalse);
    });

    test('חברות ב-wheel או admin נחשבת גם היא ניהולית', () async {
      for (final group in ['wheel', 'admin']) {
        final info = await SystemAccountProbe.detectPosix(
          idReturning(uid: '501', groups: 'staff $group'),
        );

        expect(
          info.accountType,
          UserAccountType.administrator,
          reason: group,
        );
      }
    });

    test('משתמש רגיל ללא קבוצת ניהול', () async {
      final info = await SystemAccountProbe.detectPosix(
        idReturning(uid: '1000', groups: 'users docker'),
      );

      expect(info.accountType, UserAccountType.standard);
      expect(info.isElevated, isFalse);
    });

    test('כשל בהרצת id מחזיר unknown', () async {
      final info = await SystemAccountProbe.detectPosix(
        (executable, arguments) async => ProcessResult(0, 1, '', ''),
      );

      expect(info.accountType, UserAccountType.unknown);
      expect(info.isElevated, isNull);
    });
  });

  group('SystemAccountProbe.detect', () {
    test('חריגה בהרצת התהליך אינה מתפשטת', () async {
      final info = await SystemAccountProbe.detect(
        runProcess: (executable, arguments) async =>
            throw ProcessException(executable, arguments, 'לא נמצא'),
      );

      expect(info.accountType, UserAccountType.unknown);
    });
  });

  group('SystemAccountProbe.runOffMainIsolate', () {
    final skip = Platform.isWindows || Platform.isLinux || Platform.isMacOS
        ? false
        : 'אין whoami/id בפלטפורמה';

    test('מחזיר את תוצאת התהליך מה-isolate העזר', () async {
      final result = Platform.isWindows
          ? await SystemAccountProbe.runOffMainIsolate(
              SystemAccountProbe.whoamiExecutable,
              ['/groups', '/fo', 'csv', '/nh'],
            )
          : await SystemAccountProbe.runOffMainIsolate(
              SystemAccountProbe.idExecutable,
              ['-u'],
            );

      expect(result.exitCode, 0);
      expect(result.stdout, isA<String>());
      expect((result.stdout as String).trim(), isNotEmpty);
    }, skip: skip);

    test('קובץ הרצה חסר זורק ולא מחזיר תוצאה', () async {
      await expectLater(
        SystemAccountProbe.runOffMainIsolate(
          p.join(Directory.systemTemp.path, 'otzaria_missing_probe_exe'),
          const [],
        ),
        throwsA(anything),
      );
    });
  });
}
