import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/services/startup_recovery_check.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// recovery שמדמה סימון שלא ניתן למחיקה (ProgramData ללא הרשאת כתיבה).
class _UndeletableMarkerRecovery extends LibraryDbRecoveryService {
  const _UndeletableMarkerRecovery();

  @override
  void clearStaleArtifacts(String dbPath) {
    // המחיקה "נכשלת" בשקט — כמו _deleteQuietly על קובץ ללא הרשאה.
  }
}

void main() {
  late Directory tmp;
  late String dbPath;
  late Map<String, String> prefs;
  late List<String> loggedTitles;
  late int quickCheckRuns;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('recovery_check');
    dbPath = '${tmp.path}/seforim.db';
    File(dbPath).writeAsStringSync('fake-db');
    prefs = {};
    loggedTitles = [];
    quickCheckRuns = 0;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void writeMarker() {
    File('$dbPath.applying').writeAsStringSync(
      jsonEncode({'fromVersion': 6, 'toVersion': 7, 'timestamp': 't1'}),
      flush: true,
    );
  }

  StartupRecoveryCheck buildCheck({
    required bool quickCheckResult,
    LibraryDbRecoveryService recovery = const LibraryDbRecoveryService(),
  }) {
    return StartupRecoveryCheck(
      recovery: recovery,
      runQuickCheck: (path) async {
        quickCheckRuns++;
        return quickCheckResult;
      },
      readPref: (key) => prefs[key],
      writePref: (key, value) async => prefs[key] = value,
      logError: (title, message) => loggedTitles.add(title),
    );
  }

  Future<void> runAndVerify(StartupRecoveryCheck check) async {
    await check.run(dbPath);
    await check.verifyPending();
  }

  test(
    'סימון ללא גיבוי — run מסתיים בלי quick_check; הסריקה רק ב-verifyPending',
    () async {
      writeMarker();
      final check = buildCheck(quickCheckResult: true);
      await check.run(dbPath);
      expect(quickCheckRuns, 0);
      expect(check.hasPendingVerification, isTrue);
      expect(File('$dbPath.applying').existsSync(), isTrue);

      await check.verifyPending();
      expect(quickCheckRuns, 1);
      expect(check.hasPendingVerification, isFalse);
      expect(File('$dbPath.applying').existsSync(), isFalse);

      // קריאה חוזרת אינה סורקת שוב.
      await check.verifyPending();
      expect(quickCheckRuns, 1);
    },
  );

  test('ללא סימון — אין quick_check ואין רישום', () async {
    await runAndVerify(buildCheck(quickCheckResult: true));
    expect(quickCheckRuns, 0);
    expect(loggedTitles, isEmpty);
    expect(prefs, isEmpty);
  });

  test('סימון + quick_check עובר → הסימון נמחק, בלי העדפה ובלי לוג', () async {
    writeMarker();
    await runAndVerify(buildCheck(quickCheckResult: true));
    expect(quickCheckRuns, 1);
    expect(File('$dbPath.applying').existsSync(), isFalse);
    expect(prefs, isEmpty);
    expect(loggedTitles, isEmpty);
  });

  test('סימון שאינו ניתן למחיקה — הסריקה רצה פעם אחת בלבד', () async {
    writeMarker();
    const recovery = _UndeletableMarkerRecovery();

    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 1);
    expect(File('$dbPath.applying').existsSync(), isTrue);
    expect(prefs[StartupRecoveryCheck.prefKey], startsWith('ok|'));
    expect(loggedTitles, ['Library update marker cleanup failed']);

    // "עלייה" שנייה עם אותו סימון: בלי סריקה חוזרת ובלי לוג נוסף.
    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 1);
    expect(loggedTitles, hasLength(1));
  });

  test('DB פגום — נסרק פעם אחת, נרשם לוג, ולא נסרק שוב', () async {
    writeMarker();

    await runAndVerify(buildCheck(quickCheckResult: false));
    expect(quickCheckRuns, 1);
    expect(File('$dbPath.applying').existsSync(), isTrue);
    expect(prefs[StartupRecoveryCheck.prefKey], startsWith('corrupt|'));
    expect(loggedTitles, [
      'Library DB failed quick_check after interrupted update',
    ]);

    await runAndVerify(buildCheck(quickCheckResult: false));
    expect(quickCheckRuns, 1);
    expect(loggedTitles, hasLength(1));
  });

  test('סימון חדש (עדכון אחר) מפקיע תוצאה שמורה — הסריקה רצה שוב', () async {
    writeMarker();
    const recovery = _UndeletableMarkerRecovery();
    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 1);

    // עדכון חדש כותב סימון עם תוכן אחר.
    File('$dbPath.applying').writeAsStringSync(
      jsonEncode({'fromVersion': 7, 'toVersion': 8, 'timestamp': 't2'}),
      flush: true,
    );
    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 2);
  });

  test('סימון + גיבוי → שחזור מהגיבוי בלי quick_check', () async {
    writeMarker();
    File('$dbPath.backup').writeAsStringSync('fake-db');

    await runAndVerify(buildCheck(quickCheckResult: true));
    expect(quickCheckRuns, 0);
    expect(File('$dbPath.applying').existsSync(), isFalse);
    expect(File('$dbPath.backup').existsSync(), isFalse);
    expect(File(dbPath).readAsStringSync(), 'fake-db');
  });

  group('שאריות של המעדכן הלא-מקוון', () {
    test('מסד חסר — <db>.old חוזר לשמו', () async {
      File(dbPath).deleteSync();
      File('$dbPath.old').writeAsStringSync('retired-db');

      await runAndVerify(buildCheck(quickCheckResult: true));

      expect(File(dbPath).readAsStringSync(), 'retired-db');
      expect(File('$dbPath.old').existsSync(), isFalse);
    });

    test('מסד באורך 0 — מוחלף ב-<db>.old', () async {
      File(dbPath).writeAsStringSync('');
      File('$dbPath.old').writeAsStringSync('retired-db');

      await runAndVerify(buildCheck(quickCheckResult: true));

      expect(File(dbPath).readAsStringSync(), 'retired-db');
    });

    test('מסד תקין — <db>.old ו-<db>.unverified אינם נוגעים בו', () async {
      File('$dbPath.old').writeAsStringSync('retired-db');
      File('$dbPath.unverified').writeAsStringSync('{"version":7}');

      await runAndVerify(buildCheck(quickCheckResult: true));

      expect(File(dbPath).readAsStringSync(), 'fake-db');
      expect(File('$dbPath.old').existsSync(), isTrue);
      expect(File('$dbPath.unverified').existsSync(), isTrue);
      expect(quickCheckRuns, 0);
    });
  });
}
