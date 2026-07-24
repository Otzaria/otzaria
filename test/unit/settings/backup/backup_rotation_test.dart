import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/backup/backup_rotation.dart';

void main() {
  final now = DateTime(2026, 7, 5, 12);

  BackupEntryInfo entry(DateTime ts, {bool manual = false}) => BackupEntryInfo(
    path: ts.toIso8601String(),
    timestamp: ts,
    isManual: manual,
  );

  List<String> expiredPaths(
    List<BackupEntryInfo> backups, [
    RetentionProfile profile = RetentionProfile.balanced,
  ]) => BackupRotation.selectExpired(
    backups,
    profile,
    now,
  ).map((b) => b.path).toList();

  test('keepAll — שום גיבוי אינו נמחק', () {
    final backups = [
      entry(now.subtract(const Duration(days: 1000))),
      entry(now.subtract(const Duration(days: 10))),
    ];
    expect(expiredPaths(backups, RetentionProfile.keepAll), isEmpty);
  });

  test('גיבויים בחלון היומי נשמרים כולם', () {
    final backups = [
      entry(now.subtract(const Duration(days: 1))),
      entry(now.subtract(const Duration(days: 2))),
      entry(now.subtract(const Duration(days: 6))),
    ];
    expect(expiredPaths(backups), isEmpty);
  });

  test('בחלון השבועי נשמר רק החדש בכל שבוע', () {
    // שני גיבויים באותו שבוע (מעבר לחלון היומי): הישן פג
    final a = entry(now.subtract(const Duration(days: 14)));
    final b = entry(now.subtract(const Duration(days: 15)));
    expect(expiredPaths([a, b]), [b.path]);
  });

  test('בחלון החודשי נשמר אחד לחודש', () {
    final a = entry(DateTime(2026, 3, 20));
    final b = entry(DateTime(2026, 3, 5));
    final c = entry(DateTime(2026, 2, 10));
    expect(expiredPaths([a, b, c]), [b.path]);
  });

  test('מעבר לחלון החודשי — הכל פג (מועמד למיזוג לארכיון)', () {
    final old = entry(now.subtract(const Duration(days: 400)));
    expect(expiredPaths([old]), [old.path]);
  });

  test('גיבוי ידני לעולם אינו פג', () {
    final manualOld = entry(
      now.subtract(const Duration(days: 500)),
      manual: true,
    );
    final autoOld = entry(now.subtract(const Duration(days: 500)));
    expect(expiredPaths([manualOld, autoOld]), [autoOld.path]);
  });

  test('economy מחמיר מ-balanced', () {
    final backup = entry(now.subtract(const Duration(days: 5)));
    // בן 5 ימים: בתוך החלון היומי של balanced (7) אך מחוץ לזה של economy (3).
    expect(expiredPaths([backup], RetentionProfile.balanced), isEmpty);
    // לבדו בשבוע שלו — נשמר כנציג השבועי גם ב-economy
    expect(expiredPaths([backup], RetentionProfile.economy), isEmpty);
    // שני גיבויים באותו שבוע: ב-economy הישן פג
    final sameWeek = entry(now.subtract(const Duration(days: 6)));
    expect(
      expiredPaths([backup, sameWeek], RetentionProfile.economy),
      [sameWeek.path],
    );
  });
}
