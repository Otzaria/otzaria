import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/backup_service.dart';

/// שומר על כיסוי הגיבוי: כל מקום שמירה בתוכנה חייב להיות מוכרע במפורש
/// כמגובה ([BackupService.backedUpStores]) או כלא-מגובה-במכוון
/// ([BackupService.unbackedStores]).
///
/// בלי השומר, מקום שמירה חדש נשמט מהגיבוי בשקט — כך אבדו ההתאמות הפר-ספריות,
/// שיושבות בקבצי JSON מחוץ ל-Hive ולכן לא נתפסו על ידי שומר מפתחות ההגדרות.
///
/// היקף הסריקה: Hive boxes (בשם מילולי או דרך קבוע, גם `Class.const` מקובץ
/// אחר), מסדי נתונים שנפתחים דרך `resolveNotesDbPath('name.db')` (מילולי
/// בלבד), ומקומות שנבנים מ*שורש הנתונים* דרך `p.join`. שני דפוסים אינם בתחום
/// ולא ייתפסו: נתיב שנבנה באינטרפולציה (`'$root/x'`), ו-`p.join` על משתנה
/// שאין בשמו `dataRoot`. יעד שנבנה מנתיב בסיס אחר (יומני הריצה, שנופלים
/// ל-temp כשאין שורש נתונים) אינו בתחום אף הוא.
void main() {
  /// שמות ה-Hive boxes שנפתחים בקוד: `openBox…('name')`.
  final boxPattern = RegExp(r"""openBox[^(]*\(\s*'([^']+)'""");

  /// `openBox…(kBoxName)` ו-`openBox…(Service.boxName)` — השם מגיע מקבוע ונפתר
  /// מהצהרתו בכל קובצי `lib`; בלי פתירה בין קבצים ה-box נשמט מהסריקה כולה.
  final boxViaIdentifierPattern = RegExp(
    r"""openBox[^(]*\(\s*(?:[A-Za-z_]\w*\s*\.\s*)?([A-Za-z_]\w*)\s*[,)]""",
  );

  /// הצהרת קבוע מחרוזת: `static const String kName = 'value';`
  final constDeclarationPattern = RegExp(
    r"""const\s+(?:String\s+)?([A-Za-z_]\w*)\s*=\s*'([^']+)'""",
  );

  /// תיקיות שנוצרות ישירות תחת שורש הנתונים: `p.join(<dataRoot>, 'name')`.
  final dataRootDirPattern = RegExp(
    r"""p\.join\(\s*(?:await\s+)?[\w.]*(?:[dD]ataRoot|dataRoot)\w*(?:\(\))?\s*,\s*'([^']+)'""",
  );

  /// אותו דבר כששם התיקייה מגיע מקבוע: `p.join(<dataRoot>, kDirName)`.
  ///
  /// ⚠️ נדרש בדיוק כמו ב-[boxViaIdentifierPattern]. בלעדיו תיקייה שנוצרת
  /// תחת שורש הנתונים עם שם מקבוע — כפי ש-`windows/` נוצרה — אינה נסרקת
  /// כלל, והשומר עובר בשקט על מקום שמירה שלא הוכרע.
  final dataRootDirViaIdentifierPattern = RegExp(
    r"""p\.join\(\s*(?:await\s+)?[\w.]*(?:[dD]ataRoot|dataRoot)\w*(?:\(\))?\s*,\s*(?:[A-Za-z_]\w*\s*\.\s*)?([A-Za-z_]\w*)\s*[,)]""",
  );

  /// מסדי נתונים בתיקיית `databases`: `resolveNotesDbPath('name.db')`.
  final databaseFilePattern = RegExp(r"""resolveNotesDbPath\(\s*'([^']+)'""");

  /// ה-box של ההגדרות נפתח דרך `HiveCache.keyName` ולא כמילולית.
  const settingsBoxName = 'app_preferences';

  late Set<String> discovered;

  setUpAll(() {
    final sources = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      // קוד מוערך אינו מקום שמירה קיים (`user_overrides` נוטרל בהערה).
      sources.add(
        file
            .readAsLinesSync()
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n'),
      );
    }

    // אותו שם קבוע מוצהר בכמה מחלקות (`queueBoxName` בשני שירותי הדיווחים),
    // ולכן כל הערכים נאספים: עודף גילוי רק מחייב הכרעה, וזה הכיוון הבטוח.
    final constants = <String, Set<String>>{};
    for (final source in sources) {
      for (final match in constDeclarationPattern.allMatches(source)) {
        constants.putIfAbsent(match.group(1)!, () => {}).add(match.group(2)!);
      }
    }

    final names = <String>{settingsBoxName};
    for (final source in sources) {
      for (final pattern in [
        boxPattern,
        dataRootDirPattern,
        databaseFilePattern,
      ]) {
        for (final match in pattern.allMatches(source)) {
          names.add(match.group(1)!);
        }
      }
      for (final pattern in [
        boxViaIdentifierPattern,
        dataRootDirViaIdentifierPattern,
      ]) {
        for (final match in pattern.allMatches(source)) {
          names.addAll(constants[match.group(1)!] ?? const <String>{});
        }
      }
    }
    discovered = names;
  });

  test('הסורק מוצא את מקומות השמירה המרכזיים', () {
    // בלי הבדיקה הזאת, regex שנשבר היה הופך את השומר לירוק-תמיד.
    expect(
      discovered,
      containsAll(<String>[
        settingsBoxName,
        'user_state.db',
        'personal_notes.db',
        'per_book_settings',
        'plugins',
      ]),
    );
  });

  test('כל מקום שמירה מוכרע — מגובה או לא-מגובה במכוון', () {
    final declared = {
      ...BackupService.backedUpStores,
      ...BackupService.unbackedStores.keys,
    };
    final undeclared = discovered.difference(declared);

    expect(
      undeclared,
      isEmpty,
      reason:
          'מקומות שמירה שלא הוכרע לגביהם אם הם נכנסים לגיבוי: '
          '${undeclared.join(", ")}.\n'
          'יש להוסיף כל אחד ל-BackupService.backedUpStores (ולגבות אותו '
          'בפועל ב-createBackup/restoreFromBackup) או ל-unbackedStores '
          'עם הסיבה שאין לגבותו.',
    );
  });

  test('אין הצהרה על מקום שמירה שאינו קיים בקוד', () {
    final declared = {
      ...BackupService.backedUpStores,
      ...BackupService.unbackedStores.keys,
    };
    final stale = declared.difference(discovered);

    expect(
      stale,
      isEmpty,
      reason:
          'הצהרות על מקומות שמירה שאינם קיימים עוד בקוד: ${stale.join(", ")}',
    );
  });

  test('מקום שמירה אינו מוצהר גם כמגובה וגם כלא-מגובה', () {
    expect(
      BackupService.backedUpStores.intersection(
        BackupService.unbackedStores.keys.toSet(),
      ),
      isEmpty,
    );
  });

  test('לכל מקום שאינו מגובה יש סיבה כתובה', () {
    for (final entry in BackupService.unbackedStores.entries) {
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: 'חסרה סיבה ל-${entry.key}',
      );
    }
  });
}
