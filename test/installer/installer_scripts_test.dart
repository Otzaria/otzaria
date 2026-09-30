import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/plugins/services/bundled_plugin_seed_service.dart';
import 'package:otzaria/settings/settings_exports.dart';

/// טסטים על סקריפטי ה-Inno Setup. הם אינם נבנים ב-CI של הטסטים, ולכן ההגנה
/// היחידה עליהם היא קריאת הטקסט ואימות האינוריאנטות שמקשרות ביניהם לבין
/// [AppPaths] — שם האפליקציה קוראת את אותם מסמנים ומפתחות.

const _regular = 'otzaria.iss';
const _full = 'otzaria_full.iss';
const _scripts = [_regular, _full];

/// מסייע ההורדה אינו מתקין, ולכן אינו נכלל ב-[_scripts]: האינוריאנטות של
/// המתקינים (מסמנים, רישום, הסרה) אינן חלות עליו. הקבוצה הייעודית שלו
/// בסוף הקובץ מאמתת את האינוריאנטות שכן חלות.
const _assistant = 'download_assistant.iss';

String _script(String name) =>
    File('installer/$name').readAsStringSync().replaceAll('\r\n', '\n');

/// גוף מקטע `[Name]` עד כותרת המקטע הבא.
String _section(String script, String name) {
  final start = RegExp(
    '^\\[$name\\]\\s*\$',
    multiLine: true,
  ).firstMatch(script);
  expect(start, isNotNull, reason: 'המקטע [$name] חסר בסקריפט');
  final rest = script.substring(start!.end);
  final next = RegExp(r'^\[[A-Za-z]+\]\s*$', multiLine: true).firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

/// גוף שגרת Pascal מהחתימה ועד ה-`end;` שבתחילת שורה (שגרות ראשיות בלבד —
/// `end;` מקונן תמיד מוזח בקבצים האלה).
String _routine(String script, String signature) {
  final start = script.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'לא נמצאה השגרה $signature');
  final end = script.indexOf('\nend;', start);
  expect(end, greaterThan(start), reason: 'לא נמצא סוף השגרה $signature');
  return script.substring(start, end);
}

/// מכווץ רצפי רווחים כדי שהשוואות לא יישברו על עיצוב מחדש.
String _squeeze(String value) =>
    value.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

void main() {
  group('# בתחילת שורה נקרא כדירקטיבת preprocessor', () {
    // ISPP מפרש # בתחילת שורה גם אחרי הזחה, ולכן קבוע תווים שנדחף לראש
    // שורה בעיצוב מחדש שובר את הקומפילציה. ה-.iss אינו נבנה כאן, ולכן זו
    // ההגנה היחידה עליו.
    const directives = {
      'if',
      'ifdef',
      'ifndef',
      'ifexist',
      'ifnexist',
      'elif',
      'else',
      'endif',
      'define',
      'undef',
      'include',
      'error',
      'pragma',
      'expr',
      'insert',
      'sub',
      'endsub',
      'for',
      'dim',
      'emit',
      'file',
      'append',
      'preproc',
    };
    for (final name in _scripts) {
      test('$name: אין שורה שמתחילה ב-# שאינו דירקטיבה מוכרת', () {
        final offenders = <String>[];
        final lines = _script(name).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final match = RegExp(r'^\s*#([A-Za-z_]*)').firstMatch(lines[i]);
          if (match == null) continue;
          if (directives.contains(match.group(1)!.toLowerCase())) continue;
          offenders.add('${i + 1}: ${lines[i].trim()}');
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'שורות אלה ייכשלו ב-ISCC עם "Unknown preprocessor directive" — '
              'יש להמשיך בהן שורה קיימת:\n${offenders.join('\n')}',
        );
      });
    }
  });

  group('system_install.marker — כתיבה ומחיקה סימטריות', () {
    for (final name in _scripts) {
      test('$name: המסמן נכתב רק בהתקנת מנהל לא-ניידת', () {
        final ini = _section(_script(name), 'INI');
        final match = RegExp(
          r'system_install\.marker.*?Check:\s*(.+)$',
          multiLine: true,
        ).firstMatch(ini);

        expect(match, isNotNull, reason: 'אין רשומת [INI] למסמן');
        expect(
          _squeeze(match!.group(1)!),
          'IsAdminInstallMode and not IsPortableInstall',
          reason: 'תנאי הכתיבה השתנה — יש לעדכן איתו את תנאי המחיקה',
        );
      });

      test('$name: המסמן נמחק בכל מצב שאינו התקנת מנהל', () {
        final installDelete = _section(_script(name), 'InstallDelete');
        final match = RegExp(
          r'^Type:\s*files;\s*Name:\s*"\{app\}\\system_install\.marker";\s*'
          r'Check:\s*(.+)$',
          multiLine: true,
        ).firstMatch(installDelete);

        expect(
          match,
          isNotNull,
          reason:
              'בלי מחיקה, מסמן מהתקנת מנהל קודמת שורד מעבר להתקנת משתמש '
              'ו-AppPaths.detectInstallMode ימשיך להחזיר systemWide',
        );
        expect(
          _squeeze(match!.group(1)!),
          '(not IsAdminInstallMode) or IsPortableInstall',
          reason: 'תנאי המחיקה חייב להיות ההיפוך המדויק של תנאי הכתיבה',
        );
      });

      test('$name: שם המסמן זהה לשם שהאפליקציה מחפשת', () {
        final appPaths = File('lib/core/app_paths.dart').readAsStringSync();
        expect(appPaths, contains("'system_install.marker'"));
        expect(_script(name), contains(r'{app}\system_install.marker'));
      });

      test(
        '$name: שם מסמן המצב הנייד זהה ל-AppPaths.portableMarkerFileName',
        () {
          expect(_script(name), contains(AppPaths.portableMarkerFileName));
        },
      );
    }
  });

  group('portable.marker — התקנה רגילה מנקה מצב נייד קודם (issue #1031)', () {
    for (final name in _scripts) {
      test('$name: המסמן נמחק בכל התקנה שאינה ניידת', () {
        final installDelete = _section(_script(name), 'InstallDelete');
        final match = RegExp(
          r'^Type:\s*files;\s*Name:\s*"\{app\}\\portable\.marker";\s*'
          r'Check:\s*(.+)$',
          multiLine: true,
        ).firstMatch(installDelete);

        expect(
          match,
          isNotNull,
          reason:
              'בלי מחיקה, מסמן ממצב נייד קודם שורד להתקנה רגילה ו-AppPaths '
              'מפנה את כל הנתונים ל-otzaria_data תחת Program Files',
        );
        expect(
          _squeeze(match!.group(1)!),
          'not IsPortableInstall',
          reason: 'תנאי המחיקה חייב להיות ההיפוך המדויק של תנאי הכתיבה',
        );
      });

      test('$name: ההשקה מדף הסיום רצה כמשתמש המקורי', () {
        final run = _section(_script(name), 'Run');
        final match = RegExp(
          r'^Filename:\s*"\{app\}\\\{#MyAppExeName\}".*postinstall.*$',
          multiLine: true,
        ).firstMatch(run);

        expect(match, isNotNull, reason: 'רשומת ההשקה מדף הסיום נעלמה');
        expect(
          match!.group(0),
          contains('runasoriginaluser'),
          reason:
              'השקה מורמת יוצרת את תיקיות הנתונים עם ACL של מנהל — '
              'WebView2 של התוספים נכשל אז בכתיבה',
        );
      });
    }
  });

  group('מצב נייד נחסם ליעד מוגן (issue #1031)', () {
    for (final name in _scripts) {
      test('$name: הבדיקה חוסמת את "הבא" בעמוד בחירת התיקייה', () {
        final body = _routine(_script(name), 'function NextButtonClick(');
        final guardAt = body.indexOf('CurPageID = wpSelectDir');

        expect(
          guardAt,
          greaterThan(0),
          reason: 'החסימה נעלמה מ-NextButtonClick',
        );
        expect(
          guardAt,
          greaterThan(body.indexOf('WizardSilent')),
          reason:
              'בהתקנה שקטה אסור לגעת בכלום — /DIR שהועבר במפורש '
              'חייב להישמר',
        );

        final guard = body.substring(guardAt);
        expect(guard, contains('PortableMode'));
        expect(guard, contains('IsProtectedInstallDir'));
        expect(
          guard,
          contains('Result := False'),
          reason: 'בלי זה האשף ממשיך ליעד החסום למרות האזהרה',
        );
      });

      test('$name: היעדים המוגנים מכסים את תיקיות המערכת', () {
        final fn = _routine(_script(name), 'function IsProtectedInstallDir(');

        for (final root in const [
          '{commonpf}',
          '{commonpf32}',
          '{win}',
          '{commonappdata}',
        ]) {
          expect(
            fn,
            contains(root),
            reason: '$root אינו נבדק — התקנה ניידת תוכל לנחות שם',
          );
        }
      });
    }
  });

  group('GetDataDir — מקור האמת למיקום הנתונים', () {
    for (final name in _scripts) {
      test('$name: מנהל → commonappdata, אחרת userappdata', () {
        final body = _routine(_script(name), 'function GetDataDir(');

        final adminBranch = body.indexOf('IsAdminInstallMode');
        final common = body.indexOf(r'{commonappdata}\otzaria');
        final elseBranch = body.indexOf('else');
        final user = body.indexOf(r'{userappdata}\otzaria');

        expect(adminBranch, greaterThanOrEqualTo(0));
        expect(common, greaterThan(adminBranch));
        expect(elseBranch, greaterThan(common));
        expect(user, greaterThan(elseBranch));
      });

      test('$name: מצב ההתקנה הוא lowest — ולכן GetDataDir תלוי-מצב', () {
        final script = _script(name);
        // ‎PrivilegesRequired=lowest אומר שהמתקין עולה לא-מורם כברירת מחדל,
        // ולכן מיקום הנתונים נגזר מבחירת המשתמש ולא מהעלייה עצמה.
        expect(script, contains('PrivilegesRequired=lowest'));
        expect(
          script,
          contains('PrivilegesRequiredOverridesAllowed=commandline'),
        );
      });
    }
  });

  group('נתיב הספרייה הקיים מנצח את ברירת המחדל', () {
    test('$_full: CreateBooksPage קורא את הנתיב השמור', () {
      final body = _routine(_script(_full), 'procedure CreateBooksPage;');

      expect(
        body,
        contains('GetCustomLibraryPath()'),
        reason:
            'בלי זה שינוי מצב ההתקנה מזיז את יעד החילוץ בעוד האפליקציה '
            'ממשיכה לקרוא מהנתיב הישן',
      );
      expect(
        body,
        contains('IsOtzariaBooksFolder('),
        reason: 'נתיב מ-prefs חייב אימות לפני שהוא נבחר כיעד חילוץ',
      );
    });

    test('$_full: InitializeSilentDefaults קורא את הנתיב השמור', () {
      final body = _routine(
        _script(_full),
        'procedure InitializeSilentDefaults();',
      );

      expect(body, contains('GetCustomLibraryPath()'));
      expect(body, contains('IsOtzariaBooksFolder('));
    });

    test('$_full: המסלול השקט והאינטראקטיבי מיישרים קו', () {
      final script = _script(_full);
      final silent = _routine(script, 'procedure InitializeSilentDefaults();');
      final wizard = _routine(script, 'procedure CreateBooksPage;');

      for (final guard in ['GetCustomLibraryPath()', 'IsOtzariaBooksFolder(']) {
        expect(
          silent.contains(guard) && wizard.contains(guard),
          isTrue,
          reason: 'שני המסלולים חייבים להשתמש ב-$guard, אחרת הם יתפצלו',
        );
      }
    });

    test('$_full: הספרייה מוחלפת רק אחרי חילוץ מלא — לא נמחקת מראש', () {
      final script = _script(_full);
      final installDelete = _section(script, 'InstallDelete');

      expect(
        installDelete,
        isNot(contains('GetSelectedBooksPath')),
        reason:
            'מחיקת הספרייה בתחילת ההתקנה השאירה משדרגים בלי ספרייה '
            'כשהחילוץ נקטע (issue #867)',
      );

      final extract = _routine(
        script,
        'procedure ExtractEmbeddedLibraryArchives();',
      );
      expect(
        extract,
        contains('ExtractFileDir(SelectedBooksPath)'),
        reason: 'ה-staging חייב לשבת ליד היעד — rename עובד רק באותו כונן',
      );

      final lastExtract = extract.lastIndexOf('ExtractBundled');
      final backupOld = extract.indexOf(
        'RenameFile(SelectedBooksPath, BooksBackup)',
      );
      final moveNew = extract.indexOf(
        'RenameFile(StagingBooks, SelectedBooksPath)',
      );
      expect(
        backupOld,
        greaterThan(lastExtract),
        reason: 'ההחלפה חייבת לבוא אחרי שכל החילוצים הצליחו',
      );
      expect(moveNew, greaterThan(backupOld));
    });

    test(
      '$_full: ארכיון חסר או ספרייה בלי seforim.db מכשילים — לא דילוג שקט',
      () {
        final script = _script(_full);

        for (final proc in [
          'procedure ExtractBundledDatabase(',
          'procedure ExtractBundledTarArchive(',
        ]) {
          final body = _routine(script, proc);
          expect(
            body,
            isNot(contains('skipping')),
            reason:
                'דילוג שקט על ארכיון חסר הסתיים כהתקנה "מוצלחת" בלי ספרייה '
                '(issue #862)',
          );
          final notFound = body.indexOf('not FileExists(ArchivePath)');
          final abortPos = body.indexOf('Abort;');
          expect(notFound, greaterThanOrEqualTo(0));
          expect(
            abortPos,
            greaterThan(notFound),
            reason: 'ארכיון חסר חייב להציג שגיאה ולעצור את החילוץ',
          );
        }

        final extract = _routine(
          script,
          'procedure ExtractEmbeddedLibraryArchives();',
        );
        final verify = extract.indexOf(
          "StagingBooks + '\\{#BundledLibraryDbName}'",
        );
        final swap = extract.indexOf(
          'RenameFile(StagingBooks, SelectedBooksPath)',
        );
        expect(verify, greaterThanOrEqualTo(0));
        expect(
          swap,
          greaterThan(verify),
          reason: 'אימות seforim.db חייב לבוא לפני החלפת הספרייה (issue #862)',
        );
      },
    );
  });

  group('מתקין FULL מאונדקס מפוצל', () {
    test('המבנה המפוצל הוא מצב בנייה נוסף ואינו מחליף את FULL המשובץ', () {
      final script = _script(_full);

      expect(script, contains('#ifdef IndexedSplitFull'));
      expect(script, contains('windows-full-indexed'));
      expect(script, contains('#ifndef IndexedSplitFull'));
      expect(script, contains(r'Source: "library_db\seforim.db.zst"'));
    });

    test('מסד מסכמה 6 נארז כ-seforim.zdb ומועתק כמות שהוא', () {
      final script = _script(_full);

      expect(
        script,
        contains(
          r'#if FileExists(AddBackslash(SourcePath) + "library_db\seforim.zdb")',
        ),
      );
      expect(script, contains(r'Source: "library_db\seforim.zdb"'));
      expect(script, contains('#define BundledLibraryDbName "seforim.zdb"'));
      expect(script, contains('#define BundledLibraryDbName "seforim.db"'));
      expect(
        DatabaseConstants.zdbDatabaseFileName,
        'seforim.zdb',
        reason: 'המתקין מניח את ה-zdb בשם שהאפליקציה פותרת ליד seforim.db',
      );

      final install = _routine(script, 'procedure InstallBundledZdb(');
      expect(install, isNot(contains('zstd')));
      final missing = install.indexOf('not FileExists(TmpPath)');
      expect(missing, greaterThanOrEqualTo(0));
      expect(install.indexOf('Abort;'), greaterThan(missing));
      // {tmp} בכונן אחר מהספרייה: rename נכשל, וההעתקה היא המסלול הרגיל.
      expect(install, contains('FileCopy(TmpPath, TargetPath, False)'));

      final extract = _routine(
        script,
        'procedure ExtractEmbeddedLibraryArchives();',
      );
      expect(
        extract,
        contains("InstallBundledZdb('seforim.zdb', StagingBooks)"),
      );
      expect(
        extract,
        contains(
          "ExtractBundledDatabase('seforim.db.zst', 'seforim.db', "
          'StagingBooks)',
        ),
      );
    });

    test('תיקיית ספרים עם seforim.zdb בלבד מזוהה כתיקיית אוצריא', () {
      for (final name in _scripts) {
        final body = _routine(_script(name), 'function IsOtzariaBooksFolder(');
        expect(
          body,
          contains(r"FileExists(Path + '\seforim.zdb')"),
          reason: name,
        );
      }
    });

    test('החבילה המאונדקסת מתקבלת עם seforim.zdb או עם seforim.db', () {
      final body = _routine(
        _script(_full),
        'procedure ExtractIndexedLibraryArchive();',
      );

      expect(
        body,
        contains("(not FileExists(SourceBooks + '\\seforim.zdb')) and"),
      );
      expect(
        body,
        contains("(not FileExists(SourceBooks + '\\seforim.db'))"),
      );
    });

    test('מזהה manifest וחלקים תקינים לצד קובץ המתקין', () {
      final script = _script(_full);
      final prepare = _routine(
        script,
        'function PrepareIndexedLibrary(): Boolean;\nvar',
      );
      final localCheck = _routine(
        script,
        'function LocalIndexedPartsAreComplete(',
      );

      expect(prepare, contains(r"ExpandConstant('{srcexe}')"));
      expect(
        prepare,
        contains("ExtractTemporaryFile('{#IndexedEmbeddedManifestName}')"),
        reason: 'offline צריך לדרוש רק מתקין וחלקים, בלי manifest נפרד',
      );
      expect(prepare, contains('LocalIndexedPartsAreComplete(SourceDir)'));
      expect(localCheck, contains('FileExists(PartPath)'));
      expect(prepare, contains('AssembleIndexedArchive()'));
      expect(
        File('tool/release/assemble_split_asset.ps1').readAsStringSync(),
        contains(r'$part.sha256'),
      );
    });

    test('חלקים חסרים יורדים דרך מסך ההורדה עם hash מה-manifest', () {
      final script = _script(_full);
      final download = _routine(script, 'function DownloadIndexedParts()');

      expect(download, contains('IndexedDownloadPage.Add('));
      expect(download, contains('IndexedPartHashes[I]'));
      expect(download, contains('IndexedDownloadPage.Download'));
    });

    test('הארכיון מוכן לפני תחילת ההתקנה והספרייה מוחלפת רק אחרי חילוץ', () {
      final script = _script(_full);
      final next = _routine(script, 'function NextButtonClick(');
      final extract = _routine(
        script,
        'procedure ExtractIndexedLibraryArchive();',
      );

      expect(next, contains('(CurPageID = wpReady)'));
      expect(next, contains('PrepareIndexedLibrary()'));
      expect(
        next.indexOf('PrepareIndexedLibrary()'),
        lessThan(next.indexOf('if (ModePage <> nil)')),
        reason: 'גם התקנה שקטה חייבת להכין את החלקים לפני היציאה המוקדמת',
      );
      expect(
        extract,
        contains(r"SourceIndex + '\.otzaria_prebuilt_index'"),
      );
      expect(extract, contains('RenameFile(SelectedBooksPath, BooksBackup)'));
      expect(extract, contains('RenameFile(SourceBooks, SelectedBooksPath)'));
    });
  });

  group('מפתח נתיב הספרייה ב-shared_preferences', () {
    for (final name in _scripts) {
      test('$name: הקריאה מ-prefs משתמשת במפתח של האפליקציה', () {
        final script = _script(name);
        final key = SettingsRepository.keyLibraryPath;

        expect(
          script,
          contains('"flutter.$key":'),
          reason: 'שינוי keyLibraryPath ב-Dart מחייב עדכון המתקין',
        );
        expect(script, contains('"$key":'));
        expect(
          _routine(script, 'function GetCustomLibraryPath('),
          contains(r'{userappdata}\otzaria\shared_preferences.json'),
        );
      });
    }

    test('$_full: הכתיבה ל-prefs משתמשת באותו מפתח', () {
      final wrapper = _routine(
        _script(_full),
        'procedure WriteLibraryPathToPrefs(',
      );
      final writer = _routine(
        _script(_full),
        'procedure WriteStringPreferenceToPrefs(',
      );
      expect(
        wrapper,
        contains("'${SettingsRepository.keyLibraryPath}'"),
      );
      expect(
        writer,
        contains("SharedPrefsKey := '\"flutter.' + PreferenceKey"),
      );
    });

    test('$_full: הכתיבה מאפסת שם תת-תיקייה ישן (issue #871)', () {
      final body = _routine(
        _script(_full),
        'procedure WriteLibraryPathToPrefs(',
      );

      expect(
        body,
        contains("'${SettingsRepository.keyLibraryFolderName}', ''"),
        reason:
            'ערך stale ב-keyLibraryFolderName מפנה את האפליקציה לתת-תיקייה '
            'שאינה קיימת — והספרייה שהותקנה זה עתה "נעלמת"',
      );
    });

    test('$_full: המתקין המאונדקס שומר גם את נתיב האינדקס הצמוד', () {
      final body = _routine(
        _script(_full),
        'procedure WriteLibraryPathToPrefs(',
      );

      expect(body, contains('#ifdef IndexedSplitFull'));
      expect(body, contains("'${SettingsRepository.keyIndexPath}'"));
      expect(body, contains("ExtractFileDir(LibraryPath) + '\\index'"));
    });
  });

  group('שיגור-מחדש של המתקין', () {
    for (final name in _scripts) {
      test('$name: אין Exec/ShellExec ישיר על {srcexe}', () {
        // Exec/ShellExec של Inno מסרבות להריץ את קובץ ה-Setup עצמו לפני
        // תחילת ההתקנה — הן נכשלות תמיד ומייצרות הודעת הרשאות שקרית.
        final hit = RegExp(
          r'\b(?:Exec|ShellExec)\s*\([^;]*\{srcexe\}',
        ).firstMatch(_script(name));

        expect(
          hit,
          isNull,
          reason: 'כל שיגור-מחדש חייב לעבור דרך RelaunchSetup',
        );
      });

      test('$name: RelaunchSetup מבוסס ShellExecuteW', () {
        final body = _routine(_script(name), 'function RelaunchSetup(');
        expect(body, contains('ShellExecuteW('));
        expect(body, contains(r"ExpandConstant('{srcexe}')"));
        expect(
          body,
          contains('> 32'),
          reason: 'ShellExecuteW מדווח הצלחה מעל 32',
        );
      });

      test('$name: RelaunchSetupElevated מאציל ל-RelaunchSetup עם runas', () {
        final body = _routine(
          _script(name),
          'function RelaunchSetupElevated(',
        );
        expect(body, contains("RelaunchSetup('runas'"));
      });

      test('$name: שדרוג אוטומטי מציג חלון התקדמות', () {
        final body = _routine(_script(name), 'function InitializeSetup()');
        final upgradeStart = body.indexOf(
          'if IsUpgradeFromModernVersion() then',
        );
        final upgradeEnd = body.indexOf(
          'if (not IsAdmin) and RequiresAdmin then',
          upgradeStart,
        );
        final upgrade = body.substring(upgradeStart, upgradeEnd);
        final relaunches = RegExp(
          r'Launched := RelaunchSetup(?:Elevated)?\(([\s\S]*?),\s*ResultCode\);',
        ).allMatches(upgrade).map((match) => match.group(0)!).toList();

        expect(relaunches, hasLength(2));
        for (final relaunch in relaunches) {
          expect(
            relaunch,
            contains("'/SILENT /SUPPRESSMSGBOXES /NORESTART"),
          );
          expect(relaunch, isNot(contains('/VERYSILENT')));
          expect(relaunch, contains('SW_SHOWNORMAL'));
          expect(relaunch, isNot(contains('SW_HIDE')));
        }
      });
    }
  });

  group('זיהוי התקנה קודמת — כיסוי כל אזורי הרישום', () {
    for (final name in _scripts) {
      test('$name: GetPreviousDisplayVersion בודק HKLM64, HKLM32 ו-HKCU', () {
        // התקנות מנהל ממתקינים ישנים נרשמו תחת WOW6432Node (HKLM32);
        // דילוג עליו מפיל שדרוג-שקט לאשף מלא.
        final body = _routine(
          _script(name),
          'function GetPreviousDisplayVersion(): String;',
        );
        final hklm64 = body.indexOf('HKLM64');
        final hklm32 = body.indexOf('HKLM32');
        final hkcu = body.indexOf('HKCU');
        expect(hklm64, greaterThanOrEqualTo(0));
        expect(hklm32, greaterThan(hklm64));
        expect(
          hkcu,
          greaterThan(hklm32),
          reason: 'רישום מערכתי (שני ה-HKLM) קודם לרישום פר-משתמש',
        );
      });

      test('$name: FindPreviousInstallDir מזהה HKLM32 כהתקנה מערכתית', () {
        final body = _routine(
          _script(name),
          'function FindPreviousInstallDir(',
        );
        final hklm32 = body.indexOf(
          'TryGetInstallDirFromRegistry(HKLM32, UninstallRegKey',
        );
        expect(hklm32, greaterThanOrEqualTo(0));
        final block = body.substring(hklm32, body.indexOf('exit;', hklm32));
        expect(
          block,
          contains('RequiresAdmin := True'),
          reason: 'התקנה תחת HKLM דורשת הרשאות מנהל לשדרוג',
        );
      });
    }
  });

  group('נתיב הספרייה נקרא מהקובץ שהאפליקציה רושמת (issue #1020)', () {
    for (final name in _scripts) {
      test('$name: הקובץ נקרא לפני ה-prefs הנטוש', () {
        final script = _script(name);
        final body = _routine(script, 'function GetCustomLibraryPath(');

        final recordCall = body.indexOf('ReadLibraryPathRecord(');
        final prefsRead = body.indexOf('shared_preferences.json');
        expect(
          recordCall,
          greaterThanOrEqualTo(0),
          reason:
              'ההגדרות יושבות ב-Hive; בלי הקובץ הזה ספרייה שהועברה מתוך '
              'התוכנה שורדת את ההסרה',
        );
        expect(
          recordCall,
          lessThan(prefsRead),
          reason: 'ה-prefs הוא מקור נסיגה בלבד — הקובץ הוא מקור האמת',
        );
      });

      test('$name: שם הקובץ זהה לשם שהאפליקציה כותבת', () {
        expect(
          _script(name),
          contains(
            "LibraryPathRecordFileName = '"
            '${AppPaths.libraryPathRecordFileName}'
            "'",
          ),
          reason: 'שינוי השם ב-Dart מחייב עדכון המתקין',
        );
      });

      test('$name: הסרת התקנת מנהל אינה מוחקת נתונים של פרופילים אחרים', () {
        final script = _script(name);
        final body = _routine(script, 'procedure DeleteAllUserData(');
        expect(
          body,
          isNot(contains('DeleteUserDataInAllProfiles')),
          reason: 'אישור מחיקה בהסרה אינו הסכמה למחוק נתונים של משתמשים אחרים',
        );
        expect(
          script,
          isNot(contains('procedure DeleteUserDataInAllProfiles(')),
        );
        expect(script, isNot(contains('function GetUserProfilesRoot(')));
      });
    }

    for (final name in _scripts) {
      test('$name: הסרה בהיקף אחד מנקה את ההיקף הנגדי', () {
        final body = _routine(
          _script(name),
          'procedure CurUninstallStepChanged(',
        );
        expect(body, contains('RemoveStaleScopeRegistration(HKCU, False)'));
        expect(body, contains('RemoveStaleScopeRegistration(HKLM64, True)'));
        expect(
          body,
          contains('if not IsCrossScopeUninstall() then'),
          reason: 'בלי החסם, שני ה-uninstallers מפעילים זה את זה',
        );
      });
    }
  });

  group('ניקוי התקנה מקבילה בהיקף השני (issue #886)', () {
    for (final name in _scripts) {
      test('$name: התקנת מנהל מנקה את HKCU ואת WOW6432Node אחרי ההתקנה', () {
        final script = _script(name);
        final cleanup = _routine(
          script,
          'procedure RemoveOtherScopeInstalls();',
        );

        expect(
          cleanup,
          contains('if PortableMode then'),
          reason: 'התקנה ניידת לא נוגעת ברישום כלל',
        );
        expect(cleanup, contains('RemoveStaleScopeRegistration(HKCU, False)'));
        expect(
          cleanup,
          contains('RemoveStaleScopeRegistration(HKLM32, False)'),
        );
        expect(
          cleanup,
          contains('RemoveStaleScopeRegistration(HKLM64, True)'),
          reason:
              'הכיוון ההפוך (issue #1020): התקנת משתמש מעל התקנת מנהל '
              'השאירה שתי רשומות מקבילות',
        );

        final postInstall = _routine(script, 'procedure CurStepChanged(');
        expect(
          postInstall,
          contains('RemoveOtherScopeInstalls()'),
          reason:
              'בלי הקריאה, ההתקנה בהיקף השני נשארת והקיצור הישן ממשיך '
              'להריץ בינארי ישן',
        );
      });

      test('$name: רשומה בנתיב אחר מוסרת דרך ה-uninstaller שלה, בשקט', () {
        final body = _routine(
          _script(name),
          'procedure RemoveStaleScopeRegistration(',
        );

        expect(
          body,
          contains("'/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CROSSSCOPE=1'"),
          reason:
              'בלי דגלי השקט ה-uninstaller שואל על מחיקת נתונים; '
              'ברירת המחדל השקטה שלו משמרת אותם. /CROSSSCOPE עוצר רקורסיה '
              'הדדית בין שני ה-uninstallers',
        );
        expect(
          body,
          contains("ShellExec('runas'"),
          reason:
              'ה-uninstaller של התקנת מנהל דורש הגבהה — Exec רגיל עליו '
              'נכשל כשרצים כמשתמש',
        );
        expect(body, contains('ewWaitUntilTerminated'));
        expect(
          body,
          contains('SameInstallDir(StaleDir'),
          reason:
              'הרצת uninstaller על רשומה שמצביעה על {app} הייתה מוחקת '
              'את הקבצים שזה עתה הותקנו',
        );
        expect(
          body,
          contains('RegDeleteKeyIncludingSubkeys(RootKey, UninstallRegKey)'),
          reason:
              'רשומה שמצביעה על {app} (או בלי uninstaller) נמחקת '
              'מהרישום בלבד',
        );
      });
    }
  });

  group('שיגור-מחדש עם מצב מפורש — בלי לשאול שוב', () {
    for (final name in _scripts) {
      test('$name: ShouldSkipPage מדלג על עמודי הפתיחה והמצב', () {
        // בלי הדילוג, בחירת "לכל המשתמשים" מציגה את אותן שאלות פעמיים —
        // פעם בריצה המקורית ופעם בריצה המשוגרת-מחדש.
        final body = _routine(
          _script(name),
          'function ShouldSkipPage(',
        );
        expect(body, contains("CmdLineParamExists('/ALLUSERS')"));
        expect(body, contains("CmdLineParamExists('/CURRENTUSER')"));
        expect(body, contains('FeaturesPage.ID'));
        expect(body, contains('ModePage.ID'));
      });
    }
  });

  group('איפוס הגדרות לא מוחק ספרים (issue #873)', () {
    // שם פרוצדורת המחיקה-עם-החרגות בכל סקריפט: הרגיל משמר גם books,
    // ה-FULL רק backups כי הספרייה מותקנת בו מחדש.
    const exceptProc = {
      _regular: 'DelTreeExceptBooksAndBackups',
      _full: 'DelTreeExceptBackups',
    };

    for (final name in _scripts) {
      test('$name: הנתיב העברי הישן נמחק עם החרגות ולא ב-DelTree מלא', () {
        final body = _routine(_script(name), 'procedure CurStepChanged(');
        final legacy = body.indexOf(r'{localappdata}\אוצריא');
        expect(legacy, greaterThanOrEqualTo(0));

        final end = legacy + 250 > body.length ? body.length : legacy + 250;
        final after = body.substring(legacy, end);
        expect(
          after,
          contains('${exceptProc[name]}(AppDataPath)'),
          reason: 'DelTree מלא על הנתיב העברי מחק ספריות וגיבויים שלמים',
        );
        expect(after, isNot(contains('DelTree(AppDataPath')));
        expect(
          body,
          isNot(contains(r'אוצריא\Data')),
          reason: 'קוד מת — תת-התיקייה נמחקת ממילא עם ההורה',
        );
      });

      test('$name: נתיב הספרייה המותאם נקרא לפני המחיקה ומוגן ממנה', () {
        final body = _routine(_script(name), 'procedure CurStepChanged(');
        final protect = body.indexOf(
          'ProtectedLibraryPath := RemoveBackslash(GetCustomLibraryPath())',
        );
        final firstDelete = body.indexOf('${exceptProc[name]}(');

        expect(protect, greaterThanOrEqualTo(0));
        expect(
          firstDelete,
          greaterThan(protect),
          reason: 'הנתיב נשמר ב-prefs — חייבים לקרוא אותו לפני שה-prefs נמחק',
        );

        final delProc = _routine(
          _script(name),
          'procedure ${exceptProc[name]}(',
        );
        expect(
          delProc,
          contains('Lowercase(ChildPath) <> Lowercase(ProtectedLibraryPath)'),
          reason: 'ספרייה מותאמת בתוך נתיב נתונים נמחקה יחד איתו',
        );
        expect(
          delProc,
          contains('Lowercase(Path) = Lowercase(ProtectedLibraryPath)'),
          reason: 'ספרייה שהיא הנתיב הנמחק עצמו חייבת יציאה מוקדמת',
        );
      });

      test('$name: בחירת המשימות לא נדבקת מהתקנה קודמת (issue #941)', () {
        expect(
          _section(_script(name), 'Setup'),
          contains('UsePreviousTasks=no'),
          reason:
              'ברירת המחדל של Inno שומרת את המשימות ברישום — "איפוס הגדרות" '
              'שסומן פעם רץ שוב בכל שדרוג שקט ומוחק את נתוני המשתמש',
        );
      });

      test('$name: איפוס בריצה שקטה רק עם /TASKS מפורש (issue #941)', () {
        final script = _script(name);
        final guard = _routine(script, 'function ShouldResetSettings(');

        expect(guard, contains('WizardSilent'));
        expect(guard, contains('{param:TASKS|}'));
        expect(guard, contains('{param:MERGETASKS|}'));

        final body = _routine(script, 'procedure CurStepChanged(');
        expect(body, contains('ShouldResetSettings()'));
        expect(
          body,
          isNot(contains("WizardIsTaskSelected('resetsettings')")),
          reason: 'מחיקת הנתונים חייבת לעבור דרך השער, לא ישירות דרך המשימה',
        );
      });

      test('$name: תיאור משימת האיפוס מוביל באזהרה ולא ממליץ עליה', () {
        final tasks = _section(_script(name), 'Tasks');
        final line = tasks
            .split('\n')
            .firstWhere((l) => l.contains('resetsettings'));

        expect(
          line,
          isNot(contains('מומלץ')),
          reason: 'הניסוח "מומלץ למעדכנים" גרם למשתמשים לסמן ולאבד נתונים',
        );
        expect(line.indexOf('אזהרה'), greaterThanOrEqualTo(0));
        expect(line.indexOf('אזהרה'), lessThan(line.indexOf('ימחק')));
      });
    }
  });

  group('פרמטריזציית ארכיטקטורה — Windows ARM64 (issue #1014)', () {
    test('$_regular: ברירת המחדל x64 ווריאנט arm64 נשלט מבחוץ', () {
      final script = _script(_regular);

      expect(
        script,
        contains('#ifndef AppArch'),
        reason: 'בלי ברירת מחדל, בניית x64 הקיימת נשברת',
      );
      expect(script, contains('#define AppArch "x64"'));
      expect(script, contains('ArchitecturesAllowed=arm64'));
      expect(script, contains('ArchitecturesAllowed=x64compatible'));
      expect(
        script,
        contains('OutputBaseFilename=otzaria-{#MyAppVersion}-windows_arm64'),
        reason:
            'מנגנון העדכון מזהה ARM לפי "arm64"; "_" ממוין אחרי המתקין הרגיל, '
            'כך שגרסאות ישנות שבוחרות את ה-exe הראשון לא מקבלות מתקין ARM',
      );
      expect(
        script,
        contains(r'..\build\windows\{#AppArch}\runner\Release\*'),
        reason: 'נתיב build קשיח ל-x64 היה אורז קבצי x64 במתקין ה-ARM',
      );
    });

    test('ה-workflow בונה arm64 על רץ ARM עם ISCC /DAppArch=arm64', () {
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(workflow, contains('build_windows_arm64:'));
      expect(
        workflow,
        contains('runs-on: windows-11-arm'),
        reason: 'ל-Flutter אין קרוס-קומפילציה של Windows — חובה מארח ARM',
      );
      expect(workflow, contains(r'/DAppArch=arm64 installer\otzaria.iss'));
      expect(
        workflow,
        contains(r"Test-Path 'build\windows\arm64\runner\Release\otzaria.exe'"),
        reason: 'בלי האימות, בנייה שנפלה לאמולציית x64 עוברת בשקט',
      );
    });

    test('vcredist נבחר לפי ארכיטקטורת היעד ב-CMake', () {
      final cmake = File('windows/CMakeLists.txt').readAsStringSync();

      expect(cmake, contains('FLUTTER_TARGET_PLATFORM'));
      expect(
        cmake,
        contains(r'installer/vcredist/${VCREDIST_ARCH}/'),
        reason: 'DLLs של x64 בבניית arm64 היו מאפילים על אלה של System32',
      );
    });
  });

  group('מתקין FULL ל-Windows ARM64', () {
    test('$_full: ברירת המחדל x64 ווריאנט arm64 נשלט מבחוץ', () {
      final script = _script(_full);

      expect(script, contains('#ifndef AppArch'));
      expect(script, contains('#define AppArch "x64"'));
      final setup = _section(script, 'Setup');
      expect(
        setup,
        contains(
          '#if AppArch == "arm64"\n'
          'ArchitecturesAllowed=arm64\n'
          'ArchitecturesInstallIn64BitMode=arm64\n'
          '; zstd ו-7za שמחלצים את הספרייה הם x64, ו-Windows 10 על ARM מאמלץ רק x86.\n'
          'MinVersion=10.0.22000\n'
          '#else\n'
          'ArchitecturesAllowed=x64compatible\n'
          'ArchitecturesInstallIn64BitMode=x64compatible\n'
          '#endif',
        ),
      );
    });

    test('$_full: שם הנכס הוא זה שהמניפסט ומסייע ההורדה מחפשים', () {
      final setup = _section(_script(_full), 'Setup');

      expect(
        setup,
        contains(
          '#ifdef IndexedSplitFull\n'
          'OutputBaseFilename=otzaria-{#MyAppVersion}-windows-full-indexed\n'
          '#elif AppArch == "arm64"\n',
        ),
        reason: 'המאונדקס קודם — השם שלו אינו תלוי בארכיטקטורה',
      );
      expect(
        setup,
        contains(
          'OutputBaseFilename=otzaria-{#MyAppVersion}-windows_arm64-full',
        ),
      );
      expect(
        setup,
        contains(
          '#else\nOutputBaseFilename=otzaria-{#MyAppVersion}-windows-full\n'
          '#endif',
        ),
        reason: 'שם הנכס של x64 אינו משתנה',
      );
      expect(
        RegExp(
          r'^otzaria-.+-windows_arm64-full\.exe$',
        ).hasMatch('otzaria-0.9.97-windows_arm64-full.exe'),
        isTrue,
      );
    });

    test('$_full: קבצי האפליקציה נלקחים מתיקיית ה-build של הארכיטקטורה', () {
      final files = _section(_script(_full), 'Files');

      expect(files, isNot(contains(r'..\build\windows\x64\')));
      expect(
        files,
        contains(r'Source: "..\build\windows\{#AppArch}\runner\Release\*.dll"'),
      );
      expect(
        files,
        contains(r'Source: "..\build\windows\{#AppArch}\runner\Release\*"; \'),
      );
    });

    test(
      '$_full: המאונדקס נבנה ל-x64 בלבד — שילוב עם arm64 נכשל בקומפילציה',
      () {
        expect(
          _script(_full),
          contains(
            '#if defined(IndexedSplitFull) && AppArch == "arm64"\n'
            '  #error ',
          ),
        );
      },
    );

    test('FULL ורגיל חולקים AppId — שדרוג בין הגרסאות כמו ב-x64', () {
      String appId(String name) => RegExp(
        r'^AppId=(.+)$',
        multiLine: true,
      ).firstMatch(_script(name))!.group(1)!;

      expect(appId(_full), appId(_regular));
    });

    test('ה-job של ARM64 בונה את ה-FULL אחרי כל הנכסים הרגילים, בלי לחסום', () {
      final step = _workflowStep('Build Inno Setup FULL installer (ARM64)');

      expect(step, contains('continue-on-error: true'));
      expect(step, contains('timeout-minutes:'));
      expect(step, contains(r'.\installer\download_full_installer_assets.ps1'));
      expect(
        step,
        contains(r'& "$env:ISCC" /DAppArch=arm64 installer\otzaria_full.iss'),
      );
      expect(
        step,
        isNot(contains('download_bundled_plugins')),
        reason: 'התוספים כבר ירדו בשלב של המתקין הרגיל — אין קריאה שנייה לחנות',
      );

      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final job = workflow.substring(
        workflow.indexOf('\n  build_windows_arm64:\n'),
        workflow.indexOf('\n  build_linux:\n'),
      );
      final full = job.indexOf(
        '- name: Build Inno Setup FULL installer (ARM64)',
      );
      expect(full, greaterThan(0));
      for (final earlier in const [
        '- name: Upload Windows ARM64 installer\n',
        '- name: Upload Windows ARM64 ZIP',
        '- name: Upload application file manifest (ARM64)',
      ]) {
        expect(
          job.indexOf(earlier),
          inInclusiveRange(0, full),
          reason: earlier,
        );
      }

      final upload = _workflowStep('Upload Windows ARM64 installer (full)');
      expect(upload, contains("if: steps.arm64_full.outcome == 'success'"));
      expect(upload, contains('continue-on-error: true'));
      expect(upload, contains('name: otzaria-windows-arm64-installer-full'));
      expect(
        upload,
        contains('path: installer/otzaria-*-windows_arm64-full.exe'),
      );
    });

    test('נכסי הספרייה ל-FULL יורדים מסקריפט אחד לשתי הארכיטקטורות', () {
      final x64 = _workflowStep('Download library assets for full installer');
      expect(x64, contains(r'.\installer\download_full_installer_assets.ps1'));

      final script = File(
        'installer/download_full_installer_assets.ps1',
      ).readAsStringSync();
      for (final asset in const [
        'download_library_db_asset.ps1',
        'otzar-HB_catalog.db.zst',
        'talmud_bavli_latest.tar.zst',
        'lexical.db.zst',
        r'installer\zstd.exe',
        r'installer\7za.exe',
      ]) {
        expect(script, contains(asset));
      }
    });
  });

  group('סימון גרסת התלמוד בחבילות FULL', () {
    // בלי הסימון האפליקציה מורידה מחדש ~440MB בבדיקת העדכון הראשונה.
    final versionFile = DatabaseConstants.talmudBavliVersionFileName;

    test('$_full: החילוץ כותב את הסימון מ-sha256 של הארכיון', () {
      final body = _routine(
        _script(_full),
        'procedure ExtractBundledTarArchive(',
      );

      expect(body, contains("TargetDir + '\\$versionFile'"));
      expect(body, contains('Lowercase(GetSHA256OfFile(ArchivePath))'));
      expect(
        body.indexOf('SaveStringToFile'),
        lessThan(body.indexOf('DeleteFile(ArchivePath)')),
        reason: 'ה-sha256 מחושב על הארכיון — לפני מחיקתו',
      );
    });

    for (final entry in const {
      'Create Linux FULL portable bundle': 'sha256sum',
      'Create macOS FULL portable bundle': 'shasum -a 256',
    }.entries) {
      test('${entry.key}: הסימון נכתב לתיקיית התלמוד', () {
        final step = _workflowStep(entry.key);
        final talmudDir =
            '\$BUNDLE_ROOT/אוצריא/${DatabaseConstants.talmudBavliFolderName}';

        expect(step, contains(entry.value));
        expect(step, contains('$talmudDir/$versionFile'));
      });
    }
  });

  group('סימון גרסת מילון החיפוש בחבילות FULL', () {
    // בלי הסימון האפליקציה מורידה מחדש ~57MB בבדיקת העדכון הראשונה (issue #665).
    test('$_full: אחרי חילוץ lexical.db נכתב סימון מ-sha256 של הקובץ', () {
      final body = _routine(
        _script(_full),
        'procedure ExtractEmbeddedLibraryArchives();',
      );

      expect(body, contains("'\\lexical.db.version'"));
      expect(
        body,
        contains(
          "Lowercase(GetSHA256OfFile(StagingBooks + '\\lexical.db'))",
        ),
        reason: 'הנכס ב-release אינו דחוס — ה-digest מחושב על הקובץ המחולץ',
      );
    });

    for (final entry in const {
      'Create Linux FULL portable bundle': 'sha256sum',
      'Create macOS FULL portable bundle': 'shasum -a 256',
    }.entries) {
      test('${entry.key}: הסימון נכתב ליד lexical.db', () {
        final step = _workflowStep(entry.key);

        expect(step, contains(entry.value));
        expect(step, contains(r'$BUNDLE_ROOT/אוצריא/lexical.db.version'));
      });
    }
  });

  group('תוספים מצורפים — שני סקריפטי ההורדה וכל החבילות מיושרים', () {
    // הרשימה נקראת ע"י שני סקריפטים (pwsh ל-Windows, bash ללינוקס/מק) —
    // סטייה ביניהם מפילה תוסף בשקט רק בחלק מהפלטפורמות.
    const scripts = [
      'download_bundled_plugins.ps1',
      'download_bundled_plugins.sh',
    ];

    for (final name in scripts) {
      test('$name: אותה רשימה, אותו endpoint, אותה תיקיית פלט', () {
        final script = File(
          'installer/$name',
        ).readAsStringSync().replaceAll('\r\n', '\n');

        expect(script, contains('bundled_plugin_ids.dart'));
        expect(script, contains('https://otzaria.org'));
        expect(script, contains('/download?appVersion='));
        expect(script, contains(AppPaths.bundledPluginsFolderName));
        expect(
          RegExp(r"\(\[\^'\]\+\)").allMatches(script).length,
          2,
          reason: 'תבנית פענוח הזוגות חייבת ללכוד מזהה-חנות ומזהה-מניפסט',
        );
        expect(
          script,
          contains('manifest.json'),
          reason: 'בלי אימות מזהה המניפסט, ארכיון שגוי נכשל בשקט אצל המשתמש',
        );
        expect(
          script,
          contains('@'),
          reason:
              'שני הסקריפטים חייבים לפרק את סיומת @פלטפורמות מהערך — '
              'אחרת הסיומת תיכנס לשם הקובץ וה-seeder ידחה את הארכיון',
        );
      });
    }

    test('כל קריאות ה-workflow מעבירות את פלטפורמת הבנייה לסינון', () {
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        RegExp(
          r'download_bundled_plugins\.ps1 -Platform windows',
        ).allMatches(workflow).length,
        3,
        reason: 'שלושת מתקיני Windows (רגיל, ARM64, indexed) חייבים סינון',
      );
      expect(workflow, contains('download_bundled_plugins.sh linux'));
      expect(workflow, contains('download_bundled_plugins.sh macos'));
      expect(workflow, contains('download_bundled_plugins.sh android'));
      expect(
        workflow,
        isNot(
          matches(
            RegExp(r'download_bundled_plugins\.(sh|ps1)\s*$', multiLine: true),
          ),
        ),
        reason: 'קריאה בלי פלטפורמה עוקפת את הסינון ואורזת תוסף שסונן',
      );
    });

    test('אנדרואיד: הארכיונים נכנסים ל-assets המוצהרים ב-pubspec', () {
      const assetDir = BundledPluginSeedService.bundledPluginsAssetDir;

      expect(
        _workflowStep('Download bundled plugins into Android assets'),
        contains('$assetDir/'),
      );
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- $assetDir/'),
        reason: 'בלי ההצהרה ב-pubspec הארכיונים לא נארזים ב-APK',
      );
      expect(
        Directory(assetDir).existsSync(),
        isTrue,
        reason: 'תיקיית asset מוצהרת שאינה קיימת מפילה כל build מקומי',
      );
    });

    test('לינוקס: ההורדה רצה וכל ארבע החבילות מקבלות את התיקייה', () {
      expect(
        _workflowStep('Download bundled plugins for Linux packages'),
        contains('download_bundled_plugins.sh'),
      );
      for (final step in const [
        'Build and Patch Linux DEB package',
        'Build and Patch Linux RPM package',
        'Bundle WPE runtime into main bundle (raw + FULL)',
      ]) {
        expect(
          _workflowStep(step),
          contains('installer/bundled_plugins'),
          reason: '$step אינו אורז את התוספים — החבילה תגיע בלעדיהם',
        );
      }
    });

    test('מק: ההורדה רצה וההזרקה ל-.app קודמת ליצירת ה-DMG', () {
      expect(
        _workflowStep('Download bundled plugins for macOS bundles'),
        contains('download_bundled_plugins.sh'),
      );
      expect(
        _workflowStep('Bundle plugins into the app bundle'),
        contains(
          'Contents/Resources/${AppPaths.bundledPluginsFolderName}',
        ),
        reason:
            'Contents/MacOS שמורה לקוד — קובצי נתונים בה פוסלים את החתימה; '
            'הנתיב חייב להתאים ל-AppPaths.getBundledPluginsPath',
      );

      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        workflow.indexOf('- name: Bundle plugins into the app bundle'),
        lessThan(workflow.indexOf('- name: Create DMG installer')),
        reason: 'הזרקה אחרי ה-DMG משאירה את המתקין של מק בלי התוספים',
      );
    });

    test('מק: ה-.app נחתם מחדש ונבדק אחרי ההזרקה ולפני האריזה', () {
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final resign = workflow.indexOf(
        '- name: Re-sign and verify the app bundle',
      );

      expect(
        resign,
        greaterThan(
          workflow.indexOf('- name: Bundle plugins into the app bundle'),
        ),
        reason: 'חתימה לפני ההזרקה מתבטלת שוב ברגע שהקבצים נכנסים',
      );
      for (final step in const [
        '- name: Create DMG installer',
        '- name: Create macOS update zip',
        '- name: Create macOS FULL portable bundle',
      ]) {
        expect(
          resign,
          lessThan(workflow.indexOf(step)),
          reason: '$step אורז bundle שחתימתו שבורה — Gatekeeper יפסול אותו',
        );
      }

      final step = _workflowStep('Re-sign and verify the app bundle');
      expect(step, contains('codesign --force --sign -'));
      expect(
        step,
        contains('--entitlements macos/Runner/Release.entitlements'),
        reason: 'חתימה מחדש בלי ההרשאות מוחקת אותן מהבינארי',
      );
      expect(
        step,
        contains('codesign --verify --deep --strict'),
        reason: 'בלי שער האימות bundle פגום עובר בשקט אל המשתמשים',
      );

      expect(
        File('macos/Runner/Release.entitlements').existsSync(),
        isTrue,
        reason: 'הנתיב מקודד בפקודת החתימה — העברת הקובץ תפיל את ה-CI',
      );

      // ‏'Contents/Resources' מקודד כאן ובנפרד ב-app_paths.dart; בלי הקישור
      // הזה שינוי בצד אחד משאיר את הטסטים ירוקים והאפליקציה בלי תוספים.
      expect(
        File('lib/core/app_paths.dart').readAsStringSync(),
        contains("p.join(exeDir, '..', 'Resources', bundledPluginsFolderName)"),
        reason: 'קוד הריצה במק חייב לחפש באותו נתיב שה-workflow מעתיק אליו',
      );
    });
  });

  group('התקנה ניידת — שאלה לפני שכפול ספרייה קיימת (issue #861)', () {
    test('$_full: השאלה נשאלת בלחיצת "התקן" ומזהה ספרייה קיימת בלבד', () {
      final script = _script(_full);
      final ask = _routine(script, 'procedure AskPortableLibraryChoice(');

      expect(ask, contains('if not PortableMode then'));
      expect(ask, contains('FindExistingLibraryPath()'));
      expect(
        ask,
        contains('MB_YESNO) = IDNO'),
        reason: 'ברירת המחדל (Yes) חייבת להישאר חילוץ — דילוג רק בבחירה מפורשת',
      );

      final next = _routine(script, 'function NextButtonClick(');
      expect(
        next,
        contains('AskPortableLibraryChoice()'),
        reason: 'השאלה חייבת לרוץ בעמוד Ready, לפני תחילת ההתקנה',
      );
    });

    test('$_full: הזיהוי מכסה את ה-prefs ואת שני נתיבי ברירת המחדל', () {
      final find = _routine(
        _script(_full),
        'function FindExistingLibraryPath(',
      );

      expect(find, contains('GetCustomLibraryPath()'));
      expect(find, contains(r"'{userappdata}\otzaria\books'"));
      expect(find, contains(r"'{commonappdata}\otzaria\books'"));
      expect(
        RegExp('IsOtzariaBooksFolder').allMatches(find).length,
        3,
        reason: 'כל מועמד חייב אימות תוכן לפני שהוא נחשב ספרייה קיימת',
      );
    });

    test('$_full: הדילוג כותב את ה-marker ויוצא לפני החילוץ', () {
      final body = _routine(_script(_full), 'procedure CurStepChanged(');
      final skipAt = body.indexOf('PortableMode and PortableSkipLibrary');
      final extractAt = body.indexOf('zstd.exe');

      expect(skipAt, greaterThan(0));
      expect(
        skipAt,
        lessThan(extractAt),
        reason: 'בלוק הדילוג חייב לקדום לחילוץ — אחרת העותק הכפול כבר נוצר',
      );

      final skipBlock = body.substring(skipAt, extractAt);
      expect(
        skipBlock,
        contains(r"'{app}\portable.marker'"),
        reason: 'גם בדילוג ההתקנה חייבת להישאר ניידת',
      );
      expect(skipBlock, contains('exit;'));
    });

    test('שירות הספרייה היתומה מזהה התקנת מנהל לפי ה-AppId של המתקינים', () {
      final service = File(
        'lib/settings/services/orphan_library_service.dart',
      ).readAsStringSync();
      final guid = RegExp(
        r'\{[0-9A-F-]{36}\}_is1',
      ).firstMatch(service)?.group(0);

      expect(guid, isNotNull, reason: 'מפתח ההסרה נעלם מהשירות');
      final appId = guid!.substring(0, guid.length - 4);
      for (final name in _scripts) {
        expect(
          _script(name),
          contains('AppId={$appId'),
          reason:
              'שינוי AppId במתקין ישבור את זיהוי התקנת המנהל '
              'ב-OrphanLibraryService — יש לעדכן את שניהם יחד',
        );
      }
    });

    test('$_full: בדילוג לא מורידים את חבילת הספרייה המאונדקסת', () {
      final next = _routine(_script(_full), 'function NextButtonClick(');
      expect(
        next,
        contains(
          'if not PortableSkipLibrary then\n'
          '      Result := PrepareIndexedLibrary();',
        ),
      );
    });
  });

  group('מסייע ההורדה — אינו מתקין', () {
    test('$_assistant: אין התקנה לתיקיית תוכנה, קיצורים או רישום', () {
      final script = _script(_assistant);

      expect(script, contains('CreateAppDir=no'));
      expect(
        script,
        isNot(
          matches(
            RegExp(
              r'^\[(Files|Icons|Registry|Dirs|INI)\]\s*$',
              multiLine: true,
            ),
          ),
        ),
        reason: 'הכלי אינו מתקין דבר — כל מקטע שמתקין הופך אותו למתקין',
      );
      for (final call in const [
        'RegWriteStringValue',
        'RegWriteDWordValue',
        'RegWriteBinaryValue',
      ]) {
        expect(script, isNot(contains(call)), reason: 'כתיבה לרישום: $call');
      }
    });

    test('$_assistant: אין מסיר ואין רשומה ב"הוספה או הסרה"', () {
      final script = _script(_assistant);

      expect(script, contains('Uninstallable=no'));
      expect(script, contains('CreateUninstallRegKey=no'));
      expect(
        script,
        isNot(matches(RegExp(r'^\[Uninstall[A-Za-z]*\]\s*$', multiLine: true))),
      );
      expect(script, isNot(contains('CurUninstallStepChanged')));
    });

    test('$_assistant: שם הפלט מדויק ואינו מבלבל את בוחרי הנכסים', () {
      final script = _script(_assistant);
      final match = RegExp(
        r'^OutputBaseFilename=(.+)$',
        multiLine: true,
      ).firstMatch(script);

      expect(match, isNotNull);
      final name = _squeeze(match!.group(1)!);
      expect(name, 'Otzaria-Download-Assistant-windows');
      // GitHub מסנן שם נכס ל-[A-Za-z0-9._-] ומוחק תווים עבריים בלי תחליף.
      expect(name, matches(RegExp(r'^[A-Za-z0-9._-]+$')));
      expect(name.toLowerCase(), isNot(contains('full')));
      expect(
        name.toLowerCase(),
        contains('download-assistant'),
        reason: 'עליו נשענת ההחרגה של האשף מבחירת נכס העדכון',
      );
      expect(
        File('lib/update/my_update_widget.dart').readAsStringSync(),
        contains("name.contains('download-assistant')"),
        reason: 'הפרדיקט שמחריג את האשף מבחירת נכס העדכון נעלם',
      );
    });

    test('$_assistant: מאפייני הקובץ בעברית — שם הקובץ נשאר ASCII', () {
      final script = _script(_assistant);
      final hebrew = RegExp(r'[֐-׿]');

      for (final key in const [
        'VersionInfoProductName',
        'VersionInfoDescription',
      ]) {
        final match = RegExp(
          '^$key=(.+)\$',
          multiLine: true,
        ).firstMatch(script);
        expect(match, isNotNull, reason: '$key חסר');
        expect(
          match!.group(1)!,
          matches(hebrew),
          reason: '$key הוא הזיהוי העברי היחיד שאפשרי — שם הנכס חייב ASCII',
        );
      }
      expect(
        RegExp(
          r'^VersionInfoDescription=(.+)$',
          multiLine: true,
        ).firstMatch(script)!.group(1),
        contains('אינו מתקין'),
      );
      expect(
        script,
        contains('VersionInfoProductTextVersion={#TagVersionPart}'),
        reason: 'הגרסה המוצגת נגזרת מהתג המוטבע ואינה מומצאת',
      );
    });

    test('$_assistant: ניסוחי ההתקנה של Inno נדרסים', () {
      final messages = _section(_script(_assistant), 'Messages');

      for (final id in const [
        'SetupLdrStartupMessage',
        'ButtonInstall',
        'WizardReady',
        'ReadyLabel1',
        'ReadyLabel2a',
        'ReadyLabel2b',
        'WizardPreparing',
        'PreparingDesc',
        'WizardInstalling',
        'InstallingLabel',
        'StatusCreateDirs',
        'StatusExtractFiles',
        'StatusSavingUninstall',
        'StatusRunProgram',
        'FinishedLabel',
        'FinishedLabelNoIcons',
        'ClickFinish',
        'SetupAborted',
      ]) {
        expect(
          messages,
          matches(RegExp('^$id=', multiLine: true)),
          reason: 'ברירת המחדל של $id מנוסחת כמתקין',
        );
      }
      // "התקנה" מותר כאובייקט שמכינים; אסור שהכלי יתאר את עצמו כמתקין.
      for (final claim in const ['תוכנת ההתקנה', 'מתקין את', 'על מחשבך']) {
        expect(messages, isNot(contains(claim)), reason: claim);
      }
    });

    test('$_assistant: ברירת המחדל לשמירה היא תיקיית המסייע עצמו', () {
      final script = _script(_assistant);
      final assistantDir = _routine(script, 'function AssistantDir()');
      final wizard = _routine(script, 'procedure InitializeWizard()');

      expect(assistantDir, contains(r"ExpandConstant('{srcexe}')"));
      expect(assistantDir, contains('ExtractFileDir'));
      expect(
        wizard,
        contains('DefaultBase := AssistantDir();'),
        reason: 'התוצאה נשמרת ליד הקובץ שהופעל, לא בתיקייה קבועה',
      );
      expect(
        wizard,
        contains('FolderPage.Values[0] := DefaultBase;'),
        reason: 'ברירת המחדל היא העדפה — המשתמש עדיין בוחר',
      );
    });

    test('$_assistant: הכתיבוּת נבדקת בכתיבה, ויש נסיגה מוסברת', () {
      final script = _script(_assistant);
      final probe = _routine(script, 'function DirIsWritable(');
      final wizard = _routine(script, 'procedure InitializeWizard()');
      final next = _routine(script, 'function NextButtonClick(');

      expect(
        probe,
        contains('SaveStringToFile('),
        reason: 'נתיב אינו מעיד על כתיבוּת — חובה לנסות לכתוב',
      );
      expect(probe, contains('DeleteFile(Probe)'));
      expect(wizard, contains('if not DirIsWritable(DefaultBase) then'));
      expect(wizard, contains('DefaultBase := FallbackOutputBase();'));
      expect(
        wizard,
        contains('FolderNote'),
        reason: 'הנסיגה חייבת להיאמר למשתמש בעברית פשוטה',
      );
      expect(
        next,
        contains('if DirIsWritable(FolderPage.Values[0]) then'),
        reason: 'גם תיקייה שנבחרה ידנית נבדקת בכתיבה',
      );
      expect(next, contains('FolderPage.Values[0] := FallbackOutputBase();'));
    });

    test('$_assistant: מספר הקבצים שנוצרו קובע פריסה וניסוח', () {
      final script = _script(_assistant);
      final planned = _routine(script, 'function PlannedOutputNames()');
      final count = _routine(script, 'function ProducedFileCount()');
      final outputDir = _routine(script, 'function OutputDir()');
      final prepare = _routine(script, 'function PrepareOutput()');

      expect(planned, contains("AssetKind[A] = 'split'"));
      expect(planned, contains('ShouldAssembleSingleFile(A)'));
      expect(planned, contains('AssetPartCount[A]'));
      expect(count, contains('GetArrayLength(PlannedOutputNames())'));
      expect(
        outputDir,
        contains('ProducedFileCount() > 1'),
        reason: 'קובץ בודד ישירות בתיקייה; כמה קבצים בתת-תיקייה',
      );
      expect(outputDir, contains('OutputSubFolderName()'));
      // outputSubfolderName בחוזה: הפלטפורמה בשם, כדי ששני יעדים לא יתערבבו.
      expect(
        _routine(script, 'function OutputSubFolderName()'),
        contains("'אוצריא להתקנה ל-' + PlatformDisplayName(TargetPlatform)"),
      );

      expect(
        prepare,
        contains('else if Produced = 1 then'),
        reason: 'הניסוח נגזר ממה שנוצר בפועל, לא מהרכיב שנבחר',
      );
      final single = prepare.substring(prepare.indexOf('else if Produced = 1'));
      final multi = single.substring(single.indexOf("'ההתקנה מוכנה בתיקייה:'"));
      expect(single, contains("'הקובץ מוכן:' + #13#10 + SingleName"));
      expect(
        single.substring(0, single.indexOf("'ההתקנה מוכנה בתיקייה:'")),
        isNot(contains('תיקייה הזאת')),
      );
      expect(multi, contains('העתק את כל התיקייה הזאת'));
      expect(multi, contains('חייבים להישאר יחד'));
      for (final jargon in const ['מניפסט', 'sha', 'hash', 'נכס']) {
        expect(single, isNot(contains(jargon)), reason: jargon);
      }
    });

    test('$_assistant: תיבת "הצג" מסומנת מראש ומסמנת את מה שנוצר', () {
      final script = _script(_assistant);
      final page = _routine(script, 'procedure CurPageChanged(');
      final deinit = _routine(script, 'procedure DeinitializeSetup()');

      expect(page, contains('RevealCheck.Checked := True;'));
      expect(page, contains("RevealCheck.Caption := 'הצג את הקובץ שהוכן'"));
      expect(page, contains("RevealCheck.Caption := 'הצג את התיקייה שהוכנה'"));
      expect(
        page,
        contains('if RevealIsFile then'),
        reason: 'התווית נגזרת ממה שנוצר, כמו ניסוח עמוד הסיום',
      );

      expect(deinit, contains('ExecAsOriginalUser('));
      expect(deinit, contains(r"ExpandConstant('{win}\explorer.exe')"));
      expect(
        deinit,
        contains("'/select,\"' + RevealPath + '\"'"),
        reason: 'בלי /select נפתחת תיקייה כלשהי, ובלי מרכאות נשבר נתיב עם רווח',
      );
      expect(
        deinit,
        isNot(contains('MsgBox')),
        reason: 'פתיחת הסייר היא נוחות — כישלון שלה אינו מפיל ואינו מבהיל',
      );
      expect(deinit, contains('Log('));
    });

    test('$_assistant: תמונת האשף הקטנה שטוחה על רקע לבן', () {
      final match = RegExp(
        r'^WizardSmallImageFile=(.+)$',
        multiLine: true,
      ).firstMatch(_script(_assistant));
      expect(match, isNotNull);

      final files = _squeeze(match!.group(1)!).split(',');
      for (final name in files) {
        expect(
          name,
          contains('_white'),
          reason: 'תמונה משותפת עם המתקינים נשמרה מאייקון שקוף — רקע שחור',
        );
        final bytes = File('installer/$name').readAsBytesSync();
        // BMP נשמר מלמטה למעלה: הפיקסל הראשון בנתונים הוא הפינה התחתונה-שמאלית.
        final offset = bytes.buffer.asByteData().getUint32(10, Endian.little);
        expect(bytes.sublist(offset, offset + 3), [255, 255, 255]);
      }
    });

    test('$_assistant: אין רשימת שמות נכסים קשיחה', () {
      final script = _script(_assistant);

      // הרכיבים, הגדלים וה-hash מגיעים מהמניפסט; שם נכס קשיח היה מקבע את
      // הכלי לגרסה אחת ומחייב שינוי קוד בכל רכיב חדש. היוצא היחיד הוא שם
      // המניפסט עצמו, שה-workflow כותב.
      const manifestConst =
          "ReleaseManifestAsset = 'otzaria-release-manifest.json';";
      expect(script, contains(manifestConst));
      expect(
        File('.github/workflows/build-and-announce.yml').readAsStringSync(),
        contains('--out release-files/otzaria-release-manifest.json'),
      );
      expect(
        script.replaceAll(manifestConst, ''),
        isNot(contains('otzaria-')),
      );
      // explorer.exe הוא תוכנית מערכת שפותחת את התוצאה, לא נכס של release.
      final literals = script.replaceAll(
        r"ExpandConstant('{win}\explorer.exe')",
        '',
      );
      expect(
        literals,
        isNot(matches(RegExp(r"'[^']+\.(exe|zip|tar\.zst)'"))),
        reason: 'שם קובץ נכס ספציפי בתוך הסקריפט',
      );
    });

    test('$_assistant: כל כתובת היא github.com בארגון Otzaria', () {
      final script = _script(_assistant);
      final urls = RegExp(
        r"'(https?://[^']*)'",
      ).allMatches(script).map((m) => m.group(1)!).toList();

      expect(urls, isNotEmpty);
      for (final url in urls) {
        // 'https://github.com/' לבדה היא תחילית הבנייה ב-AssetUrl, שהמאגר
        // שמצורף אליה כבר אומת.
        expect(
          url == 'https://github.com/' ||
              url.startsWith('https://github.com/Otzaria/') ||
              url.startsWith('https://api.github.com/repos/Otzaria/'),
          isTrue,
          reason: 'כתובת שאינה בארגון Otzaria ב-github.com: $url',
        );
      }
      expect(script, isNot(contains('http://')));

      final builder = _routine(script, 'function AssetUrl(');
      expect(
        builder.indexOf('IsOtzariaRepository'),
        lessThan(builder.indexOf("'https://github.com/'")),
        reason: 'הכתובת נבנית רק אחרי שהמאגר אומת כשייך לארגון',
      );
    });

    test('$_assistant: להורדה תמיד מועבר hash מהמניפסט', () {
      final script = _script(_assistant);
      final adds = RegExp(
        r'DownloadPage\.Add\(([^;]*)\);',
      ).allMatches(script).map((m) => m.group(1)!).toList();

      expect(adds, hasLength(1), reason: 'יותר ממסלול הורדה אחד');
      expect(
        adds.single,
        contains('QueueSha[I]'),
        reason: 'Add בלי hash מוריד קובץ שאי אפשר לאמת',
      );
      expect(
        script,
        isNot(matches(RegExp(r"DownloadPage\.Add\([^;]*,\s*''\s*\)"))),
      );
      // המניפסט עצמו יורד בלי hash (הוא מקור האמת), ולכן הוא לא עובר
      // דרך עמוד ההורדה אלא דרך DownloadTemporaryFile.
      expect(
        RegExp('DownloadTemporaryFile').allMatches(script).length,
        2,
        reason: 'רק רשימת ה-release והמניפסט יורדים בלי hash',
      );
    });

    test('$_assistant: קובץ זמני מקבל שם סופי רק אחרי אימות, והחותם אחריו', () {
      final promote = _routine(_script(_assistant), 'function PromoteToCache(');

      final sizeCheck = promote.indexOf('Actual = Size');
      final rename = promote.indexOf('RenameFile(Staged, CachePath(Name))');
      final marker = promote.indexOf('WriteMarker(Name, Sha)');
      expect(sizeCheck, greaterThanOrEqualTo(0));
      expect(
        rename,
        greaterThan(sizeCheck),
        reason: 'קובץ חלקי שקיבל שם סופי ייחשב בהרצה הבאה כקובץ שהורד',
      );
      expect(marker, greaterThan(rename));
      expect(
        promote.indexOf('DeleteFile(MarkerPath(Name))'),
        lessThan(rename),
        reason: 'חותם ישן לצד קובץ חדש היה מאשר תוכן שלא נבדק',
      );
      expect(
        promote,
        contains("CachePath(Name) + '.download'"),
        reason: 'ההורדה חייבת לנחות תחת שם זמני',
      );
      // עמוד ההורדה כבר אימת את ה-sha256 — hash שני כאן עלה ~17 שניות ל-2GB.
      expect(promote, isNot(contains('HashFile(')));
      expect(promote, isNot(contains('GetSHA256OfFile(')));

      final assemble = _routine(_script(_assistant), 'function AssembleAsset(');
      final sizeVerify = assemble.indexOf('Actual <> AssetSize[AssetIndex]');
      final promoteFinal = assemble.indexOf('RenameFile(TmpPath, FinalPath)');
      expect(sizeVerify, greaterThanOrEqualTo(0));
      expect(promoteFinal, greaterThan(sizeVerify));
      expect(
        assemble.indexOf('WriteMarker(AssetName[AssetIndex]'),
        greaterThan(promoteFinal),
      );
      final hashVerify = assemble.indexOf('HashFile(TmpPath)');
      expect(hashVerify, greaterThan(sizeVerify));
      expect(promoteFinal, greaterThan(hashVerify));
      expect(
        assemble.indexOf('DeleteFile(TmpPath);', hashVerify),
        lessThan(promoteFinal),
      );
      expect(
        _routine(_script(_assistant), 'function AppendFileTo('),
        contains('(Copied = Expected)'),
      );
    });

    test('$_assistant: hash מחושב במקום אחד בלבד, ונרשם ללוג', () {
      final script = _script(_assistant);
      expect(
        RegExp(r'GetSHA256OfFile\(').allMatches(script).length,
        1,
        reason: 'כל hash עובר דרך HashFile כדי שהלוג יראה כמה פעמים חושב',
      );
      final hash = _routine(script, 'function HashFile(');
      expect(hash, contains('GetSHA256OfFile(Path)'));
      expect(hash, contains('Log('));
    });

    test('$_assistant: קובץ שכבר במטמון נסמך על החותם ולא יורד שוב', () {
      final script = _script(_assistant);
      final matches = _routine(script, 'function FileMatchesMarker(');
      final cached = _routine(script, 'function CachedFileIsGood(');

      expect(cached, contains('FileMatchesMarker(CachePath(Name)'));
      expect(matches, contains('FileSize64('));
      expect(matches, contains('ReadMarkerHex(Name)'));
      expect(
        matches,
        contains('(FileStamp <= MarkerStamp)'),
        reason: 'קובץ שהשתנה אחרי שנכתב החותם אינו מאומת עוד',
      );
      final hash = matches.indexOf('HashFile(Path)');
      expect(hash, greaterThan(matches.indexOf('ReadMarkerHex(Name)')));
      expect(
        matches.indexOf('WriteMarker(Name, Sha)'),
        greaterThan(hash),
        reason: 'מטמון ישן בלי חותם עובר hash פעם אחת ומקבל חותם',
      );
      expect(
        _routine(script, 'procedure WriteMarker('),
        contains("Lowercase(Sha) + '  ' + Name + #10"),
        reason: 'פורמט sha256sum, כמו במסייעי macOS ו-Linux',
      );
      expect(
        _routine(script, 'function AssembledIsReady('),
        contains('FileMatchesMarker('),
      );

      final queue = _routine(script, 'function BuildQueue(');
      expect(
        RegExp('CachedFileIsGood').allMatches(queue).length,
        2,
        reason: 'גם חלקים וגם נכס יחיד חייבים לדלג כשהם כבר מאומתים',
      );
      expect(queue, contains('Continue;'));
    });

    test('$_assistant: מעל 4 ג׳יגה לא מייצרים exe יחיד — כלל מחושב', () {
      final script = _script(_assistant);

      expect(
        script,
        contains('MaxSingleOutputFileSize = 4294967296'),
        reason: 'Windows מסרב להריץ exe בגודל 4 GiB ומעלה, ו-FAT32 אינו מחזיק',
      );
      final rule = _routine(script, 'function ShouldAssembleSingleFile(');
      expect(
        rule,
        contains('AssetSize[AssetIndex] >= MaxSingleOutputFileSize'),
      );
      // shouldAssembleSplitAsset: ל-Windows רק exe; לכל יעד אחר כל נכס.
      expect(rule, contains("if TargetPlatform = 'windows' then"));
      expect(rule, contains('IsExecutableName(AssetName[AssetIndex])'));
      expect(
        rule,
        isNot(contains('CompId')),
        reason: 'הכלל נגזר מהנכס עצמו, לא ממזהה רכיב ספציפי',
      );
    });

    test('$_assistant: מטמון→יעד בקישור קשיח, ובכישלון העתקה', () {
      final script = _script(_assistant);
      expect(
        script,
        contains("external 'CreateHardLinkW@kernel32.dll stdcall'"),
      );
      final copy = _routine(script, 'function CopyToOutput(');
      final link = copy.indexOf('CreateHardLink(Dest, CachePath(Name), 0)');
      expect(link, greaterThanOrEqualTo(0));
      expect(copy.indexOf('CopyFile(CachePath(Name), Dest'), greaterThan(link));
    });

    test('$_assistant: פס ההורדה מציג מהירות וזמן, ואינו קופא בלי הסבר', () {
      final script = _script(_assistant);
      final progress = _routine(script, 'function OnDownloadProgress(');
      expect(script, contains("external 'GetTickCount@kernel32.dll stdcall'"));
      expect(script, contains('SpeedWindowMs = 5000'));
      expect(progress, contains('AddSpeedSample(Done)'));
      expect(progress, contains('HumanRate(Speed)'));
      expect(progress, contains('HumanDuration('));
      final atMax = progress.indexOf('(Progress >= ProgressMax)');
      expect(atMax, greaterThanOrEqualTo(0));
      expect(
        progress.indexOf("'בודק את הקובץ שירד'"),
        greaterThan(atMax),
        reason: 'Inno מחשב hash אחרי הבית האחרון בלי דיווח — הפס עומד על 100%',
      );
      expect(
        _routine(script, 'function AppendFileTo('),
        contains('WorkPage.SetProgress('),
        reason: 'ההרכבה מדווחת התקדמות בבתים',
      );
    });

    test('$_assistant: עמודי היעד — פלטפורמה, ארכיטקטורה ופורמט', () {
      final script = _script(_assistant);
      final skip = _routine(script, 'function ShouldSkipPage(');
      final target = _routine(script, 'procedure UpdateTarget()');
      final wizard = _routine(script, 'procedure InitializeWizard()');

      // עמוד עם אפשרות אחת אינו מוצג; "במחשב הזה" מדלג על שלושתם.
      for (final list in const ['PlatformList', 'ArchList', 'FormatList']) {
        expect(
          skip,
          contains('IsThisComputerMode() or (GetArrayLength($list) <= 1)'),
        );
      }
      expect(wizard, contains("DefaultIndex(PlatformList, 'windows')"));
      expect(
        wizard,
        contains('PlatformPage := CreateInputOptionPage(ModePage.ID'),
      );
      expect(target, contains("TargetPlatform := 'windows';"));
      expect(target, contains('TargetArchitecture := RunningArchitecture();'));
      expect(target, contains("DefaultIndex(ArchList, 'x64')"));
      expect(target, contains("DefaultIndex(FormatList, 'deb')"));
      expect(
        _routine(script, 'function RunningArchitecture()'),
        contains('if IsArm64 then'),
      );

      final formats = _routine(script, 'function FormatDisplayName(');
      for (final label in const [
        'Ubuntu, Debian, Mint והפצות דומות (DEB)',
        'Fedora, openSUSE והפצות דומות (RPM)',
        'הפצה אחרת — ללא התקנה',
      ]) {
        expect(formats, contains("'$label'"));
      }
      expect(
        _routine(script, 'function PrepareOutput()'),
        contains(
          'if IsThisComputerMode() and IsExecutableName(AssetName[A]) and',
        ),
        reason: 'מפעילים מתקין רק כשמתקינים במחשב הזה',
      );
    });

    test('$_assistant: הרכבה חלקית ממשיכה רק מ-.tmp של אותו sha', () {
      // שם הנכס חוזר בין בניות של אותה גרסה, וגודל החלק קבוע — גודל לבדו
      // היה מקבל .tmp של בנייה אחרת ומייצר קובץ כלאיים עם חותם חדש.
      final script = _script(_assistant);
      final belongs = _routine(script, 'function AssemblyTmpBelongs(');
      expect(belongs, contains("AssemblyTmpPath(AssetIndex) + '.sha256'"));
      expect(belongs, contains('Lowercase(AssetSha[AssetIndex])'));

      final consumed = _routine(script, 'function ConsumedPartCount(');
      final check = consumed.indexOf('if not AssemblyTmpBelongs(AssetIndex)');
      expect(check, greaterThanOrEqualTo(0));
      expect(
        consumed.indexOf('DeleteFile(TmpPath);', check),
        greaterThan(check),
      );
      expect(consumed.indexOf('FileSize64(TmpPath, Size)'), greaterThan(check));

      final assemble = _routine(script, 'function AssembleAsset(');
      final sidecar = assemble.indexOf(
        "SaveStringToFile(TmpPath + '.sha256'",
      );
      expect(sidecar, greaterThanOrEqualTo(0));
      expect(
        assemble.indexOf('AppendFileTo(TmpPath, PartPath,'),
        greaterThan(sidecar),
        reason: 'חותם הצד נכתב לפני הבית הראשון',
      );
      expect(
        assemble.lastIndexOf("DeleteFile(TmpPath + '.sha256')"),
        greaterThan(assemble.indexOf('RenameFile(TmpPath, FinalPath)')),
      );
    });

    test('$_assistant: קובץ מטמון עם קישור נוסף אינו נסמך על החותם', () {
      final script = _script(_assistant);
      expect(
        script,
        contains("external 'GetFileInformationByHandle@kernel32.dll stdcall'"),
      );
      expect(
        _routine(script, 'function LinkCount('),
        contains('Result := Info.nNumberOfLinks;'),
      );
      expect(
        _routine(script, 'function FileMatchesMarker('),
        contains('(FileStamp <= MarkerStamp) and (LinkCount(Path) = 1)'),
        reason: 'דריסת הקובץ ביעד משנה גם את המטמון בלי לקדם את זמן השינוי',
      );
    });

    test('$_assistant: תג ושמות נכס וחלק נבדקים לפי החוזה', () {
      final script = _script(_assistant);
      final safe = _routine(script, 'function IsSafeName(');
      for (final allowed in const [
        "(C >= 'A') and (C <= 'Z')",
        "(C >= 'a') and (C <= 'z')",
        "(C >= '0') and (C <= '9')",
        "(C = '.')",
        "(C = '_')",
        "(C = '+')",
        "(C = '-')",
      ]) {
        expect(safe, contains(allowed));
      }
      expect(safe, contains('Result := not OnlyDots;'), reason: "'..'");
      final url = _routine(script, 'function AssetUrl(');
      expect(url, contains('not IsSafeName(Tag)'));
      expect(url, contains('not IsSafeName(Name)'));
      expect(
        _routine(script, 'function ParseManifest('),
        contains('if not IsSafeName(PartName[NP])'),
      );
    });

    test('$_assistant: התג המוטבע אינו תלוי ב-API', () {
      // מגבלת הקצב של api.github.com (403/429) משותפת לכל יוצאי אותה כתובת.
      final load = _routine(
        _script(_assistant),
        'function LoadReleaseManifest(',
      );
      final branch = load.indexOf('if PinnedTag <> LatestTag then');
      expect(branch, greaterThanOrEqualTo(0));
      expect(
        load.indexOf('ManifestAsset := ReleaseManifestAsset;', branch),
        greaterThan(branch),
      );
      expect(load, isNot(contains("'tags/'")));
      expect(load, contains('by direct URL'));
    });

    test('$_assistant: עמוד הפורמט אינו מפנה מברירת המחדל', () {
      final wizard = _routine(
        _script(_assistant),
        'procedure InitializeWizard()',
      );
      final format = wizard.substring(wizard.indexOf('FormatPage :='));
      final text = format.substring(0, format.indexOf(');'));
      expect(text, isNot(contains('הפצה אחרת')));
      expect(text, contains('השאר את הבחירה המסומנת'));
    });

    test('$_assistant: הגדרות הפיתוח לעולם אינן מוגדרות ב-CI', () {
      final script = _script(_assistant);
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync();
      for (final define in const [
        'DevManifestFile',
        'DevSelectionDump',
        'DevApiBase',
      ]) {
        expect(workflow, isNot(contains(define)), reason: define);
        expect(script, contains('#ifdef $define'));
        expect(
          script,
          isNot(matches(RegExp('#define\\s+$define'))),
          reason: 'הגדרת פיתוח מגיעה רק מ-/D בבנייה ידנית',
        );
      }
      expect(
        RegExp(r'GetEnv\("([^"]+)"\)').allMatches(script).map((m) => m[1]),
        ['OTZARIA_ASSISTANT_RELEASE_TAG'],
        reason: 'משתנה סביבה ב-runner לא יפעיל מצב פיתוח',
      );
    });

    test('$_assistant: ההרכבה מוחקת כל חלק מיד אחרי הוספתו', () {
      final assemble = _routine(_script(_assistant), 'function AssembleAsset(');
      final append = assemble.indexOf('AppendFileTo(TmpPath, PartPath,');
      final delete = assemble.indexOf('DeleteFile(PartPath)');

      expect(append, greaterThanOrEqualTo(0));
      expect(
        delete,
        greaterThan(append),
        reason: 'בלי המחיקה שיא הדיסק הוא פי שניים מגודל הקובץ המורכב',
      );
      expect(
        _script(_assistant),
        isNot(contains('powershell')),
        reason: 'התוצאה חייבת להיווצר בלי PowerShell ובלי כלים חיצוניים',
      );
    });

    test('$_assistant: תג ה-release נקבע פעם אחת לכל הריצה', () {
      final load = _routine(
        _script(_assistant),
        'function LoadReleaseManifest(',
      );

      expect(load, contains("JStr(ApiRaw, 1, 'tag_name')"));
      expect(
        load,
        contains("AssetUrl('Otzaria/otzaria', PinnedTag, ManifestAsset)"),
        reason: 'המניפסט חייב לרדת מאותו תג שנקרא — לא מ-latest שוב',
      );
      expect(
        _script(_assistant),
        isNot(contains('releases/latest/download')),
        reason: 'כתובת latest מתחלפת באמצע ההורדה ומערבבת שתי גרסאות',
      );
    });

    test('$_assistant: מניפסט חסר או פגום אינו מפיל ואינו מוריד ללא אימות', () {
      final init = _routine(_script(_assistant), 'function InitializeSetup()');

      expect(init, contains('LoadErrorHeb'));
      expect(
        init,
        contains('https://github.com/Otzaria/otzaria/releases/latest'),
        reason: 'הנסיגה היחידה היא הפניית המשתמש לעמוד ההורדות',
      );
      expect(
        init,
        isNot(contains('DownloadPage')),
        reason: 'בלי מניפסט אין hash — ולכן אין הורדה',
      );
      expect(init, contains('Result := False'));
    });

    test('$_assistant: הסקריפט אינו תלוי בעדכון הגרסה של המתקינים', () {
      final script = _script(_assistant);

      expect(
        script,
        isNot(contains('MyAppVersion')),
        reason: 'הכלי חסר-גרסה: הוא קורא את התג בזמן ריצה',
      );
      for (final tool in const [
        'tool/version/update_version.sh',
        'tool/version/update_version.ps1',
      ]) {
        expect(
          File(tool).readAsStringSync(),
          isNot(contains(_assistant)),
          reason: '$tool אינו אמור לגעת בסקריפט חסר-הגרסה',
        );
      }
    });

    test('$_assistant: אין שורה שמתחילה ב-# שאינו דירקטיבה', () {
      // ISPP מפרש # בתחילת שורה גם אחרי הזחה — קבוע כמו #13#10 שנדחף
      // לראש שורה שובר את הקומפילציה, והקובץ אינו נבנה בטסטים.
      final offenders = <String>[];
      final lines = _script(_assistant).split('\n');
      final directive = RegExp(r'^\s*#(ifndef|ifdef|if|else|endif|define)\b');
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'^\s*#').hasMatch(lines[i]) &&
            !directive.hasMatch(lines[i])) {
          offenders.add('${i + 1}: ${lines[i].trim()}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('$_assistant: התג מגיע ממשתנה סביבה, עם נסיגה בהיעדרו', () {
      final script = _script(_assistant);
      // התג המוטבע הוא ברירת המחדל; בלעדיו הכלי חוזר ל-/releases/latest.
      expect(script, contains('#ifndef AssistantReleaseTag'));
      // ‎/D‎ עם מרכאות מגיע ל-ISPP עטוף בלוכסנים; נמדד: ‎\0.10.0+139\‎.
      expect(
        script,
        contains('GetEnv("OTZARIA_ASSISTANT_RELEASE_TAG")'),
      );
      expect(script, contains("Trim('{#AssistantReleaseTag}')"));
      expect(script, contains("PinnedTag := LatestTag"));
      expect(script, contains("PinnedTag := EmbeddedTag"));
      expect(script, contains('/releases/'));
    });

    test('$_assistant: ההשוואה מתעלמת מסיומת ‎+build', () {
      final script = _script(_assistant);
      final versionPart = script.substring(
        script.indexOf('function VersionPart('),
        script.indexOf('function CompareVersionText('),
      );
      expect(versionPart, contains("Pos('+', Result)"));
      expect(versionPart, contains('Copy(Result, 1, P - 1)'));
      // רק גרסה גבוהה יותר דוחקת את התג המוטבע.
      expect(
        script,
        contains('CompareVersionText(LatestTag, EmbeddedTag) > 0'),
      );
    });

    test('ה-workflow מעביר את התג לבניית מסייע ההורדה', () {
      final step = _workflowStep(
        'Build Download Assistant (non-fatal helper tool)',
      );
      expect(step, contains(r'$env:OTZARIA_ASSISTANT_RELEASE_TAG = $tag'));
      expect(step, contains(r'& "$env:ISCC" installer\download_assistant.iss'));
      expect(step, isNot(contains('/DAssistantReleaseTag=')));
      // אותו כלל תג שבו create_release משתמש.
      expect(
        step,
        contains(
          r"$tag = & ./tool/version/release_tag.ps1 $version "
          r"'${{ github.ref }}' '${{ github.run_number }}'",
        ),
      );
    });
  });

  group('תג ה-release של המתקין המאונדקס', () {
    // ‎/D‎ עם ערך במרכאות מגיע ל-ISPP עטוף בלוכסנים דרך pwsh, והכתובת
    // שנבנית ממנו שבורה. נמדד מול ISCC אמיתי: ‎[\0.10.0+139\]‎.
    test('$_full: התג מגיע ממשתנה סביבה, עם נפילה אחורה', () {
      final script = _script(_full);
      final flat = script.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        flat,
        contains(
          '#ifndef IndexedReleaseTag '
          '#define IndexedReleaseTag GetEnv("OTZARIA_INDEXED_RELEASE_TAG") '
          '#endif',
        ),
        reason: '‎#ifndef‎ משאיר ל-‎/D‎ מפורש לנצח בבנייה מקומית',
      );
      expect(
        flat,
        contains(
          '#if IndexedReleaseTag == "" '
          '#define IndexedReleaseTag MyAppVersion '
          '#endif',
        ),
        reason: 'בנייה בלי תג ובלי משתנה סביבה חייבת עדיין להתקמפל',
      );
      expect(
        flat,
        contains(
          '#define IndexedReleaseBaseUrl '
          '"https://github.com/Otzaria/otzaria/releases/download/" '
          '+ IndexedReleaseTag',
        ),
      );
    });

    test('ה-workflow מעביר את התג בסביבה ולא ב-‎/D‎', () {
      final step = _workflowStep('Build indexed FULL bootstrap installer');

      expect(
        step,
        contains(r'$env:OTZARIA_INDEXED_RELEASE_TAG = $releaseTag'),
      );
      expect(
        step,
        contains(
          r'$releaseTag = & ./tool/version/release_tag.ps1 $version '
          r'$env:GITHUB_REF $env:GITHUB_RUN_NUMBER',
        ),
      );
      expect(
        step,
        contains(
          '& "\$env:ISCC" \'/DIndexedSplitFull=1\' installer\\otzaria_full.iss',
        ),
      );
      expect(
        step,
        isNot(contains('/DIndexedReleaseTag')),
        reason: 'ערך שעובר ב-‎/D‎ דרך pwsh מגיע עטוף בלוכסנים',
      );
      // דגל בלי ערך — לא מושפע מהעיוות ונשאר כפי שהוא.
      expect(step, contains("'/DIndexedSplitFull=1'"));
    });
  });
}

/// גוף שלב [name] ב-workflow הראשי, עד השלב הבא.
String _workflowStep(String name) {
  final workflow = File(
    '.github/workflows/build-and-announce.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final start = workflow.indexOf('- name: $name');
  expect(start, greaterThanOrEqualTo(0), reason: 'לא נמצא השלב $name');
  final next = workflow.indexOf('\n      - name: ', start + 1);
  return next < 0 ? workflow.substring(start) : workflow.substring(start, next);
}
