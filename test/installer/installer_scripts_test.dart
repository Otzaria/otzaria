import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/plugins/services/bundled_plugin_seed_service.dart';
import 'package:otzaria/plugins/services/plugin_protocol_registration_service.dart';
import 'package:otzaria/semantic_search/models/semantic_import_layout.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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

/// `#include "x"` מילולי, כמו שכבת התצוגה ובדיקת הרשת של התוספים.
final _includeLine = RegExp(
  r'^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$',
  multiLine: true,
);

String _read(String name) =>
    File('installer/$name').readAsStringSync().replaceAll('\r\n', '\n');

/// כל סקריפט נקרא כמו ש-ISPP רואה אותו: עם מה שהוא כולל, גם בתוך קובץ כלול,
/// כדי שכל אינוריאנטה תחול על הקוד בכל קובץ שבו הוא יושב.
String _script(String name) => _expandIncludes(_read(name));

String _expandIncludes(String text) => text.replaceAllMapped(
  _includeLine,
  (m) => _expandIncludes(_read(m[1]!)),
);

/// גופי כל מקטעי `[Name]` בסקריפט, ולא רק הראשון.
List<String> _sections(String script, String name) {
  final header = RegExp(r'^\[([A-Za-z]+)\]\s*$', multiLine: true);
  final matches = header.allMatches(script).toList();
  return [
    for (var i = 0; i < matches.length; i++)
      if (matches[i][1] == name)
        script.substring(
          matches[i].end,
          i + 1 < matches.length ? matches[i + 1].start : script.length,
        ),
  ];
}

/// תוכן כל מקטעי `[Name]`, לפי סדר ההכללה.
String _section(String script, String name) {
  final sections = _sections(script, name);
  expect(sections, isNotEmpty, reason: 'המקטע [$name] חסר בסקריפט');
  return sections.join('\n');
}

/// גוף שגרת Pascal מהחתימה ועד ה-`end;` שבתחילת שורה (שגרות ראשיות בלבד —
/// `end;` מקונן תמיד מוזח בקבצים האלה). הצהרת `forward` (חוזה המתאם שבליבה
/// של שכבת התצוגה) אינה גוף, ולכן מדלגים עליה עד המימוש.
String _routine(String script, String signature) {
  var start = script.indexOf(signature);
  while (start >= 0 && _isForward(script, start)) {
    start = script.indexOf(signature, start + signature.length);
  }
  expect(start, greaterThanOrEqualTo(0), reason: 'לא נמצאה השגרה $signature');
  final end = script.indexOf('\nend;', start);
  expect(end, greaterThan(start), reason: 'לא נמצא סוף השגרה $signature');
  return script.substring(start, end);
}

bool _isForward(String script, int start) {
  final open = script.indexOf('(', start);
  var header = script.indexOf(';', start);
  if (open >= 0 && open < header) {
    header = script.indexOf(';', script.indexOf(')', open));
  }
  return header >= 0 && script.startsWith(RegExp(r'\s*forward;'), header + 1);
}

/// מכווץ רצפי רווחים כדי שהשוואות לא יישברו על עיצוב מחדש.
String _squeeze(String value) =>
    value.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

/// ערכי כל מקטעי `[CustomMessages]` או `[Messages]` לפי שפה; מפתח בלי קידומת שפה
/// (חל על כל השפות) נשמר תחת `''`.
Map<String, Map<String, String>> _messages(String script, String section) {
  final result = <String, Map<String, String>>{};
  final entry = RegExp(r'^(?:([A-Za-z]+)\.)?([A-Za-z0-9_]+)=(.*)$');
  for (final body in _sections(script, section)) {
    for (final line in body.split('\n')) {
      final match = entry.firstMatch(line.trim());
      if (match == null) continue;
      (result[match[1] ?? ''] ??= {})[match[2]!] = match[3]!;
    }
  }
  return result;
}

/// הטקסט של [key] ב-`[CustomMessages]` של המסייע בשפה [lang].
String _text(String script, String lang, String key) {
  final value = _messages(script, 'CustomMessages')[lang]?[key];
  expect(value, isNotNull, reason: '$lang.$key חסר ב-[CustomMessages]');
  return value!;
}

/// מחרוזות Pascal שבגופי `[Code]`, בלי הערות, ולכל אחת המשפט (עד `;`) שבו היא
/// מופיעה. `{#...}` הוא ISPP ולא הערה.
List<({String literal, String statement})> _codeLiterals(String script) {
  final literals = <({String literal, String statement})>[];
  for (final code in _sections(script, 'Code')) {
    final pending = <String>[];
    final statement = StringBuffer();
    var i = 0;
    while (i < code.length) {
      if (code.startsWith('{#', i)) {
        final end = code.indexOf('}', i) + 1;
        statement.write(code.substring(i, end));
        i = end;
      } else if (code[i] == '{') {
        i = code.indexOf('}', i) + 1;
      } else if (code.startsWith('(*', i)) {
        i = code.indexOf('*)', i) + 2;
      } else if (code.startsWith('//', i)) {
        final end = code.indexOf('\n', i);
        i = end < 0 ? code.length : end;
      } else if (code[i] == "'") {
        final value = StringBuffer();
        i++;
        while (i < code.length) {
          if (code[i] == "'") {
            if (code.startsWith("''", i)) {
              value.write("'");
              i += 2;
              continue;
            }
            i++;
            break;
          }
          value.write(code[i]);
          i++;
        }
        pending.add(value.toString());
        statement.write("'$value'");
      } else if (code[i] == ';') {
        for (final literal in pending) {
          literals.add((literal: literal, statement: statement.toString()));
        }
        pending.clear();
        statement.clear();
        i++;
      } else {
        statement.write(code[i]);
        i++;
      }
    }
  }
  return literals;
}

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
        final guardAt = body.indexOf(
          RegExp(
            r'if \(CurPageID = wpSelectDir\) and PortableMode and\s+'
            r'IsProtectedInstallDir\(',
          ),
        );

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

  group('תיקיית יעד ארוכה מדי נחסמת לפני ההעתקה (MAX_PATH)', () {
    const include = 'install_dir_length_check.iss';

    for (final name in _scripts) {
      test('$name: הבדיקה רצה בעמוד בחירת התיקייה, גם בהתקנה שקטה', () {
        final script = _script(name);
        expect(
          _sections(script, 'Code').join(),
          contains('function InstallDirTooLong(): Boolean;'),
        );

        final body = _routine(script, 'function NextButtonClick(');
        final checkAt = body.indexOf(
          'CurPageID = wpSelectDir) and InstallDirTooLong()',
        );
        expect(
          checkAt,
          greaterThan(0),
          reason: 'הבדיקה נעלמה מ-NextButtonClick',
        );
        expect(
          checkAt,
          lessThan(body.indexOf('WizardSilent')),
          reason:
              'אחרי היציאה בהתקנה שקטה, /DIR ארוך נכשל באמצע ההעתקה '
              'במקום להיעצר מראש',
        );
        expect(body.substring(checkAt), contains('Result := False'));
      });

      test('$name: הבדיקה סורקת את התיקייה שממנה מועתקים הקבצים', () {
        expect(
          _section(_script(name), 'Files'),
          contains(r'Source: "..\build\windows\{#AppArch}\runner\Release\*'),
        );
        expect(
          _read(include),
          contains(
            r'"..\build\windows\" + AppArch + "\runner\Release"',
          ),
        );
      });
    }

    test('הודעת הנתיב משתמשת בתרגום ובמתאם ההודעות המשותף', () {
      final helper = _read(include);
      final body = _routine(helper, 'function InstallDirTooLong(');
      expect(body, contains('InstTellSuppressible('));
      expect(body, isNot(contains('SuppressibleMsgBox(')));
      expect(body, contains("CustomMessage('InstallDirTooLongTitle')"));
      expect(
        body,
        contains("FmtMessage(CustomMessage('InstallDirTooLongText'),"),
      );
      expect(body, contains('IntToStr(Length(WizardDirValue))'));
      expect(body, contains('IntToStr({#MaxInstallDirLength})'));
      expect(
        body,
        contains('Result := Length(WizardDirValue) > {#MaxInstallDirLength}'),
      );
      expect(
        helper,
        contains(
          'procedure InstTellSuppressible(const Title, Text: String); forward;',
        ),
      );
      expect(
        helper.indexOf('procedure InstTellSuppressible('),
        lessThan(helper.indexOf('function InstallDirTooLong(')),
      );

      final messages = _messages(helper, 'CustomMessages');
      expect(messages['hebrew']!['InstallDirTooLongTitle'], isNotEmpty);
      expect(messages['english']!['InstallDirTooLongTitle'], isNotEmpty);
      for (final lang in ['hebrew', 'english']) {
        final text = messages[lang]!['InstallDirTooLongText']!;
        expect(text, contains('%1'));
        expect(text, contains('%2'));
        expect(text, contains('%n%n'));
      }
      expect(
        helper,
        matches(
          RegExp(
            r'#ifdef OtzariaUiProduct\s+english\.InstallDirTooLongTitle=[^\n]+\n'
            r'english\.InstallDirTooLongText=[^\n]+\n#endif',
          ),
        ),
        reason: 'אנגלית נכללת רק כששכבת התצוגה מגדירה את השפה',
      );
    });

    test('המתאם הישן שומר על הודעה ניתנת להשתקה ומפנה מקום למתאם המעוצב', () {
      const fallback = 'installer_message_fallback.iss';
      final text = _read(fallback);
      expect(text.trim(), startsWith('#ifndef OtzariaUiProduct'));
      expect(text.trim(), endsWith('#endif'));
      final body = _routine(text, 'procedure InstTellSuppressible(');
      expect(body, contains('SuppressibleMsgBox(Text, mbError, MB_OK, IDOK)'));
      expect(body, isNot(contains('UiTell(')));
      for (final name in _scripts) {
        final script = _script(name);
        final fallbackAt = script.indexOf(text);
        expect(
          fallbackAt,
          greaterThan(script.indexOf('function NextButtonClick(')),
        );
        expect(_sections(script, 'Code').join(), contains(text));
        final implementation = RegExp(
          r'procedure InstTellSuppressible\([^;]+;\s*begin',
        );
        final adapterAt = implementation.firstMatch(script)!.start;
        expect(
          adapterAt,
          lessThanOrEqualTo(fallbackAt + text.indexOf('procedure')),
          reason: 'המתאם המעוצב חייב להופיע לפני ה-fallback הלא פעיל',
        );
      }
    });

    test('שמות הנכסים שלנו קצרים מספיק לתיקיות התקנה עמוקות', () {
      // Flutter שומר כל נכס ב-data\flutter_assets בשם מקודד-URI, ולכן כל אות
      // עברית בשם עולה 6 תווים בנתיב. 100 משאיר לתיקיית היעד 158 תווים.
      const maxInstalledPath = 100;
      final flutter =
          (loadYaml(File('pubspec.yaml').readAsStringSync())
                  as YamlMap)['flutter']
              as YamlMap;
      final keys = <String>[
        for (final entry in (flutter['assets'] as YamlList).cast<String>())
          if (!entry.endsWith('/'))
            entry
          else if (Directory(entry).existsSync())
            for (final file in Directory(entry).listSync().whereType<File>())
              '$entry${p.basename(file.path)}',
        for (final family in flutter['fonts'] as YamlList)
          for (final font in (family as YamlMap)['fonts'] as YamlList)
            (font as YamlMap)['asset'] as String,
      ];
      expect(keys, isNotEmpty);

      final tooLong = {
        for (final key in keys)
          key: 'data/flutter_assets/${Uri.encodeFull(key)}'.length,
      }..removeWhere((_, length) => length <= maxInstalledPath);
      expect(
        tooLong,
        isEmpty,
        reason:
            'נתיב ההתקנה של הנכסים האלה ארוך מ-$maxInstalledPath תווים, '
            'והתקנה לתיקייה עמוקה תיכשל — יש לתת להם שם קצר באנגלית',
      );
    });
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
        final verify = extract.indexOf("StagingBooks + '\\seforim.db'");
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

  group('נתוני החיפוש החכם לצד מתקין ה-FULL', () {
    test('semantic-import שליד המתקין מועתק להורה של תיקיית הספרייה', () {
      final script = _script(_full);
      // שורת המשך של Inno (`\` בסוף שורה) מצורפת לשורה אחת.
      final files = _squeeze(
        _sections(script, 'Files').join().replaceAll('\\\n', ' '),
      );
      expect(
        files,
        contains(
          'Source: "{src}\\$kSemanticImportFolderName\\*"; '
          'DestDir: "{code:GetSemanticImportDir}"; Flags: external '
          'recursesubdirs createallsubdirs skipifsourcedoesntexist',
        ),
      );
      // SemanticPaths.root באפליקציה הוא ההורה של נתיב הספרייה.
      expect(
        _routine(script, 'function GetSemanticImportDir('),
        contains(
          "ExtractFileDir(GetSelectedBooksPath('')) + "
          "'\\$kSemanticImportFolderName'",
        ),
      );
    });

    // "מלאה" ב-x64 עם מתקין FULL גדול היא המתקין הרגיל + חלקים + נתוני החיפוש.
    test('$_regular: מעתיק גם הוא, בכל ארכיטקטורה ובלי תלות בחלקים', () {
      final script = _script(_regular);
      // כל מקטעי [Files]: העיצוב של שכבת התצוגה במקטע משלו לפניהם.
      final filesSection = _sections(
        script,
        'Files',
      ).join().replaceAll('\\\n', ' ');
      final line = _squeeze(
        filesSection,
      ).split('\n').singleWhere((l) => l.contains(kSemanticImportFolderName));
      expect(
        line,
        startsWith(
          'Source: "{src}\\$kSemanticImportFolderName\\*"; '
          'DestDir: "{code:GetSemanticImportDir}"; Flags: external '
          'recursesubdirs createallsubdirs skipifsourcedoesntexist',
        ),
      );
      final ifdef = filesSection.indexOf('#ifdef LibraryParts');
      final endif = filesSection.indexOf('#endif', ifdef);
      expect(
        filesSection.indexOf(kSemanticImportFolderName),
        greaterThan(endif),
        reason: 'ההעתקה אינה חלק מתמיכת החלקים',
      );
      expect(
        _routine(script, 'function GetSemanticImportDir('),
        contains(
          "ExtractFileDir(GetLibraryBooksPath()) + "
          "'\\$kSemanticImportFolderName'",
        ),
      );
    });
  });

  group('חלקי הספרייה והאינדקס לצד המתקין הרגיל', () {
    test('$_regular: התמיכה נבנית רק עם המניפסטים, בשתי הארכיטקטורות', () {
      final script = _script(_regular);

      expect(
        script,
        contains(
          '#if FileExists(AddBackslash(SourcePath) + "library.manifest.json")\n'
          '  #define LibraryParts\n',
        ),
        reason: 'בנייה מקומית בלי המניפסט אינה מכירה את החלקים',
      );
      expect(
        script,
        contains(
          '  #if FileExists(AddBackslash(SourcePath) + '
          '"library_index.manifest.json")\n'
          '    #define LibraryIndexParts\n',
        ),
        reason: 'האינדקס נתמך רק יחד עם הספרייה',
      );
      expect(script, isNot(contains('#if AppArch == "x64" && FileExists')));
      // השמות חייבים להתאים לארכיונים שה-workflow אורז ומפצל.
      expect(
        script,
        contains(
          '#define LibraryArchiveName "otzaria-" + MyAppVersion + '
          '"-library.tar.zst"',
        ),
      );
      expect(
        script,
        contains(
          '#define IndexArchiveName "otzaria-" + MyAppVersion + '
          '"-library-index.tar.zst"',
        ),
      );
    });

    test('$_full: אין יותר מתקין מאונדקס נפרד', () {
      final script = _script(_full);

      expect(script, isNot(contains('IndexedSplitFull')));
      expect(script, isNot(contains('windows-full-indexed')));
      expect(script, isNot(contains('CreateDownloadPage')));
    });

    test(
      '$_regular: בלי חלקי ספרייה — בדיקת תיקייה ויציאה לפני PowerShell',
      () {
        final prepare = _routine(
          _script(_regular),
          'function PrepareLibraryParts(): Boolean;',
        );
        final quickCheck = prepare.indexOf(
          "HasSplitArchiveParts(SourceDir, '{#LibraryArchiveName}')",
        );

        expect(prepare, contains(r"ExpandConstant('{srcexe}')"));
        expect(quickCheck, greaterThan(0));
        expect(
          quickCheck,
          lessThan(prepare.indexOf('PrepareSplitArchive(')),
          reason: 'עדכון רגיל (גם שקט) לא מחלץ קבצים ולא מריץ PowerShell',
        );
        final split = _routine(
          _script(_regular),
          'function PrepareSplitArchive(',
        );
        expect(split, contains('LocalPartsAreComplete(SourceDir, PartNames)'));
        expect(
          split,
          contains('AssembleSplitArchive(ManifestPath, SourceDir,'),
        );
        // מתקין בשורש כונן: "E:\" היה הופך את \" למרכאה מילולית בשורת הפקודה.
        expect(
          _routine(_script(_regular), 'function AssembleSplitArchive('),
          contains("AddBackslash(PartsDir) + '.\"'"),
        );
        expect(
          _script(_regular),
          isNot(contains('CreateDownloadPage')),
          reason: 'המתקין הרגיל אינו מוריד את החלקים בעצמו',
        );
        expect(
          File('tool/release/assemble_split_asset.ps1').readAsStringSync(),
          contains(r'$part.sha256'),
        );
      },
    );

    test('$_regular: אינדקס בלי ספרייה אינו נפרס', () {
      final prepare = _routine(
        _script(_regular),
        'function PrepareLibraryParts(): Boolean;',
      );
      final noLibrary = prepare.substring(
        prepare.indexOf(
          "HasSplitArchiveParts(SourceDir, '{#LibraryArchiveName}')",
        ),
        prepare.indexOf("Result := False;"),
      );

      expect(
        noLibrary,
        contains("HasSplitArchiveParts(SourceDir, '{#IndexArchiveName}')"),
      );
      expect(noLibrary, contains('Log('));
      expect(noLibrary, contains('exit;'));
      expect(noLibrary, isNot(contains('PrepareSplitArchive')));
      expect(
        prepare,
        contains(
          "PrepareSplitArchive('library_index.manifest.json',\n"
          "        '{#IndexArchiveName}'",
        ),
      );
    });

    test('$_regular: ARM64 — הכלים של x64 רצים רק ב-Windows 11', () {
      final prepare = _routine(
        _script(_regular),
        'function PrepareLibraryParts(): Boolean;',
      );
      final arm = prepare.substring(prepare.indexOf('#if AppArch == "arm64"'));

      expect(arm, contains(r'if GetWindowsVersion < $0A0055F0 then'));
      expect(
        _script(_regular),
        isNot(contains('MinVersion')),
        reason: 'מתקין ה-ARM64 הרגיל ממשיך לרוץ ב-Windows 10 בלי חלקים',
      );
    });

    test('$_regular: החלקים מוכנים לפני תחילת ההתקנה, גם בהתקנה שקטה', () {
      final next = _routine(_script(_regular), 'function NextButtonClick(');

      expect(next, contains('if CurPageID = wpReady then'));
      expect(
        next.indexOf('PrepareLibraryParts()'),
        lessThan(next.indexOf('if WizardSilent then')),
        reason: 'בהתקנה שקטה Inno "לוחץ" Next, והיציאה המוקדמת הייתה מדלגת',
      );
    });

    test('$_regular: כשל בחלקים אינו נתקע בהתקנה שקטה', () {
      // כל הודעה עוברת בעוזר שבשקט קורא בדיוק ל-SuppressibleMsgBox, ובאשף מעוצבת.
      final script = _script(_regular);
      for (final (routine, helper) in const [
        ('function PrepareSplitArchive(', 'procedure InstTellSuppressible('),
        (
          'procedure LibraryInstallFailed(',
          'procedure InstReportLibraryFailure(',
        ),
      ]) {
        final body = _routine(script, routine);
        expect(body, contains(helper.split(' ')[1]), reason: routine);
        expect(body, isNot(contains('MsgBox(')), reason: routine);
        final silent = _routine(script, helper);
        expect(silent, contains('SuppressibleMsgBox('), reason: helper);
        expect(silent, isNot(contains(' MsgBox(')), reason: helper);
      }
      // ההודעה המושתקת אינה מותירה קוד יציאה 0 כשהספרייה לא הותקנה.
      expect(
        _routine(_script(_regular), 'procedure LibraryInstallFailed('),
        contains('LibraryNotInstalled := True;'),
      );
      expect(
        _routine(_script(_regular), 'function GetCustomSetupExitCode('),
        contains('if LibraryNotInstalled then'),
      );
    });

    test('$_regular: חלקי ספרייה של גרסה אחרת אינם מותקנים בשקט', () {
      final script = _script(_regular);
      final finder = _routine(script, 'function OtherVersionPartsName(');
      expect(
        finder,
        contains("'otzaria-*-library*.tar.zst.part-*'"),
        reason: 'גם חלקי אינדקס של גרסה אחרת',
      );
      expect(finder, contains("'{#LibraryArchiveName}.part-'"));
      final prepare = _routine(script, 'function PrepareLibraryParts(');
      expect(prepare, contains('OtherVersionPartsName(SourceDir)'));
      // בהתקנה שקטה ברירת המחדל היא לעצור, לא להתקין בלי הספרייה.
      expect(prepare, contains('InstAskYesNoSuppressible('));
      expect(prepare, contains(', IDNO);'));
      expect(
        _routine(script, 'function InstAskYesNoSuppressible('),
        contains(
          'SuppressibleMsgBox(Text, mbConfirmation, MB_YESNO, Default) = IDYES',
        ),
      );
    });

    test('$_regular: הפריסה מחליפה ספרייה ואינדקס רק אחרי חילוץ מלא', () {
      final script = _script(_regular);
      final extract = _routine(script, 'procedure ExtractLibraryArchives(');
      final step = _routine(script, 'procedure CurStepChanged(');

      expect(extract, contains(r"SourceIndex + '\.otzaria_prebuilt_index'"));
      expect(extract, contains('RenameFile(BooksPath, BooksBackup)'));
      expect(extract, contains('RenameFile(SourceBooks, BooksPath)'));
      // בלי אינדקס index הקיימת נשארת, כמו במתקין ה-FULL.
      expect(
        extract,
        contains(
          'IndexBackedUp := (not WithIndex) or (not DirExists(TargetIndex)) or',
        ),
      );
      expect(extract, contains('if WithIndex and DirExists(TargetIndex) then'));
      expect(
        extract,
        isNot(contains('Abort')),
        reason: 'Abort אינו עוצר את Setup ב-ssPostInstall — כשל מדווח וממשיכים',
      );
      // אחרי [Dirs], שנותנת למשתמשים הרשאה על תיקיית הנתונים ועל index.
      expect(
        step.indexOf('InstallPreparedLibrary()'),
        greaterThan(step.indexOf('if CurStep = ssPostInstall then')),
      );
      expect(
        step.indexOf('InstallPreparedLibrary()'),
        lessThan(step.indexOf('if CurStep <> ssInstall then')),
      );
    });

    test('$_regular: הספרייה נפרסת לנתיב שהאפליקציה קוראת ממנו', () {
      final script = _script(_regular);
      final body = _routine(
        script,
        'function GetLibraryBooksPath(): String;\nvar',
      );

      expect(
        _routine(script, 'procedure InstallPreparedLibrary('),
        contains('ExtractLibraryArchives(GetLibraryBooksPath())'),
      );
      expect(body, contains(r"'\otzaria_data\books'"));
      expect(body, contains('GetCustomLibraryPath()'));
      expect(body, contains('IsOtzariaBooksFolder(CustomPath)'));
      expect(
        body,
        contains(
          "ReadLibraryPreference('${SettingsRepository.keyLibraryFolderName}')",
        ),
      );
      expect(
        script,
        contains(
          "LibraryDatabasePathRecordFileName = '${AppPaths.libraryDatabasePathRecordFileName}';",
        ),
      );
      expect(body, contains(r"GetDataDir('') + '\books'"));
    });

    test('$_regular: ההשקה השקטה ממתינה לסוף הפריסה', () {
      final script = _script(_regular);
      final launch = _routine(
        script,
        'function ShouldLaunchAppAfterSilentInstall(',
      );
      final install = _routine(script, 'procedure InstallPreparedLibrary(');

      expect(launch, contains("(PreparedLibraryArchive = '')"));
      expect(install, contains('ExecAsOriginalUser('));
      expect(install, contains("{param:NOLAUNCH|0}"));
    });

    test('$_regular: הקבצים הזמניים ראשונים ב-[Files]', () {
      final files = _sections(_script(_regular), 'Files').join();
      final app = files.indexOf(r'Source: "..\build\windows\');

      for (final entry in const [
        'Source: "library.manifest.json"; Flags: dontcopy',
        'Source: "library_index.manifest.json"; Flags: dontcopy',
        'Source: "read_split_manifest.ps1"; Flags: dontcopy',
        r'Source: "..\tool\release\assemble_split_asset.ps1"; Flags: dontcopy',
        'Source: "zstd.exe"; Flags: dontcopy',
        'Source: "7za.exe"; Flags: dontcopy',
      ]) {
        expect(files.indexOf(entry), inInclusiveRange(0, app), reason: entry);
      }
    });

    test('ה-workflow בונה את המתקינים הרגילים אחרי חלקי הספרייה', () {
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final job = workflow.substring(
        workflow.indexOf('\n  build_windows_installer:\n'),
        workflow.indexOf('\n  create_release:\n'),
      );
      final prepare = _workflowStep('Prepare regular installer inputs');

      expect(
        job,
        contains(
          'needs: [bump_version, build_windows, build_windows_arm64, '
          'build_linux]',
        ),
      );
      expect(job, contains("needs.build_windows.result == 'success'"));
      expect(prepare, contains(r'installer\library.manifest.json'));
      expect(prepare, contains(r'installer\library_index.manifest.json'));
      expect(
        prepare,
        contains(r'Remove-Item "$releaseDir\portable.marker"'),
        reason: 'ה-ZIP נייד; marker שהיה נארז הופך כל התקנה רגילה לניידת',
      );
      expect(
        _workflowStep('Build regular installer'),
        contains(r'& "$env:ISCC" installer\otzaria.iss'),
      );
      expect(
        _workflowStep('Build regular installer (ARM64)'),
        contains(r'& "$env:ISCC" /DAppArch=arm64 installer\otzaria.iss'),
      );
      expect(
        workflow.split(r'/DAppArch=arm64 installer\otzaria.iss').length - 1,
        1,
        reason: 'מתקין ה-ARM64 הרגיל נבנה פעם אחת, עם המניפסטים',
      );
      expect(
        _workflowStep('Build Inno Setup installer'),
        isNot(contains(r'installer\otzaria.iss')),
        reason: 'המתקין הרגיל נבנה פעם אחת, עם המניפסט',
      );
    });

    test('ה-workflow אורז ספרייה ואינדקס כשני נכסים מפוצלים', () {
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        workflow,
        contains(
          'pack_library_asset "otzaria-\${VERSION}-library.tar.zst" books',
        ),
      );
      expect(
        workflow,
        contains(
          'pack_library_asset "otzaria-\${VERSION}-library-index.tar.zst" '
          'index',
        ),
      );
      expect(workflow.toLowerCase(), isNot(contains('library-full-indexed')));
      expect(
        workflow,
        contains('*-library.tar.zst.part-*|*-library-index.tar.zst.part-*)'),
        reason: 'החלקים אינם מקושרים בהערות השחרור',
      );
    });
  });

  group('מפתח נתיב הספרייה ב-shared_preferences', () {
    for (final name in _scripts) {
      test('$name: הקריאה מ-prefs משתמשת במפתח של האפליקציה', () {
        final script = _script(name);
        final key = SettingsRepository.keyLibraryPath;

        if (name == _regular) {
          final reader = _routine(script, 'function ReadLibraryPreference(');
          expect(reader, contains("KeyStr := '\"flutter.' + KeyName"));
          expect(reader, contains("KeyStr := '\"' + KeyName"));
          expect(
            reader,
            contains(r'{userappdata}\otzaria\shared_preferences.json'),
          );
          expect(
            _routine(script, 'function GetCustomLibraryPath('),
            contains("ReadLibraryPreference('$key')"),
          );
        } else {
          expect(script, contains('"flutter.$key":'));
          expect(script, contains('"$key":'));
          expect(
            _routine(script, 'function GetCustomLibraryPath('),
            contains(r'{userappdata}\otzaria\shared_preferences.json'),
          );
        }
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
        final prefsRead = body.indexOf(
          name == _regular
              ? "ReadLibraryPreference('key-library-path')"
              : 'shared_preferences.json',
        );
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

  group('הסרה מוחקת את רישום הפרוטוקול otzaria://', () {
    const scheme = PluginProtocolRegistrationService.scheme;
    const classKey = 'Software\\Classes\\$scheme';

    for (final name in _scripts) {
      test('$name: מפתח הפרוטוקול של המתקין נמחק בהסרה', () {
        final flags = [
          for (final line in _section(_script(name), 'Registry').split('\n'))
            if (line.startsWith('Root: HKA; Subkey: "$classKey";'))
              ...RegExp(
                r'Flags:([^;]*)',
              ).firstMatch(line)!.group(1)!.trim().split(RegExp(r'\s+')),
        ];
        expect(
          flags,
          contains('uninsdeletekey'),
          reason:
              'ב-uninsdeletekeyifempty המפתח לעולם אינו ריק (ערך ברירת המחדל '
              'נשאר), ו-otzaria:// נשאר מצביע על EXE שהוסר',
        );
      });

      test('$name: המפתח שהאפליקציה רושמת ב-HKCU נמחק רק אם הוא שלנו', () {
        final script = _script(name);
        final body = _routine(
          script,
          'procedure RemoveUserProtocolKeyIfOurs();',
        );
        expect(body, contains("'$classKey\\DefaultIcon'"));
        expect(
          body,
          contains("RegDeleteKeyIncludingSubkeys(HKCU, '$classKey')"),
          reason: 'בהתקנת מנהל HKA הוא HKLM, והמפתח שהאפליקציה כתבה נשאר',
        );
        expect(
          body,
          contains(
            "SameInstallDir(ExtractFileDir(ExePath), ExpandConstant('{app}'))",
          ),
          reason: 'מפתח שמצביע על התקנה אחרת שנשארת אסור למחוק',
        );
        expect(
          _routine(script, 'procedure CurUninstallStepChanged('),
          contains('RemoveUserProtocolKeyIfOurs();'),
        );
      });
    }
  });

  group('שיגור-מחדש עם מצב מפורש — בלי לשאול שוב', () {
    for (final name in _scripts) {
      test(
        '$name: ShouldSkipPage מדלג על הפתיחה, ו"איך להתקין" מסומן מראש',
        () {
          // בלי הדילוג הריצה המשוגרת-מחדש הייתה מתחילה שוב בפתיחה. "איך להתקין"
          // נשאר: בו נבחרת התיקייה, והבחירה כבר מסומנת לפי מצב התהליך.
          final script = _script(name);
          final body = _routine(script, 'function ShouldSkipPage(');
          expect(body, contains("CmdLineParamExists('/ALLUSERS')"));
          expect(body, contains("CmdLineParamExists('/CURRENTUSER')"));
          expect(body, contains('(PageID = wpWelcome)'));
          expect(body, isNot(contains('wpSelectDir')));
          final wizard = _routine(script, 'procedure InitializeWizard');
          expect(
            wizard,
            contains("(IsAdmin and not CmdLineParamExists('/CURRENTUSER'))"),
          );
          expect(wizard, contains('AllUsersModeRadio.Checked := True'));
        },
      );

      test('$name: שיגור-מחדש להחלפת מצב נסגר בלי שאלת "לצאת?"', () {
        // אירוע CancelButtonClick של שכבת התצוגה רץ לפני זה של הסקריפט, ושואל
        // אלא אם UiClosing — לכן הדגל מורם לפני הסגירה, יחד עם הדגל של הסקריפט.
        final next = _routine(_script(name), 'function NextButtonClick(');
        final closes = RegExp(
          r'RelaunchingForModeChange := True;\s*UiClosing := True;\s*WizardForm\.Close;',
        ).allMatches(next);
        expect(closes, isNotEmpty);
        expect(
          RegExp(r'WizardForm\.Close;').allMatches(next).length,
          closes.length,
          reason: 'כל סגירה לשיגור-מחדש חייבת להרים את UiClosing',
        );
        final cancel = _routine(
          _script(name),
          'procedure UiCancelButtonClick(',
        );
        expect(cancel, contains('if UiClosing then'));
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
        final script = _script(name);
        final tasks = _section(script, 'Tasks');
        final line = tasks
            .split('\n')
            .firstWhere((l) => l.contains('resetsettings'));
        final key = RegExp(
          r'Description: "\{cm:(\w+)\}"',
        ).firstMatch(line)![1]!;
        // גם הכרטיס שבעמוד האפשרויות.
        for (final text in [
          _text(script, 'hebrew', key),
          _text(script, 'hebrew', 'TaskResetDesc'),
        ]) {
          expect(
            text,
            isNot(contains('מומלץ')),
            reason: 'הניסוח "מומלץ למעדכנים" גרם למשתמשים לסמן ולאבד נתונים',
          );
          expect(text.indexOf('אזהרה'), greaterThanOrEqualTo(0));
          expect(text.indexOf('אזהרה'), lessThan(text.indexOf('ימחק')));
        }
        expect(
          _text(script, 'english', key),
          startsWith('Reset user settings — warning'),
        );
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
          '#if AppArch == "arm64"\n'
          '; "full" בשם מונע מהעדכון שבתוך התוכנה לבחור בו כמתקין עדכון.\n',
        ),
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
      final files = _sections(_script(_full), 'Files').join();

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
      // המתקין הרגיל של ARM64 נבנה ב-build_windows_installer, עם חלקי הספרייה.
      expect(job, isNot(contains('- name: Upload Windows ARM64 installer\n')));
      for (final earlier in const [
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
        'seforim.db.zst',
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

    // lexical.db ב-release קפוא לגרסאות ישנות; המילון המתוקן הוא lexical-v2.db.
    test('המילון נלקח מ-lexical-v2.db, ו-lexical.db רק כגיבוי', () {
      final script = File(
        'installer/download_full_installer_assets.ps1',
      ).readAsStringSync();
      expect(
        script.indexOf(r'$lexicalBase/lexical-v2.db'),
        allOf(
          isNonNegative,
          lessThan(script.indexOf(r'$lexicalBase/lexical.db')),
        ),
      );

      for (final entry in const {
        '.github/workflows/build-and-announce.yml':
            'SeforimMagicIndexer/releases/latest/download/lexical.db',
      }.entries) {
        final lines = File(entry.key).readAsLinesSync();
        final fallbacks = lines.where((l) => l.contains(entry.value));
        expect(fallbacks, isNotEmpty, reason: entry.key);
        for (final line in fallbacks) {
          expect(line.trim(), startsWith('||'), reason: entry.key);
        }
        expect(
          lines.where((l) => l.contains('/lexical-v2.db')).length,
          fallbacks.length,
          reason: entry.key,
        );
      }
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
        reason:
            'שלושת ה-jobs של מתקיני Windows (FULL, ARM64, רגיל) חייבים סינון',
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
      // ברירת המחדל (Yes, וב-Enter בדו-שיח המעוצב) חייבת להישאר חילוץ — דילוג
      // רק בבחירה מפורשת ב"לא".
      expect(ask, contains('PortableSkipLibrary := not InstAskYesNo('));
      expect(ask, contains('mbConfirmation, MB_YESNO)'));
      final yesNo = _routine(script, 'function InstAskYesNo(');
      expect(yesNo, contains('MsgBox(Text, Typ, Flags) = IDYES'));
      expect(
        yesNo.replaceAll(RegExp(r'\s+'), ' '),
        contains("CustomMessage('NoButton'), False, True)"),
        reason:
            'Danger=False: "כן" הוא כפתור ברירת המחדל; NoCancel: כמו MsgBox של '
            'כן/לא, Esc אינו בוחר ב"לא" ואינו מדלג על החילוץ',
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
  });

  group('מסייע ההורדה — אינו מתקין', () {
    test('$_assistant: אין התקנה לתיקיית תוכנה, קיצורים או רישום', () {
      final script = _script(_assistant);

      expect(script, contains('CreateAppDir=no'));
      expect(
        script,
        isNot(
          matches(
            RegExp(r'^\[(Icons|Registry|Dirs|INI)\]\s*$', multiLine: true),
          ),
        ),
        reason: 'הכלי אינו מתקין דבר — כל מקטע שמתקין הופך אותו למתקין',
      );
      // [Files] מותר רק לקבצים שנשלפים לתיקייה הזמנית: dontcopy בכל רשומה.
      for (final files in _sections(script, 'Files')) {
        final entries = files
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .where((line) => !line.startsWith(';') && !line.startsWith('#'));
        for (final entry in entries) {
          expect(
            entry,
            matches(RegExp(r'^Source:.*;\s*Flags:[^;]*\bdontcopy\b')),
            reason: 'רשומת [Files] בלי dontcopy מתקינה קובץ: $entry',
          );
        }
      }
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

    test('$_assistant: מאפייני הקובץ בשתי השפות — שם הקובץ נשאר ASCII', () {
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
        // מאפייני הקובץ אינם תלויים בשפת הממשק, ולכן גם באנגלית.
        expect(match.group(1)!, matches(RegExp('[A-Za-z]{4}')), reason: key);
        // Inno קוטע ערך ארוך מ-60 תווים בלי אזהרה.
        expect(
          match.group(1)!.trim().length,
          lessThanOrEqualTo(60),
          reason: key,
        );
      }
      final description = RegExp(
        r'^VersionInfoDescription=(.+)$',
        multiLine: true,
      ).firstMatch(script)!.group(1);
      expect(description, contains('אינו מתקין'));
      expect(description, contains('does not install'));
      expect(
        script,
        contains('VersionInfoProductTextVersion={#TagVersionPart}'),
        reason: 'הגרסה המוצגת נגזרת מהתג המוטבע ואינה מומצאת',
      );
    });

    test('$_assistant: ניסוחי ההתקנה של Inno נדרסים בשתי השפות', () {
      final byLang = _messages(_script(_assistant), 'Messages');

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
        for (final lang in const ['english', 'hebrew']) {
          expect(
            byLang[lang]?[id],
            isNotNull,
            reason: 'ברירת המחדל של $lang.$id מנוסחת כמתקין',
          );
        }
      }
      // "התקנה" מותר כאובייקט שמכינים; אסור שהכלי יתאר את עצמו כמתקין.
      final values = [
        for (final entries in byLang.values) ...entries.values,
      ].join('\n');
      expect(values, isNotEmpty);
      for (final claim in const [
        'תוכנת ההתקנה',
        'מתקין את',
        'על מחשבך',
        'This will install',
        'Setup will',
        'Installing',
      ]) {
        expect(values, isNot(contains(claim)), reason: claim);
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
      // בעברית שם החוזה; באנגלית שם אנגלי — רק ב-Windows ורק לתצוגה ולתיקייה.
      expect(
        _routine(script, 'function OutputSubFolderName()'),
        contains(
          "Msg1('OutputSubfolder', PlatformDisplayName(TargetPlatform))",
        ),
      );
      final contract = _messages(
        script,
        'CustomMessages',
      )['']!['ContractSubfolder'];
      expect(contract, 'אוצריא להתקנה ל-%1');
      expect(
        File(
          'tool/release/download_assistant_selection.dart',
        ).readAsStringSync(),
        contains("'אוצריא להתקנה ל-\${"),
        reason: 'שם החוזה זהה למימוש הייחוס',
      );
      expect(_text(script, 'hebrew', 'OutputSubfolder'), contract);
      expect(
        _text(script, 'english', 'OutputSubfolder'),
        'Otzaria setup for %1',
      );
      // DumpSelections משווה ל-expected-selections גם כשהממשק באנגלית.
      final dump = _routine(script, 'procedure DumpSelections()');
      expect(dump, contains("Msg1('ContractSubfolder',"));
      expect(dump, contains('PlannedOutputNotes(False)'));
      expect(dump, isNot(contains('OutputSubFolderName()')));

      expect(
        prepare,
        contains('if Produced = 1 then'),
        reason: 'הניסוח נגזר ממה שנוצר בפועל, לא מהרכיב שנבחר',
      );
      final single = prepare.substring(prepare.indexOf('if Produced = 1'));
      const folderReady = "CustomMessage('ResultFolderReady')";
      final multi = single.substring(single.indexOf(folderReady));
      final singleOnly = single.substring(0, single.indexOf(folderReady));
      expect(
        single,
        contains("CustomMessage('ResultFileReady') + #13#10 + SingleName"),
      );
      expect(singleOnly, isNot(contains('Folder')));
      expect(multi, contains("Msg1('GuideOtherFolder',"));
      expect(
        _text(script, 'hebrew', 'GuideOtherFolder'),
        allOf(
          contains('העתק את כל התיקייה הזאת'),
          contains('חייבים להישאר יחד'),
        ),
      );
      expect(
        _text(script, 'english', 'GuideOtherFolder'),
        allOf(contains('whole folder'), contains('must stay together')),
      );
      // עמוד הסיום של קובץ בודד מדבר בשפת המשתמש, בלי מונחים טכניים.
      final singleKeys = RegExp(
        r"(?:CustomMessage|Msg1)\('(\w+)'",
      ).allMatches(singleOnly).map((m) => m[1]!);
      for (final lang in const ['english', 'hebrew']) {
        for (final key in [...singleKeys, 'OpenHintExe', 'OpenHintArchive']) {
          final text = _text(script, lang, key).toLowerCase();
          for (final jargon in const [
            'מניפסט',
            'sha',
            'hash',
            'נכס',
            'manifest',
            'asset',
          ]) {
            expect(
              text,
              isNot(contains(jargon)),
              reason: '$lang.$key: $jargon',
            );
          }
        }
      }
    });

    test('$_assistant: תיבת "הצג" מסומנת מראש ומסמנת את מה שנוצר', () {
      final script = _script(_assistant);
      final page = _routine(script, 'procedure CurPageChanged(');
      final deinit = _routine(script, 'procedure DeinitializeSetup()');

      expect(page, contains('RevealCheck.Checked := True;'));
      expect(
        page,
        contains("RevealCheck.Caption := CustomMessage('RevealFile')"),
      );
      expect(
        page,
        contains("RevealCheck.Caption := CustomMessage('RevealFolder')"),
      );
      expect(_text(script, 'hebrew', 'RevealFile'), 'הצג את הקובץ שהוכן');
      expect(_text(script, 'hebrew', 'RevealFolder'), 'הצג את התיקייה שהוכנה');
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

    test(
      '$_assistant: העיצוב נשלף מ-assistant_art בלבד, ותמונות Inno כבויות',
      () {
        final script = _script(_assistant);

        // ריק במפורש: בלעדיו Inno מציג את תמונות ברירת המחדל שלו.
        for (final key in const ['WizardImageFile', 'WizardSmallImageFile']) {
          expect(
            script,
            matches(RegExp('^$key=\\s*\$', multiLine: true)),
            reason: key,
          );
        }
        expect(
          script.toLowerCase(),
          isNot(contains('.bmp')),
          reason: 'תמונת BMP של העיצוב הקודם עדיין מוזכרת',
        );

        final sources = [
          for (final files in _sections(script, 'Files'))
            ...RegExp(
              r'^Source:\s*"([^"]+)"',
              multiLine: true,
            ).allMatches(files).map((m) => m[1]!),
        ];
        expect(sources, isNotEmpty);
        for (final source in sources) {
          expect(source, startsWith(r'assistant_art\'), reason: source);
        }
        // העיצוב אינו במאגר ונמשך לפני הבנייה: בלעדיו הקומפילציה נעצרת בהסבר.
        expect(script, contains('#if !FileExists(AssistantArtIsi)'));
        expect(
          script.substring(script.indexOf('#if !FileExists(AssistantArtIsi)')),
          matches(RegExp(r'^\s*#error ', multiLine: true)),
        );
        expect(
          script,
          contains('ExtractTemporaryFiles('),
          reason: 'התמונות נשלפות בזמן ריצה ואינן מותקנות',
        );
      },
    );

    test(
      '$_assistant: הספר והכותרת מוטמעים רק בקנה המידה של המקור ומוצגים מתוחים',
      () {
        final script = _script(_assistant);
        final entries = [
          for (final files in _sections(script, 'Files'))
            ...RegExp(
              r'^Source:.*$',
              multiLine: true,
            ).allMatches(files).map((m) => m[0]!),
        ];

        String source(String entry) =>
            RegExp(r'^Source:\s*"([^"]+)"').firstMatch(entry)![1]!;

        // פריימי הספר הם רוב גודל הקובץ: עותק לכל קנה מידה מגדיל אותו פי 2.4.
        expect(
          entries.where(
            (e) =>
                source(e).contains('book_') ||
                source(e).contains('title_') ||
                source(e).contains('UiTitleFiles'),
          ),
          [
            r'Source: "assistant_art\book_*_{#AA_BOOK_SRC_SCALE}.png"; Flags: dontcopy nocompression',
            r'Source: "assistant_art\{#UiTitleFiles}_{#AA_TITLE_SRC_SCALE}.png"; Excludes: "{#UiTitleSkip}"; Flags: dontcopy nocompression',
          ],
        );
        // המסייע מטמיע את title_* בלי כותרות המתקינים (title_inst_*).
        expect(script, contains('#define UiTitleFiles "title_*"'));
        expect(script, contains('#define UiTitleSkip "title_inst_*"'));
        final perScale = entries.where(
          (e) => RegExp(r'^assistant_art\\\*_\d+\.png$').hasMatch(source(e)),
        );
        expect(perScale, hasLength(6));
        for (final entry in perScale) {
          expect(
            entry,
            contains('Excludes: "book_*,title_*{#UiArtSkip}"'),
            reason: 'עיצוב ישן עם ספר בכל קנה מידה היה מוטמע שוב: $entry',
          );
        }
        expect(script, contains('#ifndef AA_BOOK_SRC_SCALE'));

        // נשלפים מקנה המידה של המקור גם כשקנה המידה של החלון אחר — כל תמונה
        // כשמגיע תורה, ולא כולן בפעימה הראשונה שמעכבת את ציור החלון.
        final hero = _routine(script, 'function UiHeroImage(');
        expect(
          hero,
          contains(
            "UiLoadArt('book_' + Format('%.2d', [I]), {#AA_BOOK_SRC_SCALE})",
          ),
        );
        expect(
          hero.replaceAll(RegExp(r'\s+'), ' '),
          contains(
            "UiLoadArt(UiTitleArt + IntToStr(I - {#AA_BOOK_FRAMES}), {#AA_TITLE_SRC_SCALE})",
          ),
        );
        // הכותרת האנגלית (title_en_*) נכללת ב-title_* של [Files], ונבחרת רק
        // כשהעיצוב מגדיר AA_TITLE_EN; בלעדיו — הכותרת העברית.
        final init = _routine(script, 'procedure UiInitializeWizard(');
        final titleEn = init.indexOf('#ifdef AA_TITLE_EN');
        expect(titleEn, greaterThanOrEqualTo(0));
        expect(
          init.substring(titleEn, init.indexOf('#endif', titleEn)),
          allOf(
            contains('UiTitleArt := TitleArtEn'),
            contains('UiTitleArt := TitleArt;'),
            contains('if UiRtl then'),
          ),
        );
        expect(
          script,
          contains("UiInitializeWizard('title_', 'title_en_', "),
          reason: 'המסייע מציג את כותרת המסייע שבעיצוב',
        );
        final load = _routine(script, 'function UiLoadArt(');
        final extract = load.indexOf('ExtractTemporaryFile(FileName);');
        expect(extract, greaterThanOrEqualTo(0));
        expect(
          load.lastIndexOf('if not FileExists(', extract),
          greaterThanOrEqualTo(0),
          reason: 'ב-250% התמונות כבר נשלפו עם קנה המידה של החלון',
        );
        expect(extract, lessThan(load.indexOf('Png.LoadFromFile(')));
        final first = _routine(script, 'procedure UiFirstTick()');
        expect(first, isNot(contains('book_')));
        expect(first, isNot(contains('title_')));

        // Stretch מקטין לגודל הפקד, ו-UiShowArt מגדיר את הפקד לגודל התמונה.
        for (final hero in const ['UiHeroBook', 'UiHeroTitle']) {
          expect(script, contains('$hero.Stretch := True;'));
          expect(script, isNot(contains('UiShowArt($hero')));
          expect(
            script,
            isNot(contains('$hero.Bitmap :=')),
            reason: 'רק UiHeroShow מציב תמונה, ומשחרר את העותק שלו',
          );
        }
        final shows = RegExp(
          r'UiHeroShow\((\w+),',
        ).allMatches(script).map((m) => m[1]!).toSet();
        expect(shows, {'UiHeroBook', 'UiHeroTitle'});
        expect(
          _routine(script, 'procedure UiHeroShow('),
          contains('Img.Bitmap := UiHeroImage(I);'),
        );
        for (final kind in const ['BOOK', 'TITLE']) {
          expect(
            script,
            matches(
              RegExp(
                'Px\\(\\{#AA_${kind}_W\\}\\),\\s*Px\\(\\{#AA_${kind}_H\\}\\)\\);',
              ),
            ),
            reason: 'גודל היעד של $kind',
          );
        }
      },
    );

    test(
      '$_assistant: הפתיחה מפענחת בזרימה, מחכה לתמונה חסרה ואינה מדלגת על פריים',
      () {
        final script = _script(_assistant);
        final animate = _routine(script, 'procedure UiAnimateHero(');
        final decode = _routine(script, 'procedure UiHeroDecodeNext(');

        // פענוח של תמונה בגודל המקור ארוך מפריים: לכל היותר אחד בכל פעימה,
        // כדי שהחלון לא ייתקע עד שכולן מוכנות.
        expect(
          RegExp(r'UiHeroDecodeNext\(\)').allMatches(animate),
          hasLength(1),
        );
        expect(RegExp(r'UiHeroImage\(').allMatches(decode), hasLength(1));
        for (final body in [animate, decode]) {
          expect(body, isNot(matches(RegExp(r'\b(for|while|repeat)\b'))));
        }
        expect(
          animate.indexOf(r'UiRedrawWindow(WizardForm.Handle, 0, 0, $180);'),
          allOf(
            greaterThanOrEqualTo(0),
            lessThan(animate.indexOf('UiHeroDecodeNext();')),
          ),
          reason: 'מה שהשתנה מצויר לפני הפענוח, ולא מתעכב בגללו',
        );

        // הספר הסגור מוצג מיד אחרי הפענוח הראשון, מאחורי שכבה בצבע הדף
        // שנעלמת בהדרגה — אין עמוד ריק בזמן ההמתנה.
        final shown = animate.indexOf('if UiHeroNext > 0 then');
        expect(shown, greaterThanOrEqualTo(0));
        expect(
          animate.indexOf('UiHeroShow(UiHeroBook, 0);'),
          greaterThan(shown),
        );
        expect(animate.indexOf('UiHeroSetVeil(255);'), greaterThan(shown));
        expect(
          animate,
          isNot(contains('UiHeroFade / ')),
          reason: "'/' בין שני שלמים הוא חילוק שלמים ב-Pascal Script",
        );
        final build = _routine(script, 'procedure UiBuildHero(');
        expect(
          build.indexOf('UiHeroVeil := UiImage(Page);'),
          greaterThan(build.indexOf('UiHeroBook := UiImage(Page);')),
          reason: 'השכבה נוצרת אחרי הספר ולכן מצוירת מעליו',
        );
        expect(
          _routine(script, 'procedure UiHeroSetVeil('),
          contains('Info.Height := 2;'),
          reason: 'המתיחה של Inno 6.7.3 נכשלת בתמונה בגובה שורה אחת',
        );

        // השעון מתקדם לכל היותר פריים אחד בפעימה, ונעצר כשהתמונה שהוא דורש
        // עוד לא פוענחה — פריים לעולם אינו מדולג.
        expect(
          animate,
          contains(
            'if Step > {#AA_BOOK_FRAME_MS} then\n'
            '    Step := {#AA_BOOK_FRAME_MS};',
          ),
        );
        final held = animate.indexOf(
          'UiHeroHeld := (I >= UiHeroNext) or (UiHeroHeld and not UiHeroCanRun(I));',
        );
        expect(held, greaterThanOrEqualTo(0));
        final advance = animate.indexOf('UiHeroT := T;');
        expect(advance, greaterThan(held));
        expect(
          animate.lastIndexOf('if not UiHeroHeld then', advance),
          greaterThan(held),
        );
        expect(
          build,
          contains('UiHeroHeld := True;'),
          reason: 'גם ההתחלה עוברת דרך UiHeroCanRun',
        );
        expect(
          _routine(
            script,
            'function UiHeroCanRun(',
          ).replaceAll(RegExp(r'\s+'), ' '),
          contains(
            'Result := (UiHeroNext >= GetArrayLength(UiHeroArt)) or '
            '((UiHeroNext > I + 1) and UiHeroDecodeFits(UiHeroFrameCost));',
          ),
          reason: 'מתחילים רק אם הפענוח לא יעצור את הניגון שוב',
        );
        expect(
          _routine(script, 'function UiHeroDecodeFits('),
          contains('<= UiHeroTickMs'),
          reason: 'פענוח מתבצע רק בפתיחה, ולכן נמדד מול הפעימה שלה',
        );

        // לחיצה, אנימציות כבויות ויציאה מהעמוד עוצרות את הפענוח ומשחררות
        // את מה שפוענח; העותק שהוצג משוחרר מיד כי הפקד מחזיק את שלו.
        expect(
          _routine(script, 'function UiOnMouseDown('),
          contains(
            'if not UiHeroDone and (UiPage = wpWelcome) then\n'
            '    UiHeroPlaceFinal();',
          ),
        );
        expect(
          build,
          contains(
            'if UiHeroDone or not UiAnimationsEnabled() then\n'
            '    UiHeroPlaceFinal();',
          ),
        );
        final last = _routine(script, 'procedure UiHeroPlaceFinal(');
        expect(last, contains('UiHeroRelease();'));
        expect(last, contains('UiHeroVeil.Visible := False;'));
        expect(
          _routine(script, 'procedure UiHeroRelease('),
          contains('UiHeroNext := GetArrayLength(UiHeroArt);'),
        );
        expect(
          animate,
          contains(
            'if UiHeroDone or (UiHeroNext >= GetArrayLength(UiHeroArt)) then\n'
            '    exit;',
          ),
        );
        expect(
          _routine(script, 'procedure UiHeroShow('),
          contains(
            'Img.Bitmap := UiHeroImage(I);\n'
            '  UiHeroArt[I].Free;\n'
            '  UiHeroArt[I] := nil;',
          ),
        );
        final page = _routine(script, 'procedure UiRenderPage(');
        final leave = page.indexOf(
          'if (PageID <> wpWelcome) and Assigned(UiHeroBook) and not UiHeroDone then',
        );
        expect(leave, greaterThanOrEqualTo(0));
        expect(page.indexOf('UiHeroRelease();', leave), greaterThan(leave));
      },
    );

    test(
      '$_assistant: הפתיחה מצוירת בחציצה ובקצב אחיד, והפעימה המהירה רק בזמנה',
      () {
        final script = _script(_assistant);

        // פריים חדש נמחק ונמתח (כ-10ms) לפני שהוא מצויר. WS_EX_COMPOSITED על
        // החלון הראשי, לבד או יחד עם המחברת, עוד הציג את השלב הריק.
        final composited = RegExp(
          r'UiSetWindowLong\(([\w.]+), -20,\s*'
          r'UiGetWindowLong\(\1, -20\) or \$02000000\);',
        ).allMatches(script).map((m) => m[1]).toList();
        expect(composited, ['WizardForm.OuterNotebook.Handle']);
        expect(RegExp(r'\$02000000').allMatches(script), hasLength(1));

        // SetTimer מעוגל לפעימת המערכת (15.6ms): ב-20ms הפעימה היא 31ms
        // ופריים של 42ms מתחלף אחרי 31 או 63. רק בפתיחה הטיימר מהיר יותר.
        expect(script, contains('UiTickMs = 20;'));
        expect(script, contains('UiHeroTickMs = 10;'));
        final pace = _routine(script, 'procedure UiPaceTimer(');
        expect(
          pace,
          contains(
            'if (UiPage = wpWelcome) and not UiHeroDone then\n'
            '    Ms := UiHeroTickMs\n'
            '  else\n'
            '    Ms := UiTickMs;',
          ),
          reason: 'אותו תנאי שבו UiAnimateHero מנגן',
        );
        expect(
          _routine(script, 'procedure UiAnimateHero('),
          contains('if UiHeroDone or (UiPage <> wpWelcome) then\n    exit;'),
        );
        final kill = pace.indexOf('UiKillTimer(0, UiTimerId);');
        expect(kill, greaterThan(pace.indexOf('if Ms = UiTickRate then')));
        expect(
          pace.indexOf('UiTimerId := UiSetTimer(0, 0, Ms, UiTickProc);'),
          greaterThan(kill),
        );

        // הקצב נבחר בכל פעימה אחרי הניגון, ולכן כל יציאה מהפתיחה — סוף,
        // לחיצה, אנימציות כבויות או עמוד אחר — מחזירה מיד את הקצב הרגיל.
        final tick = _routine(script, 'procedure UiTick(');
        expect(tick, contains('UiAnimateHero();\n      UiPaceTimer();'));
        final init = _routine(script, 'procedure UiInitializeWizard(');
        expect(
          init,
          contains(
            'UiTickProc := CreateCallback(@UiTick);\n'
            '  UiTickRate := UiTickMs;\n'
            '  UiTimerId := UiSetTimer(0, 0, UiTickRate, UiTickProc);',
          ),
        );
        expect(
          RegExp(r'UiSetTimer\(').allMatches(script),
          hasLength(3),
          reason: 'ההכרזה, היצירה וההחלפה ב-UiPaceTimer בלבד',
        );

        // מסך של 60Hz מציג ממילא 33/50ms; רזולוציית הטיימר של המערכת לא
        // מוגבהת בשביל הפתיחה.
        expect(script, isNot(contains('timeBeginPeriod')));
      },
    );

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
      // בעמוד ההורדה אלא ב-FetchToTemp — המקום היחיד שמוריד בלי hash.
      final fetch = _routine(script, 'procedure FetchToTemp(');
      expect(RegExp('DownloadTemporaryFile').allMatches(script).length, 1);
      expect(fetch, contains("DownloadTemporaryFile(Url, FileName, '', nil)"));
      final connectAdds = RegExp(r'ConnectPage\.Add\(').allMatches(script);
      expect(connectAdds, hasLength(1));
      expect(fetch, contains("ConnectPage.Add(Url, FileName, '')"));
      expect(
        RegExp(r'FetchToTemp\(').allMatches(script).length,
        3,
        reason: 'רק רשימת ה-release והמניפסט יורדים בלי hash',
      );
      expect(
        _routine(script, 'function FetchReleaseJson('),
        contains('FetchToTemp(Url, FileName)'),
      );
      expect(
        RegExp(r'FetchReleaseJson\(').allMatches(script).length,
        2,
        reason: 'FetchReleaseJson נקרא רק לרשימת ה-release',
      );
      expect(
        _routine(script, 'function LoadReleaseManifest('),
        contains("FetchToTemp(Url, 'manifest.json')"),
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

    test('$_assistant: הורדה שנכשלה חוזרת, וקטועה מדווחת כקטועה (#2079)', () {
      final run = _routine(_script(_assistant), 'function RunDownloads(');
      expect(
        run,
        contains(
          'until (Failure = \'\') or StopRequested or '
          '(Attempt > DownloadAttempts)',
        ),
      );
      expect(
        run.indexOf('DownloadPage.Download;'),
        lessThan(run.indexOf('until (Failure')),
        reason: 'ההורדה עצמה חייבת להיות בתוך הלולאה',
      );
      // Inno אינו משווה גודל כשמועבר hash: קטיעה מגיעה כ-hash שגוי.
      final hashFailure = run.indexOf(
        'Pos(SetupMessage(msgVerificationFileHashIncorrect), Failure)',
      );
      expect(hashFailure, greaterThanOrEqualTo(0));
      expect(
        run.indexOf("CustomMessage('ErrorDownloadIncomplete')"),
        greaterThan(hashFailure),
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
        progress.indexOf("CustomMessage('CheckingDownloadedFile')"),
        greaterThan(atMax),
        reason: 'Inno מחשב hash אחרי הבית האחרון בלי דיווח — הפס עומד על 100%',
      );
      // Inno כותב לתווית ההורדה גם את שם הקובץ; התצוגה קוראת את השורה שלנו.
      expect(progress, contains('DownloadStatus := Status;'));
      expect(
        _routine(script, 'function UiAdapterProgress('),
        contains('Bytes := DownloadStatus;'),
      );
      expect(
        _routine(script, 'function AppendFileTo('),
        contains('WorkPage.SetProgress('),
        reason: 'ההרכבה מדווחת התקדמות בבתים',
      );
    });

    test('$_assistant: היעד — כמו המחשב הזה, או רשימה אחת של כל יעד אחר', () {
      final script = _script(_assistant);
      final skip = _routine(script, 'function ShouldSkipPage(');
      final target = _routine(script, 'procedure UpdateTarget()');
      final wizard = _routine(script, 'procedure InitializeWizard()');
      final other = _routine(script, 'procedure FillOtherPage()');

      // עמוד אחד במקום פלטפורמה, ארכיטקטורה ופורמט — רק כשנבחר "סוג מחשב אחר".
      for (final page in const ['PlatformPage', 'ArchPage', 'FormatPage']) {
        expect(script, isNot(contains(page)), reason: page);
      }
      expect(skip, contains('if PageID = OtherPage.ID then'));
      expect(skip, contains('Result := IsThisComputerMode()'));
      expect(
        skip,
        isNot(contains('FolderPage')),
        reason: 'שני המצבים מורידים לתיקייה שנבחרה',
      );
      expect(
        wizard,
        contains('OtherPage := CreateInputOptionPage(ModePage.ID'),
      );
      expect(
        wizard,
        contains('PresetPage := CreateInputOptionPage(OtherPage.ID'),
      );

      // הרשימה נגזרת מהמניפסט באותם צירופים ש-DumpSelections בודק, בלי המחשב הזה.
      for (final call in const [
        'PlatformChoices()',
        'ArchitectureChoices(Platforms[P])',
        'PackageFormatChoices(Platforms[P], Archs[A])',
        'ComponentIsOffered(I)',
      ]) {
        expect(other, contains(call), reason: call);
      }
      expect(
        other,
        contains(
          "(Platforms[P] = 'windows') and (Archs[A] = RunningArchitecture())",
        ),
      );
      expect(
        _routine(script, 'function LoadManifestStep()'),
        contains('FillOtherPage();'),
      );

      // אין יעד "אחר" שמתאים לרוב המשתמשים: בלי בחירה מראש, ו"המשך" דורש בחירה.
      expect(script, isNot(contains('OtherPage.SelectedValueIndex :=')));
      expect(
        _routine(script, 'function NextButtonClick('),
        contains('if OtherPage.SelectedValueIndex < 0 then'),
      );

      expect(target, contains("TargetPlatform := 'windows';"));
      expect(target, contains('TargetArchitecture := RunningArchitecture();'));
      expect(target, contains('TargetPlatform := OtherPlatform[I];'));
      expect(
        _routine(script, 'function RunningArchitecture()'),
        contains('if IsArm64 then'),
      );
      expect(
        _routine(script, 'function ComponentIsOffered('),
        isNot(contains('IsThisComputerMode')),
        reason: 'כללי הבחירה זהים למימוש הייחוס בכל יעד, גם במחשב הזה',
      );

      final formats = _routine(script, 'function FormatDisplayName(');
      for (final MapEntry(key: key, value: label) in const {
        'FormatDeb': 'Ubuntu, Debian, Mint והפצות דומות (DEB)',
        'FormatRpm': 'Fedora, openSUSE והפצות דומות (RPM)',
        'FormatPortable': 'הפצה אחרת — ללא התקנה',
      }.entries) {
        expect(formats, contains("CustomMessage('$key')"));
        expect(_text(script, 'hebrew', key), label);
      }
      expect(
        _routine(script, 'function PrepareOutput()'),
        contains(
          'if IsThisComputerMode() and IsExecutableName(AssetName[A]) and',
        ),
        reason: 'מפעילים מתקין רק כשמתקינים במחשב הזה',
      );
    });

    test('$_assistant: שני המצבים מורידים לתיקייה, והמתקין רץ רק בלחיצה', () {
      final script = _script(_assistant);

      expect(
        _routine(script, 'function OutputBaseDir()'),
        isNot(contains('CacheDir')),
        reason: 'אין עוד מצב שבו הפלט הוא המטמון',
      );
      expect(
        _routine(script, 'function OutputDir()'),
        isNot(contains('IsThisComputerMode')),
      );
      final next = _routine(script, 'function NextButtonClick(');
      for (final run in const ['ShellExec', 'RunInstaller']) {
        expect(
          next,
          isNot(contains(run)),
          reason: 'המסייע אינו מפעיל מתקין מעצמו בסוף ההורדה',
        );
      }
      expect(
        _routine(script, 'procedure UiButtonClick(Sender: TObject);\nvar'),
        contains('if RunInstaller() then'),
      );
      final actions = _routine(script, 'function UiPlaceFinishActions(');
      expect(actions, contains("CustomMessage('InstallNow')"));
      expect(actions, contains("CustomMessage('OpenFolder')"));
      expect(_text(script, 'hebrew', 'InstallNow'), 'התקן עכשיו במחשב הזה');
      expect(_text(script, 'hebrew', 'OpenFolder'), 'פתח את תיקיית ההתקנה');
      expect(
        actions,
        contains("RunAfterExe <> ''"),
        reason: 'בלי מתקין אין כפתור התקנה',
      );
      expect(actions, contains('This := IsThisComputerMode();'));
      expect(
        _routine(script, 'procedure UiAdapterBuildFinish()'),
        contains('UiPlaceFinishActions(Page)'),
      );
      // ב"סוג מחשב אחר" נשארת תיבת "הצג" של עמוד הסיום.
      expect(
        _routine(script, 'procedure CurPageChanged('),
        contains("(RevealPath <> '') and not IsThisComputerMode()"),
      );
    });

    test('$_assistant: עצירה של המשתמש אינה מוצגת כתקלה', () {
      final script = _script(_assistant);
      final run = _routine(script, 'function RunDownloads()');
      final next = _routine(script, 'function NextButtonClick(');
      final failure = _routine(script, 'procedure ShowFailure(');
      final ui = _routine(script, 'procedure UiShowFailure(');

      // גם כפתור העצירה של Inno נספר כעצירה, לא כקובץ שאינו זמין.
      expect(run, contains('if DownloadPage.AbortedByUser then'));
      expect(run, contains('StopRequested := True;'));
      expect(run, isNot(contains('StopRequested := False')));
      final reset = next.indexOf('StopRequested := False;');
      expect(reset, greaterThanOrEqualTo(0));
      expect(
        reset,
        lessThan(next.indexOf('BuildQueue()')),
        reason: 'עצירה קודמת אינה הופכת כישלון מאוחר יותר לעצירה',
      );
      expect(next, contains('ShowFailure(RunStopped)'));
      expect(failure, contains('else if Stage = RunStopped then'));
      expect(
        failure.substring(failure.indexOf('Stage = RunStopped')),
        contains("CustomMessage('StoppedBody')"),
      );
      // ההסבר מצטט את הכפתור שמתחתיו, בכל שפה.
      for (final lang in const ['english', 'hebrew']) {
        expect(
          _text(script, lang, 'StoppedBody'),
          contains('"${_text(script, lang, 'Resume')}"'),
          reason: lang,
        );
        expect(
          _text(script, lang, 'RunFailedBody'),
          contains('"${_text(script, lang, 'Retry')}"'),
          reason: lang,
        );
      }
      expect(ui, contains('Stopped := Stage = RunStopped;'));
      expect(ui, contains("UiShowArt(UiErrBadge, 'badge_paused');"));
      expect(
        ui,
        contains('UiSetButton(UiBtnOpenPage, not Stopped'),
        reason: 'בעצירה אין מה לחפש בעמוד ההורדות',
      );
      expect(ui, contains("CustomMessage('Resume')"));
    });

    test('$_assistant: X ו"ביטול" שואלים תמיד בחלון המעוצב', () {
      final script = _script(_assistant);
      final click = _routine(
        script,
        'procedure UiButtonClick(Sender: TObject);\nvar',
      );

      // שאלת העצירה המובנית של Inno היא MsgBox מערכת: כפתור העצירה שלו לא נלחץ.
      expect(script, isNot(contains('AbortButton)')));
      expect(click, contains('UiBtnClose: UiRequestClose();'));
      expect(
        click,
        contains('if UiIsWindowEnabled(WizardForm.Handle) = 0 then'),
        reason: 'לחיצה בזמן דו-שיח פתוח הייתה פותחת שאלה שנייה מעליו',
      );
      final close = _routine(script, 'procedure UiRequestClose()');
      expect(close, contains('WizardForm.CancelButton.CanFocus'));
      expect(close, contains('UiAskExit()'));
      expect(close, contains('UiClosing := True;'));
      expect(close, contains('StopRequested := True;'));
      expect(
        _routine(script, 'procedure UiShowFailure('),
        contains('UiCloseIfRequested()'),
        reason: 'סגירה שאושרה באמצע שלב אינה מציגה אחריו עמוד שגיאה',
      );
      expect(
        _routine(script, 'function LoadManifestStep()'),
        contains('UiCloseIfRequested();'),
      );
      expect(
        script,
        contains('@OnConnectProgress);'),
        reason: 'בלי פונקציית התקדמות אי אפשר לעצור את החיבור בלי Inno',
      );
      expect(
        _routine(script, 'function OnConnectProgress('),
        contains('Result := not StopRequested;'),
      );
      expect(
        _routine(script, 'procedure FetchToTemp('),
        contains('if StopRequested then'),
        reason: 'אחרי ביטול לא מתחילה בקשה נוספת',
      );
    });

    test('$_assistant: בשאלה הרסנית Enter ו-Esc בוחרים בפעולה הבטוחה', () {
      final script = _script(_assistant);
      final ask = _routine(script, 'function UiAskDialog(');

      // כמו AppDialog.warning: הבטוחה מלאה וממוקדת, ההרסנית כפתור טקסט אדום.
      expect(ask, contains('UiDlgOk.Default := False;'));
      expect(ask, contains('UiDlgNo.Default := False;'));
      expect(ask, contains('UiDlgNo.Cancel := not NoCancel;'));
      expect(ask, contains('UiDlg.ActiveControl := UiButtons[UiBtnDlgNo].Img'));
      // במסייע Esc נשאר "לא": UiAsk לעולם אינו מבקש NoCancel.
      expect(
        _routine(script, 'function UiAsk('),
        contains('UiAskDialog(Title, Text, Yes, No, Danger, False)'),
      );
      final flat = script.replaceAll(RegExp(r'\s+'), ' ');
      for (final pair in const [
        ('ExitYes', 'ExitNo'),
        ('ConnectStopYes', 'ConnectStopNo'),
        ('StopYes', 'StopNo'),
      ]) {
        expect(
          flat,
          contains(
            "CustomMessage('${pair.$1}'), CustomMessage('${pair.$2}'), True)",
          ),
        );
      }
      expect(_text(script, 'hebrew', 'ExitYes'), 'יציאה');
      expect(_text(script, 'hebrew', 'StopNo'), 'המשך להוריד');
    });

    test('$_assistant: הגרסה שתורד מוצגת מ-releaseVersion ולא מהתג', () {
      final script = _script(_assistant);
      final label = _routine(script, 'function OtzariaVersionLabel()');

      expect(
        label,
        contains("Msg1('OtzariaVersion', LtrUnit(ReleaseVersion))"),
      );
      expect(_text(script, 'hebrew', 'OtzariaVersion'), 'אוצריא %1');
      expect(_text(script, 'english', 'OtzariaVersion'), 'Otzaria %1');
      expect(label, contains("if ReleaseVersion <> '' then"));
      for (final tag in const ['PinnedTag', 'AssistantReleaseTag']) {
        expect(label, isNot(contains(tag)), reason: 'בתג יש ‎+build');
      }
      final show = _routine(script, 'procedure ShowReleaseVersion()');
      expect(show, contains("if ReleaseVersion = '' then"));
      expect(show, contains('ModePage.SubCaptionLabel.Caption :='));
      expect(show, contains('DownloadPage.Caption :='));
      expect(
        _routine(script, 'function LoadManifestStep()'),
        contains('ShowReleaseVersion();'),
        reason: 'לפני שהמניפסט נטען הגרסה אינה ידועה',
      );
      const row =
          "UiAddRow('preset_update', CustomMessage('RowVersion'), OtzariaVersionLabel(), False);";
      expect(_routine(script, 'procedure UiBuildReady()'), contains(row));
      expect(
        _routine(script, 'procedure UiAdapterBuildFinish()'),
        contains(row),
      );
      expect(
        _routine(script, 'procedure UiAddRow('),
        contains("if Value = '' then"),
        reason: 'גרסה לא ידועה — בלי שורה ריקה',
      );
    });

    test('$_assistant: לכל הצעה אייקון משלה, ונדרש עיצוב שיש בו אותו', () {
      final script = _script(_assistant);
      final icon = _routine(script, 'function UiOptionIcon(');
      expect(icon, contains('(DisplayRank(PresetId[Index]) > 0)'));
      expect(icon, contains("StringChangeEx(Value, '-', '_', True);"));
      expect(icon, contains("Result := 'preset_' + Value;"));
      // full-indexed → preset_full_indexed, שנוסף בעיצוב 1.4.0.
      expect(
        script,
        contains(
          '#if Pos(",preset_full_indexed,", "," + AA_ICON_NAMES + ",") == 0',
        ),
      );
      expect(
        _text(script, 'hebrew', 'PresetFullIndexed'),
        'התקנה מלאה + אינדקס חיפוש',
      );
      expect(
        _text(script, 'english', 'PresetFullIndexed'),
        'Full installation + search index',
      );
    });

    test('$_assistant: החלון נשאר כולו בתוך אזור העבודה', () {
      final script = _script(_assistant);
      final keep = _routine(script, 'procedure UiKeepOnScreen()');

      expect(
        keep,
        contains('UiMonitorFromWindow(WizardForm.Handle, 2)'),
        reason: 'אזור העבודה של המסך שעליו החלון, לא רק של הראשי',
      );
      expect(keep, contains('Info.Work.Bottom'));
      expect(
        keep,
        contains('UiIsIconic(WizardForm.Handle)'),
        reason: 'חלון ממוזער יושב ב-‎-32000‎ בכוונה',
      );
      expect(
        keep,
        contains(r'(UiGetAsyncKeyState(1) and $8000) <> 0'),
        reason: 'לא נלחמים בגרירה',
      );
      expect(
        _routine(script, 'procedure UiTick('),
        contains('UiKeepOnScreen();'),
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

    test('$_assistant: רשימת היעדים אינה מפנה להפצה הניידת', () {
      final script = _script(_assistant);
      final wizard = _routine(script, 'procedure InitializeWizard()');
      final other = wizard.substring(wizard.indexOf('OtherPage :='));
      expect(
        other.substring(0, other.indexOf(');')),
        contains("CustomMessage('OtherHint')"),
      );
      expect(_text(script, 'hebrew', 'OtherHint'), contains('בחר DEB'));
      expect(
        _text(script, 'hebrew', 'OtherHint'),
        isNot(contains('הפצה אחרת')),
      );
      expect(_text(script, 'english', 'OtherHint'), contains('choose DEB'));
      expect(
        _text(script, 'english', 'OtherHint'),
        isNot(contains(_text(script, 'english', 'FormatPortable'))),
      );
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
      // אחרי טעינה שהצליחה התג אינו נקבע שוב, גם בחזרה למסך הפתיחה.
      final script = _script(_assistant);
      final next = _routine(script, 'function NextButtonClick(');
      final welcome = next.substring(
        next.indexOf('if CurPageID = wpWelcome then'),
      );
      expect(
        welcome.substring(0, welcome.indexOf('exit;')),
        contains('if not ManifestLoaded then'),
      );
      expect(
        RegExp(r'LoadReleaseManifest\(\)').allMatches(script).length,
        3,
        reason: 'ההגדרה, שלב הטעינה, ומסלול הפיתוח DevSelectionDump בלבד',
      );
      expect(
        _routine(script, 'function LoadManifestStep()'),
        contains('ManifestLoaded := LoadReleaseManifest();'),
      );
    });

    test('$_assistant: מניפסט חסר או פגום אינו מפיל ואינו מוריד ללא אימות', () {
      final script = _script(_assistant);
      final step = _routine(script, 'function LoadManifestStep()');
      final failure = _routine(script, 'procedure ShowFailure(');

      expect(step, contains('Result := ManifestLoaded;'));
      expect(step, contains('ShowFailure(FailureLoad);'));
      expect(
        step,
        isNot(contains('DownloadPage')),
        reason: 'בלי מניפסט אין hash — ולכן אין הורדה',
      );
      // הכישלון נשאר במסך הפתיחה: "הבא" מחזיר False.
      expect(
        _routine(script, 'function NextButtonClick('),
        contains('Result := LoadManifestStep();'),
      );
      expect(failure, contains('LoadErrorMsg'));
      expect(
        _routine(script, 'procedure OpenDownloadsPage()'),
        contains('https://github.com/Otzaria/otzaria/releases/latest'),
        reason: 'הנסיגה היחידה היא הפניית המשתמש לעמוד ההורדות',
      );
      expect(
        _routine(script, 'procedure UiButtonClick(Sender: TObject);\nvar'),
        contains('UiBtnOpenPage: OpenDownloadsPage();'),
      );
    });

    test('$_assistant: InitializeSetup אינו פונה לרשת — החלון מופיע מיד', () {
      final init = _routine(_script(_assistant), 'function InitializeSetup()');
      // מסלול הפיתוח DevSelectionDump יוצא בלי חלון, ולכן מותר לו לטעון.
      final start = init.indexOf('#ifdef DevSelectionDump');
      final outside = start < 0
          ? init
          : init.substring(0, start) +
                init.substring(init.indexOf('#endif', start));
      for (final network in const [
        'LoadReleaseManifest',
        'LoadManifestStep',
        'FetchToTemp',
        'FetchReleaseJson',
        'DownloadTemporaryFile',
        'DownloadPage',
        'ConnectPage',
      ]) {
        expect(outside, isNot(contains(network)), reason: network);
      }
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

    test(
      '$_assistant: אין שורה מוזחת שמתחילה ב-[ — Inno קורא אותה ככותרת מקטע',
      () {
        final offenders = [
          for (final line in _script(_assistant).split('\n'))
            if (RegExp(r'^\s+\[').hasMatch(line)) line.trim(),
        ];
        expect(offenders, isEmpty, reason: offenders.join('\n'));
      },
    );

    test('$_assistant: אנגלית ועברית — לפי שפת הממשק של Windows, בלי שאלה', () {
      final script = _script(_assistant);
      final languages = RegExp(
        r'^Name:\s*"(\w+)";\s*MessagesFile:\s*"([^"]+)"',
        multiLine: true,
      ).allMatches(_section(script, 'Languages')).map((m) => '${m[1]}|${m[2]}');
      // הראשונה היא הנסיגה של Inno לכל שפת ממשק שאין לה התאמה.
      expect(languages, [
        'english|compiler:Default.isl',
        r'hebrew|compiler:Languages\Hebrew.isl',
      ]);
      expect(script, contains('LanguageDetectionMethod=uilanguage'));
      expect(script, contains('ShowLanguageDialog=no'));
      expect(script, contains('AppName={cm:AppTitle}'));
      expect(
        _routine(script, 'function EnglishUi()'),
        contains("Result := ActiveLanguage() = 'english';"),
      );
    });

    test('$_assistant: כל טקסט קיים בשתי השפות, וכל קריאה מוצאת אותו', () {
      final script = _script(_assistant);
      for (final section in const ['CustomMessages', 'Messages']) {
        final byLang = _messages(script, section);
        expect(
          byLang.keys.toSet(),
          section == 'CustomMessages'
              ? {'', 'english', 'hebrew'}
              : {'english', 'hebrew'},
        );
        expect(
          byLang['english']!.keys.toSet(),
          byLang['hebrew']!.keys.toSet(),
          reason: '[$section]: מפתח שחסר באחת השפות',
        );
        for (final MapEntry(key: lang, value: entries) in byLang.entries) {
          for (final MapEntry(key: key, value: value) in entries.entries) {
            expect(value.trim(), isNotEmpty, reason: '$lang.$key');
          }
        }
      }
      // מפתח בלי שפה רק לשם החוזה המשותף, שאינו מוצג.
      expect(
        _messages(script, 'CustomMessages')['']!.keys,
        ['ContractSubfolder'],
      );
      final hebrew = RegExp(r'[֐-׿]');
      for (final MapEntry(key: key, value: value) in _messages(
        script,
        'CustomMessages',
      )['english']!.entries) {
        expect(value, isNot(matches(hebrew)), reason: 'english.$key בעברית');
      }
      final used = {
        for (final m in RegExp(
          r"(?:CustomMessage\('|Msg1\('|\{cm:)(\w+)",
        ).allMatches(script))
          m[1]!,
      };
      final defined = {
        for (final entries in _messages(script, 'CustomMessages').values)
          ...entries.keys,
      };
      expect(used.difference(defined), isEmpty, reason: 'טקסט שאינו מוגדר');
      expect(
        defined.difference(used),
        isEmpty,
        reason: 'טקסט מוגדר שאיש אינו מציג',
      );
    });

    test(
      '$_assistant: אין טקסט גלוי מילולי ב-[Code] — רק דרך CustomMessage',
      () {
        final script = _script(_assistant);
        final hebrew = RegExp(r'[֐-׿]');
        final words = RegExp(r'[A-Za-z]{2,}\s+[A-Za-z]{2,}');
        // מותר: הלוג, הפרטים הטכניים (באנגלית בכל שפה, להעתקה), DLL וגופנים.
        const technical = [
          'Log(',
          'LoadErrorTech :=',
          "external '",
          'RaiseException(',
          'Font.Name :=',
        ];
        final literals = _codeLiterals(script);
        expect(
          literals.length,
          greaterThan(100),
          reason: 'הסורק לא מצא מחרוזות',
        );
        final offenders = [
          for (final (:literal, :statement) in literals)
            if (hebrew.hasMatch(literal) ||
                (words.hasMatch(literal) && !technical.any(statement.contains)))
              literal,
        ];
        expect(offenders, isEmpty, reason: offenders.join('\n'));
      },
    );

    test('$_assistant: טקסטי הרכיבים באנגלית מהמניפסט, עם נסיגה לעברית', () {
      final script = _script(_assistant);
      final text = _routine(script, 'function ComponentText(');
      expect(text, contains("JStr(Raw, ObjPos, Key + 'En')"));
      expect(text, contains("if Result = '' then"));
      final parse = _routine(script, 'function ParseManifest(');
      expect(
        parse,
        contains(
          "CompName[NC] := ComponentText(Raw, CompPos, 'name', EnglishUi());",
        ),
      );
      expect(
        parse,
        contains(
          "CompDesc[NC] := ComponentText(Raw, CompPos, 'description', EnglishUi());",
        ),
      );
      expect(parse, contains("JStr(Raw, CompPos, 'outputNoteEn')"));
      // השם העברי חובה בחוזה, גם כשהממשק באנגלית.
      expect(parse, contains("(JStr(Raw, CompPos, 'name') = '')"));
      // plannedOutputNotes(english:) — הכפולים מוסרים לפי הטקסט שמוצג.
      final notes = _routine(script, 'function PlannedOutputNotes(');
      expect(
        notes,
        contains("if English and (CompOutputNoteEn[C] <> '') then"),
      );
      expect(notes, contains('ListIndex(Result, Note) < 0'));
      expect(
        _routine(script, 'function PrepareOutput()'),
        contains('PlannedOutputNotes(EnglishUi())'),
      );
    });

    test('$_assistant: באנגלית הפריסה משוקפת, ובעברית היא כפי שהייתה', () {
      final script = _script(_assistant);
      expect(
        _routine(script, 'function UiX('),
        contains(
          'if UiRtl then\n    Result := X\n  else\n    Result := Total - X - W;',
        ),
      );
      expect(
        _routine(script, 'procedure UiPrepare('),
        contains('UiRtl := not EnglishUi();'),
      );
      // הכיוון נקבע לפני שהכותרת של הפתיחה נבחרת לפיו.
      final init = _routine(script, 'procedure UiInitializeWizard(');
      expect(init.indexOf('UiPrepare();'), greaterThanOrEqualTo(0));
      expect(
        init.indexOf('UiPrepare();'),
        lessThan(init.indexOf('#ifdef AA_TITLE_EN')),
      );
      // שורת הכותרת: הכותרת בצד שבו הקריאה מתחילה, הכפתורים בצד השני.
      final chrome = _routine(script, 'procedure UiBuildChrome(');
      for (final button in const ['UiBtnClose', 'UiBtnMin']) {
        expect(chrome, contains('UiButtons[$button].Img.Left := UiX('));
      }
      final footer = chrome.replaceAll(RegExp(r'\s+'), ' ');
      for (final button in const [
        "UiBtnNext, UiFooter, 'btn_primary'",
        "UiBtnAbort, UiFooter, 'btn_tonal'",
        "UiBtnBack, UiFooter, 'btn_ghost'",
      ]) {
        expect(footer, contains('UiMakeButton($button, UiX('));
      }
      // ההתקדמות מתמלאת בכיוון הקריאה.
      final bar = _routine(script, 'procedure UiRenderBar(');
      expect(
        bar,
        contains("UiDrawHSlices(Bmp.Canvas, 'bar_fill', UiX(W - FillW"),
      );
      expect(bar, contains('if UiRtl then\n      X := W - X - FillW;'));
      // יישור טקסט מצויר לפי הכיוון, וקריאה מימין רק לטקסט עברי או לממשק עברי.
      expect(_routine(script, 'function UiAlign()'), contains('DT_RIGHT'));
      expect(
        _routine(script, 'function UiReading('),
        contains('if UiRtl or UiHasHebrew(S) then'),
      );
      expect(script, isNot(contains('UiRtlFlags')));
      // יחידות עטופות ב-LRE…PDF רק בתוך טקסט עברי.
      expect(
        _routine(script, 'function LtrUnit('),
        contains('if not EnglishUi() then'),
      );
    });

    test('$_assistant: אין שורה שמתחילה ב-# שאינו דירקטיבה', () {
      // ISPP מפרש # בתחילת שורה גם אחרי הזחה — קבוע כמו #13#10 שנדחף
      // לראש שורה שובר את הקומפילציה, והקובץ אינו נבנה בטסטים.
      final offenders = <String>[];
      final lines = _script(_assistant).split('\n');
      final directive = RegExp(
        r'^\s*#(ifndef|ifdef|if|else|endif|define|include|error)\b',
      );
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

  group('המתקינים בשכבת התצוגה של אוצריא', () {
    const adapter = 'otzaria_ui_installer.iss';
    const core = 'otzaria_ui_core.iss';

    /// הסקריפט המורחב בלי הליבה: הקוד שהמתקינים עצמם מוסיפים.
    String installerCode(String name) =>
        _script(name).replaceFirst(_expandIncludes(_read(core)), '');

    /// שם השגרה שבתוכה נמצא [offset] בטקסט.
    String enclosingRoutine(String text, int offset) {
      final starts = RegExp(
        r'^(?:procedure|function) (\w+)',
        multiLine: true,
      ).allMatches(text.substring(0, offset)).toList();
      return starts.isEmpty ? '' : starts.last[1]!;
    }

    for (final name in _scripts) {
      test('$name: העיצוב ראשון ב-[Files], והליבה לפני [Code]', () {
        final raw = _read(name);
        final product = raw.indexOf('#define OtzariaUiProduct "installer"');
        final art = raw.indexOf('#include "otzaria_ui_art.iss"');
        final coreAt = raw.indexOf('#include "otzaria_ui_core.iss"');
        expect(product, greaterThanOrEqualTo(0));
        expect(art, greaterThan(product));
        expect(
          art,
          lessThan(raw.indexOf(RegExp(r'^\[Files\]', multiLine: true))),
          reason: 'עם SolidCompression תמונה מאוחרת ממתינה לפריסת האפליקציה',
        );
        expect(
          coreAt,
          lessThan(raw.indexOf(RegExp(r'^\[Code\]', multiLine: true))),
        );
        expect(raw, contains('#include "$adapter"'));

        final sources = [
          for (final files in _sections(_script(name), 'Files'))
            ...RegExp(
              r'^Source:\s*"([^"]+)"',
              multiLine: true,
            ).allMatches(files).map((m) => m[1]!),
        ];
        final firstOther = sources.indexWhere(
          (s) => !s.startsWith(r'assistant_art\'),
        );
        expect(firstOther, greaterThan(0));
        expect(
          sources.skip(firstOther).where((s) => s.startsWith('assistant_art')),
          isEmpty,
        );
        expect(
          sources.where((s) => s.toLowerCase().endsWith('.bmp')),
          isEmpty,
          reason: 'דף "תכונות עיקריות" והמצגת הוסרו',
        );
        // חלון ההסרה אינו מקבל את העיצוב, ולכן נשארת לו התמונה הקטנה.
        expect(
          _script(name),
          matches(RegExp(r'^WizardImageFile=\s*$', multiLine: true)),
        );
        expect(
          _script(name),
          contains('WizardSmallImageFile=wizard_small.bmp'),
        );
        expect(_script(name), contains('DisableWelcomePage=no'));
      });

      test(
        '$name: אנגלית ועברית לפי שפת Windows, ושמות התוכנה אינם מתורגמים',
        () {
          final script = _script(name);
          final languages =
              RegExp(
                    r'^Name:\s*"(\w+)";\s*MessagesFile:\s*"([^"]+)"',
                    multiLine: true,
                  )
                  .allMatches(_section(script, 'Languages'))
                  .map((m) => '${m[1]}|${m[2]}');
          expect(languages, [
            'english|compiler:Default.isl',
            r'hebrew|compiler:Languages\Hebrew.isl',
          ]);
          expect(script, contains('LanguageDetectionMethod=uilanguage'));
          expect(script, contains('ShowLanguageDialog=no'));
          // שדרוג בממשק אנגלי חייב למצוא את אותה רשומה, קבוצה וקיצורים.
          expect(script, contains('#define MyAppName "אוצריא"'));
          expect(script, contains('AppName={#MyAppName}'));
          expect(script, contains('DefaultGroupName={#MyAppName}'));
          for (final section in [
            'Icons',
            'Registry',
            'InstallDelete',
            'Dirs',
            'INI',
          ]) {
            expect(
              _section(script, section),
              isNot(contains('{cm:')),
              reason: section,
            );
          }
          final icons = [
            for (final m in RegExp(
              r'^Name:\s*"([^"]+)"',
              multiLine: true,
            ).allMatches(_section(script, 'Icons')))
              m[1]!,
          ];
          expect(icons, [
            r'{autoprograms}\{#MyAppName}',
            r'{autodesktop}\{#MyAppName}',
            r'{autodesktop}\לוח שנה - {#MyAppName}',
          ]);
        },
      );

      test('$name: כל טקסט בשתי השפות, וכל מפתח מוגדר בשימוש', () {
        final script = _script(name);
        final byLang = _messages(script, 'CustomMessages');
        expect(byLang.keys.toSet(), {'english', 'hebrew'});
        expect(
          byLang['english']!.keys.toSet(),
          byLang['hebrew']!.keys.toSet(),
          reason: 'מפתח שחסר באחת השפות',
        );
        final hebrew = RegExp(r'[֐-׿]');
        for (final MapEntry(key: key, value: value)
            in byLang['english']!.entries) {
          expect(value, isNot(matches(hebrew)), reason: 'english.$key בעברית');
        }
        final used = {
          for (final m in RegExp(
            r"(?:CustomMessage\('|Msg1\('|\{cm:)(\w+)",
          ).allMatches(script))
            m[1]!,
        };
        final defined = {for (final e in byLang.values) ...e.keys};
        // CreateDesktopIcon ו-AdditionalIcons מגיעים מקובצי השפה של Inno.
        expect(
          used.difference(defined),
          {'CreateDesktopIcon', 'AdditionalIcons'},
        );
      });

      test('$name: אין טקסט עברי מילולי בקוד — רק דרך CustomMessage', () {
        final hebrew = RegExp(r'[֐-׿]');
        // נתיבים ושמות קבצים ישנים בעברית הם נתונים, לא טקסט מוצג.
        const allowed = [
          r'C:\אוצריא',
          r'{localappdata}\אוצריא',
          'תלמוד בבלי',
          r'{autopf}\אוצריא',
        ];
        final offenders = [
          for (final l in _codeLiterals(_script(name)))
            if (hebrew.hasMatch(l.literal) &&
                !allowed.any((a) => l.literal.contains(a)))
              l.literal,
        ];
        expect(offenders, isEmpty, reason: offenders.join('\n'));
      });

      test('$name: התקנה שקטה אינה מציגה שום חלון חדש', () {
        final script = _script(name);
        // /VERYSILENT — בלי שכבת התצוגה כלל; /SILENT — חלון ההתקדמות המצומצם.
        final init = _routine(
          script,
          'procedure UiInstallerInitializeWizard()',
        );
        final silent = init.indexOf('if WizardSilent then');
        final very = init.indexOf("CmdLineParamExists('/VERYSILENT')");
        final compact = init.indexOf('UiInitializeCompact(');
        final full = init.indexOf('UiInitializeWizard(');
        expect(silent, greaterThan(0));
        expect(very, greaterThan(silent));
        expect(init.substring(very, compact), contains('exit;'));
        expect(full, greaterThan(compact));
        expect(init.substring(compact, full), contains('exit;'));

        // כל MsgBox של המתקין יושב בענף השקט של העוזרים — בשקט בדיוק הקריאה שהייתה.
        const helpers = {
          'InstTell',
          'InstAskYesNo',
          'InstAskYesNoSuppressible',
          'InstTellSuppressible',
          'InstReportFailure',
          'InstReportLibraryFailure',
          'InitializeUninstall',
        };
        final code = installerCode(name);
        for (final m in RegExp(
          r'\b(?:Suppressible)?MsgBox\(',
        ).allMatches(code)) {
          final routine = enclosingRoutine(code, m.start);
          if (routine.isEmpty) continue;
          expect(helpers, contains(routine), reason: 'MsgBox בתוך $routine');
        }
        // הענף שאחרי "if WizardSilent then" הוא ה-MsgBox עצמו, ולא הדו-שיח המעוצב.
        final silentBranch = RegExp(
          r'if WizardSilent(?: or [^\n]*)? then\n\s*(?:Result := )?'
          r'(?:Suppressible)?MsgBox\(',
        );
        for (final signature in [
          'procedure InstTell(',
          'function InstAskYesNo(',
          'function InstAskYesNoSuppressible(',
          'procedure InstTellSuppressible(',
          'procedure InstReportFailure(',
          'procedure InstReportLibraryFailure(',
        ]) {
          final body = _routine(script, signature);
          expect(body, matches(silentBranch), reason: signature);
          expect(body, isNot(contains('not WizardSilent')), reason: signature);
        }
      });

      test('$name: כל דו-שיח מעוצב שמור מאחורי not WizardSilent', () {
        final code = installerCode(name);
        for (final m in RegExp(
          r'\bUi(?:Ask|AskDialog|Tell|AskExit)\(',
        ).allMatches(code)) {
          final routineStart = code.lastIndexOf(
            RegExp(r'^(?:procedure|function) ', multiLine: true),
            m.start,
          );
          final before = code.substring(routineStart, m.start);
          expect(
            before,
            contains('WizardSilent'),
            reason:
                'UiAsk אינו MsgBox ואינו מושפע מ-/SUPPRESSMSGBOXES: '
                '${code.substring(routineStart, routineStart + 60)}',
          );
        }
      });

      test('$name: המתאם מממש את כל חוזה המתאם שהליבה מצהירה', () {
        final coreText = _read(core);
        final forwards = RegExp(
          r'^(procedure|function) (\w+)\(',
          multiLine: true,
        ).allMatches(coreText).where((m) => _isForward(coreText, m.start));
        final script = _script(name);
        for (final m in forwards) {
          _routine(script, '${m[1]} ${m[2]}(');
        }
      });

      test('$name: קוד ההסרה זהה בשני המתקינים', () {
        // AppId משותף: המסיר מריץ את [Code] של ההתקנה האחרונה, רגילה או FULL.
        for (final signature in [
          'function InitializeUninstall(',
          'procedure CurUninstallStepChanged(',
          'procedure DeleteAllUserData(',
        ]) {
          expect(
            _routine(_script(_regular), signature),
            _routine(_script(_full), signature),
            reason: signature,
          );
        }
        final ask = _routine(_script(name), 'function InitializeUninstall(');
        expect(ask, contains('MB_YESNO or MB_DEFBUTTON2) = IDYES'));
        expect(ask, isNot(contains('UiAsk')));
        final script = _script(name);
        expect(
          _text(script, 'hebrew', 'UninstallDeleteIntro'),
          startsWith('האם למחוק גם את הספרים וכל הנתונים של אוצריא?'),
        );
        expect(
          _messages(script, 'Messages')['english']!['ConfirmUninstall'],
          contains('Otzaria'),
        );
      });
    }

    test('כל טקסט שמוגדר למתקינים מוצג באחד מהם', () {
      final used = <String>{};
      final defined = <String>{};
      for (final name in _scripts) {
        final script = _script(name);
        used.addAll([
          for (final m in RegExp(
            r"(?:CustomMessage\('|Msg1\('|\{cm:)(\w+)",
          ).allMatches(script))
            m[1]!,
        ]);
        for (final e in _messages(script, 'CustomMessages').values) {
          defined.addAll(e.keys);
        }
      }
      expect(defined.difference(used), isEmpty, reason: 'טקסט שאיש אינו מציג');
    });

    test('המתקין המלא מגדיר InstallerFull לפני שכבת התצוגה, והרגיל לא', () {
      final full = _read(_full);
      expect(
        full.indexOf('#define InstallerFull'),
        lessThan(full.indexOf('#include "otzaria_ui_art.iss"')),
      );
      expect(_read(_regular), isNot(contains('InstallerFull')));
      final art = _read('otzaria_ui_art.iss');
      expect(
        art,
        contains('#if !Defined(AA_TITLE_INST) || !Defined(AA_LOGO_SM_SIZE)'),
      );
      expect(
        art.substring(art.indexOf('#if OtzariaUiProduct == "installer"')),
        matches(RegExp(r'^\s*#error ', multiLine: true)),
      );
      expect(art, contains('#define UiTitleFiles "title_inst_*"'));
      final ui = _read(adapter);
      expect(ui, contains('#ifdef InstallerFull'));
      // המתקין המאונדקס הנפרד בוטל (#1890): גם לא עמוד הורדה משלו בשכבה.
      expect(ui, isNot(contains('IndexedSplitFull')));
    });

    test('חלון /SILENT המצומצם: בלי פתיחה, שלבים וכפתורים', () {
      final coreText = _read(core);
      final compact = _routine(coreText, 'procedure UiInitializeCompact(');
      expect(compact, contains('UiHeight := UiCompactHeight;'));
      expect(compact, contains('UiHeroDone := True;'));
      final render = _routine(coreText, 'procedure UiRenderPage(');
      expect(
        render.indexOf('if UiCompact then'),
        lessThan(render.indexOf('UiBuildHero()')),
      );
      expect(
        _routine(coreText, 'procedure UiRenderSteps('),
        contains('if UiCompact then'),
      );
      expect(
        _routine(coreText, 'procedure UiSyncFooter('),
        contains('if UiCompact then'),
      );
      expect(coreText, contains('UiCompactHeight = 260;'));
    });

    test('חלון /SILENT: העיצוב נשלף לפני ההתקנה, בתבנית מעוגנת', () {
      final coreText = _read(core);
      final compact = _routine(coreText, 'procedure UiInitializeCompact(');
      // בפעימה הראשונה השליפה הייתה עלולה ליפול בתוך חילוץ של Inno (reentrancy).
      expect(
        compact.indexOf('UiExtractArt()'),
        greaterThan(compact.indexOf('UiInitializeWizard(')),
      );
      expect(
        compact.indexOf('UiBuildCompact()'),
        greaterThan(compact.indexOf('UiExtractArt()')),
        reason: 'בלי הלוח החלון מוצג לרגע עם הפקדים של Inno',
      );
      final extract = _routine(coreText, 'procedure UiExtractArt(');
      expect(extract, contains('if UiArtExtracted then'));
      expect(
        extract,
        contains(
          r"ExtractTemporaryFiles('{tmp}\*_' + IntToStr(UiScale) + '.png')",
        ),
      );
      expect(
        RegExp(r'ExtractTemporaryFiles\(').allMatches(coreText).length,
        1,
        reason: 'שליפה אחת, דרך UiExtractArt',
      );
      expect(
        _routine(coreText, 'procedure UiFirstTick('),
        contains('UiExtractArt()'),
      );
      expect(
        _routine(coreText, 'function UiLoadArt('),
        contains('and not UiCompact then'),
        reason: 'במצומצם אין שליפה עצלה באמצע ההתקנה',
      );
    });

    test('Inno Setup נעוץ ל-6.7.1 ב-CI, ו-7 נעצר בקומפילציה', () {
      final art = _read('otzaria_ui_art.iss');
      expect(art, contains('#if VER < EncodeVer(6, 7, 1)'));
      expect(
        art.substring(art.indexOf('#if VER >= EncodeVer(7, 0, 0)')),
        matches(RegExp(r'^#if VER >= EncodeVer\(7, 0, 0\)\n\s*#error ')),
      );
      expect(
        File('installer/install_inno_setup.ps1').readAsStringSync(),
        contains('choco upgrade innosetup --version 6.7.1 --allow-downgrade'),
      );
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync();
      final installs = RegExp(
        r'^.*(?:choco (?:install|upgrade) innosetup|winget install[^\n]*InnoSetup).*$',
        multiLine: true,
      ).allMatches(workflow).toList();
      expect(installs, isNotEmpty);
      for (final m in installs) {
        expect(m[0], contains('--version 6.7.1'), reason: m[0]);
      }
      expect(workflow, isNot(contains(r'\Inno Setup*\ISCC.exe')));
    });

    test('$_regular: הודעות חלקי הספרייה — בעברית הנוסח של dev מילה במילה', () {
      // בשקט (העדכון מהתוכנה) מוצגת ההודעה עצמה, ולכן הנוסח העברי לא השתנה.
      final script = _script(_regular);
      const restart =
          'הכינו את התיקייה מחדש במסייע ההורדה, או העבירו את המתקין לתיקייה '
          'אחרת כדי להתקין את התוכנה בלבד.';
      const expected = {
        'LibraryWhat': 'הספרייה',
        'IndexWhat': 'אינדקס החיפוש',
        'LibraryManifestInvalid':
            'קובץ רשימת החלקים של %1 שבתוך המתקין אינו תקין.',
        'LibraryPartsMissing':
            'בתיקייה של המתקין חסרים חלקים של %1.%n%n$restart',
        'LibraryPartsCorrupt':
            'אימות החלקים של %1 נכשל: אחד הקבצים פגום, '
            'או שאין מספיק מקום פנוי בדיסק.%n%n$restart',
        'LibraryPartsArmWin10':
            'פריסת הספרייה מהחלקים שליד המתקין דורשת Windows 11 במחשב ARM.%n%n'
            'העבירו את המתקין לתיקייה אחרת כדי להתקין את התוכנה בלבד.',
        'UnsafeLibraryRoot':
            'לא ניתן לקבוע תיקיית ספרייה בטוחה ויחידה. '
            'אין להתקין ספרייה בשורש כונן או שיתוף, או בנתיב יחסי. '
            'עדכנו תחילה את התוכנה בלבד מתיקייה ללא קובצי ספרייה, '
            'בחרו בה את הספרייה הפעילה, ואז הפעילו שוב את המתקין.',
        'OtherVersionParts':
            'לצד המתקין יש קובצי ספרייה של גרסה אחרת של אוצריא, '
            'ולכן הם לא יותקנו:%n%1%n%n'
            'כדי להתקין גם את הספרייה, הכינו את התיקייה מחדש במסייע ההורדה.%n%n'
            'להמשיך ולהתקין את התוכנה בלבד?',
        'LibraryPrepTitle': 'מכין את הספרייה',
        'LibraryPrepDesc':
            'בודק את חלקי הספרייה שליד המתקין. הבדיקה עשויה להימשך כמה דקות.',
        'StatusLibrary': 'מתקין את הספרייה המלאה...',
        'StatusLibraryIndex':
            'מתקין את הספרייה המלאה ואת אינדקס החיפוש המוכן...',
        'LibraryNotInstalled': 'התוכנה הותקנה, אבל הספרייה לא.',
        'LibraryExtractFailed': 'חילוץ הספרייה נכשל.',
        'IndexExtractFailed': 'חילוץ אינדקס החיפוש נכשל.',
        'LibraryPackageInvalid': 'מבנה חבילת הספרייה אינו תקין.',
        'BooksSwapFailed':
            'לא ניתן להחליף את תיקיית הספרים הקיימת. ודא שאוצריא סגורה.',
        'IndexSwapFailed':
            'לא ניתן להחליף את תיקיית האינדקס הקיימת. ודא שאוצריא סגורה.',
        'LibraryMoveFailed': 'העברת הספרייה למיקום שלה נכשלה.',
        'HintNoSpace': 'אין מספיק מקום פנוי בכונן. פנה מקום ונסה להתקין שוב.',
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(_text(script, 'hebrew', key), value, reason: key);
        expect(_text(script, 'english', key), isNotEmpty, reason: key);
      }
      // ההודעה בשקט: המשפט, "התוכנה הותקנה...", הרמז, ואז הפלט — כמו ב-dev.
      expect(
        _routine(script, 'procedure LibraryInstallFailed('),
        contains(
          "InstReportLibraryFailure(Message + ' ' + "
          "CustomMessage('LibraryNotInstalled') + Hint,",
        ),
      );
      expect(
        _routine(script, 'procedure InstReportLibraryFailure('),
        contains('SuppressibleMsgBox(Text + #13#10#13#10 + Output,'),
      );
    });

    test('$_regular: הכנת החלקים — עמוד בשכבה עם התקדמות אמיתית, רק באשף', () {
      final script = _script(_regular);
      final init = _routine(script, 'procedure InitializeWizard()');
      final created = init.indexOf(
        'LibraryPrepPage := CreateOutputProgressPage(',
      );
      expect(created, greaterThan(0));
      expect(
        init.substring(0, created),
        contains('if not WizardSilent then'),
        reason: 'בשקט אין עמוד הכנה, כמו ב-dev',
      );
      final prepare = _routine(script, 'function PrepareLibraryParts(');
      expect(prepare, isNot(contains('CreateOutputProgressPage(')));
      expect(prepare, contains('if LibraryPrepPage <> nil then'));
      expect(
        prepare.indexOf('LibraryPrepPage.Show'),
        lessThan(
          prepare.indexOf("PrepareSplitArchive('library.manifest.json'"),
        ),
      );
      expect(prepare, contains('LibraryPrepPage.Hide'));
      final split = _routine(script, 'function PrepareSplitArchive(');
      expect(
        split.indexOf('UiLibraryPrepStart('),
        lessThan(split.indexOf('AssembleSplitArchive(')),
      );
      expect(
        _routine(script, 'procedure UiLibraryPrepStart('),
        contains('LibraryPrepTotal := LibraryPrepTotal + Size'),
      );
      expect(
        _routine(script, 'function UiAssembledBytes()'),
        contains('UiGetFileAttributesEx(LibraryPrepArchive'),
      );
      final build = _routine(script, 'procedure UiAdapterBuildPage(');
      expect(build, contains('UiHideProgressNative(LibraryPrepPage);'));
      expect(build, contains('UiBuildProgress(UiSrcLibraryPrep);'));
    });

    test(
      '$_regular: ספרייה שלא נפרסה — מצב כישלון באשף, וקוד היציאה נשאר 9',
      () {
        final script = _script(_regular);
        final failed = _routine(script, 'procedure LibraryInstallFailed(');
        expect(
          failed.indexOf('LibraryNotInstalled := True;'),
          lessThan(failed.indexOf('InstReportLibraryFailure(')),
        );
        final report = _routine(script, 'procedure InstReportLibraryFailure(');
        expect(report, contains('InstFailed := True;'));
        expect(report, contains('InstFailTech := Output;'));
        // כל כשל בפריסה מחזיר את הספרייה הקודמת, ולכן ההבטחה עליה נכונה תמיד.
        final finish = _routine(script, 'procedure UiAdapterBuildFinish(');
        final kept = finish.substring(finish.indexOf('#ifdef LibraryParts'));
        expect(kept, contains("CustomMessage('FailLibraryKept')"));
      },
    );

    for (final name in _scripts) {
      test('$name: "איך להתקין" — כרטיס ורדיו מחוץ לחלון בוחרים אותו דבר', () {
        final script = _script(name);
        final create = _routine(script, 'procedure CreateInstallModeChoice(');
        for (final radio in const [
          'CurrentUserModeRadio',
          'AllUsersModeRadio',
          'PortableModeRadio',
        ]) {
          // רדיו שמקבל מוקד מהמקלדת מסמן את עצמו: OnClick מעביר את הבחירה הלאה.
          expect(
            create,
            contains('$radio.OnClick := @UiModeRadioClick;'),
            reason: radio,
          );
          expect(create, contains('$radio.Parent := Group;'), reason: radio);
        }
        final click = _routine(script, 'procedure UiModeRadioClick(');
        expect(click, contains('ApplyInstallModeChoice();'));
        expect(click, contains('UiSyncModePage();'));
        // PortableMode נקבע רק ב-ApplyInstallModeChoice (ובשקט ב-InitializeSetup).
        final code = installerCode(name);
        final assigns = RegExp(r'\bPortableMode := ').allMatches(code).toList();
        expect(assigns, isNotEmpty);
        for (final m in assigns) {
          expect(
            enclosingRoutine(code, m.start),
            anyOf('ApplyInstallModeChoice', 'InitializeSetup'),
          );
        }
        // כל שגרה שמשנה רדיו מעבירה את הבחירה ל-ApplyInstallModeChoice.
        final routines = <String>{
          for (final m in RegExp(r'ModeRadio\.Checked := ').allMatches(code))
            enclosingRoutine(code, m.start),
        }..remove('CreateInstallModeChoice');
        expect(routines, isNotEmpty);
        for (final routine in routines) {
          final header = RegExp(
            '^(?:procedure|function) $routine\\b',
            multiLine: true,
          ).firstMatch(code)![0]!;
          expect(
            _routine(code, header),
            contains('ApplyInstallModeChoice()'),
            reason: routine,
          );
        }
      });

      test('$name: לרדיו מחוץ לחלון יש שם נגיש מתורגם', () {
        final script = _script(name);
        final create = _routine(script, 'procedure CreateInstallModeChoice(');
        const captions = {
          'CurrentUserModeRadio': 'ModeMeTitle',
          'AllUsersModeRadio': 'ModeAllTitle',
          'PortableModeRadio': 'ModePortableTitle',
        };
        for (final entry in captions.entries) {
          expect(
            create,
            contains(
              "${entry.key}.Caption := CustomMessage('${entry.value}');",
            ),
          );
          for (final lang in ['hebrew', 'english']) {
            expect(_text(script, lang, entry.value), isNotEmpty);
          }
        }
        expect(create, contains('Group.SetBounds(-ScaleX(4000),'));
      });

      test('$name: "התיקייה קיימת" — בדו-שיח המעוצב, ולא ב-MsgBox של Inno', () {
        final script = _script(name);
        expect(script, contains('DirExistsWarning=no'));
        final next = _routine(script, 'function NextButtonClick(');
        final silent = next.indexOf('if WizardSilent then');
        final ask = next.indexOf('DirExistsDifferentFromPrevious()');
        expect(silent, greaterThan(0));
        expect(ask, greaterThan(silent));
        final condition = next.substring(ask, next.indexOf('then', ask));
        expect(condition, contains('not ModeChangeNeedsRelaunch()'));
        expect(
          condition,
          contains('InstAskYesNo(SetupMessage(msgDirExistsTitle)'),
        );
        expect(
          ask,
          lessThan(next.indexOf('IsProtectedInstallDir(')),
          reason: 'כמו auto של Inno: לפני הבדיקות של המתקין עצמו',
        );
        final compare = _routine(
          script,
          'function DirExistsDifferentFromPrevious(',
        );
        expect(compare, contains('WizardForm.PrevAppDir'));
        expect(compare, contains('CompareText(RemoveBackslash('));
      });

      test('$name: שדרוג שומר את שפת ההתקנה הקודמת', () {
        // UsePreviousLanguage=yes (ברירת המחדל): בלעדיו עדכון שקט מחליף שפה.
        expect(
          _script(name),
          isNot(matches(RegExp(r'^UsePreviousLanguage=', multiLine: true))),
        );
      });
    }

    test('$_full: לתיבת WebView2 יש שם נגיש בלי להציג את הפקד המקורי', () {
      final script = _script(_full);
      final create = _routine(script, 'procedure CreateWebView2Choice(');
      expect(
        create,
        contains("WV2Check.Caption := CustomMessage('WebView2Title');"),
      );
      expect(create, contains('WV2Check.Left := -ScaleX(4000);'));
      expect(create, contains('WV2Check.Checked := WebView2Missing;'));
      expect(create, contains('WV2Check.Enabled := WebView2Missing;'));
      expect(
        _routine(script, 'procedure UiBuildTasksPage('),
        contains("CustomMessage('WebView2Title')"),
      );
      for (final lang in ['hebrew', 'english']) {
        expect(
          _text(script, lang, 'WebView2Title'),
          'Microsoft WebView2 Runtime',
        );
      }
    });

    test('סיום: "פתח" ו"סגור" דרך רשומת [Run], ובכישלון אין הפעלה ואין אתחול', () {
      for (final name in _scripts) {
        final run = _section(_script(name), 'Run');
        expect(
          run,
          contains(
            r'Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchApp}"; '
            'Flags: nowait postinstall skipifsilent runasoriginaluser\n',
          ),
          reason: name,
        );
      }
      final script = _script(_regular);
      final finish = _routine(script, 'procedure UiFinish(');
      expect(finish, contains('WizardForm.RunList.Checked[I] := Launch;'));
      expect(finish, contains('UiClickReal(WizardForm.NextButton)'));
      final click = _routine(script, 'procedure UiButtonClick(');
      expect(click, contains('UiBtnOpenApp: UiFinish(True);'));
      expect(click, contains('UiBtnDone: UiFinish(False);'));
      final build = _routine(script, 'procedure UiAdapterBuildFinish(');
      expect(
        build,
        contains(
          'CanRun := (WizardForm.RunList.Items.Count > 0) and not Restart and '
          'not InstFailed;',
        ),
      );
      // Enter מפעיל את "סיום" האמיתי: בכישלון הוא לא יריץ את התוכנה ולא יאתחל.
      final failed = build.substring(build.indexOf('if InstFailed then'));
      expect(failed, contains('WizardForm.RunList.Checked[I] := False;'));
      expect(failed, contains('WizardForm.NoRadio.Checked := True;'));
      expect(
        build.indexOf('WizardForm.NoRadio.Checked := True;'),
        lessThan(build.indexOf('UiSetButton(UiBtnDone')),
      );
    });

    test('כישלון: צעד הבא, והבטחה על הספרייה רק לפני ההחלפה', () {
      final script = _script(_full);
      final build = _routine(script, 'procedure UiAdapterBuildFinish(');
      expect(build, contains("CustomMessage('FailRetry')"));
      expect(build, contains('if not LibrarySwapStarted then'));
      expect(build, contains("CustomMessage('FailLibraryKept')"));
      // הדגל מורם מיד אחרי שהספרייה הקודמת הוזזה לגיבוי.
      for (final signature in ['procedure ExtractEmbeddedLibraryArchives(']) {
        final body = _routine(script, signature);
        final backup = body.indexOf('if not BooksBackedUp then');
        final flag = body.indexOf('LibrarySwapStarted := True;');
        expect(backup, greaterThan(0), reason: signature);
        expect(flag, greaterThan(backup), reason: signature);
        expect(
          body.substring(backup, flag),
          contains("CustomMessage('BooksSwapFailed')"),
          reason: 'החלפה שלא התחילה משאירה את הספרייה שלמה',
        );
        expect(
          flag,
          lessThan(body.indexOf("CustomMessage('BooksMoveFailed')")),
          reason: signature,
        );
      }
      // קוד היציאה בפרטים הטכניים, לא בגוף ההודעה.
      final flat = script.replaceAll(RegExp(r'\s+'), ' ');
      for (final key in const [
        'DbExtractFailed',
        'PdfExtractFailed',
        'PdfOpenFailed',
      ]) {
        for (final lang in const ['english', 'hebrew']) {
          expect(_text(script, lang, key), isNot(contains('%1')), reason: key);
        }
        expect(
          flat,
          contains(
            "InstReportFailure(CustomMessage('$key') + Hint, "
            "Msg1('ExitCode', IntToStr(ResultCode)) + #13#10 + ErrOutput, True);",
          ),
          reason: key,
        );
      }
    });

    test('רגע לפני ההתקנה: "אוצריא פתוחה" רק כש-Restart Manager מצא משהו', () {
      final script = _script(_regular);
      final messages = _messages(script, 'Messages');
      for (final lang in const ['english', 'hebrew']) {
        expect(
          messages[lang]!['PreparingDesc'],
          isNot(anyOf(contains('Otzaria'), contains('אוצריא'))),
          reason: 'הכותרת מוצגת עוד לפני השאילתה',
        );
      }
      // עד ש-Restart Manager ממלא אותה, ברשימה המוסתרת נשאר שם הפקד ("PreparingMemo").
      final hint = _routine(script, 'function UiAdapterPageHint(');
      expect(
        hint.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'if WizardForm.PreparingMemo.Visible then '
          'WizardForm.PageDescriptionLabel.Caption := '
          "CustomMessage('PrepareAppsOpen');",
        ),
      );
      final preparing = _routine(script, 'procedure UiBuildPreparing(');
      expect(
        preparing.indexOf('if WizardForm.PreparingMemo.Visible then'),
        lessThan(preparing.indexOf('Trim(WizardForm.PreparingMemo.Text)')),
      );
      expect(preparing, contains("UiAddRow('app',"));
      expect(preparing, contains("UiInstCard(UiCardCloseApps, 'update',"));
      expect(
        "'warning'".allMatches(preparing).length,
        1,
        reason: 'סמל האזהרה רק ל"אל תסגור"',
      );
    });

    test('ניסוח: מקום פנוי, תיקייה קיימת, יציאה וכותרות באנגלית', () {
      final script = _script(_full);
      final messages = _messages(script, 'Messages');
      final he = messages['hebrew']!;
      final en = messages['english']!;
      // LRM לפני המספר: בלעדיו "MB 313.9" מוצג בסדר הפוך במשפט העברי.
      expect(he['DiskSpaceMBLabel'], contains('‎[mb] MB'));
      expect(he['DiskSpaceGBLabel'], contains('‎[gb] GB'));
      for (final lang in [he, en]) {
        expect(lang['DirExists'], contains('%1'));
        expect(lang['DirExistsTitle'], isNotNull);
        expect(lang['ExitSetupTitle'], isNotNull);
        expect(lang['ExitSetupMessage'], isNotNull);
        expect(lang['DiskSpaceMBLabel'], contains('[mb]'));
        expect(lang['DiskSpaceGBLabel'], contains('[gb]'));
      }
      expect(he['DirExistsTitle'], 'התיקייה כבר קיימת');
      expect(en['StatusExtractFiles'], 'Copying files...');
      expect(_text(script, 'hebrew', 'BooksExists'), isNot(contains('תוכנה')));
      // כמו במסייע: כותרות באנגלית ב-Sentence case.
      for (final title in [
        en['WizardSelectDir']!,
        en['WizardSelectTasks']!,
        en['WizardReady']!,
        en['WizardPreparing']!,
        _text(script, 'english', 'BooksTitle'),
      ]) {
        expect(
          title.split(' ').skip(1).where((w) => w.startsWith(RegExp('[A-Z]'))),
          isEmpty,
          reason: title,
        );
      }
    });

    test('שדרוג באשף מדבר על "עדכון", ואיפוס ההגדרות מסומן כהרסני', () {
      final script = _script(_regular);
      final init = _routine(script, 'procedure UiInstallerInitializeWizard(');
      // אחרי ההתקנה הרישום כבר מראה את הגרסה החדשה, ולכן ההחלטה נשמרת בהתחלה.
      expect(
        init,
        contains(
          "InstIsUpdate := (GetPreviousDisplayVersion() <> '') and "
          'not PortableMode;',
        ),
      );
      expect(init, contains("CustomMessage('UpdateButton')"));
      final build = _routine(script, 'procedure UiAdapterBuildFinish(');
      expect(build, contains('InstIsUpdate and not PortableMode then'));
      expect(build, contains("CustomMessage('FinishUpdated')"));
      expect(build, isNot(contains('GetPreviousDisplayVersion')));
      expect(
        _routine(script, 'function UiInstCard('),
        contains('Card.Danger := Kind = UiCardReset;'),
      );
      final layout = _routine(_read(core), 'function UiLayoutCard(');
      expect(
        layout.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'if Card.Danger then UiText(C, Card.Desc, X, Y + Px(3), TextW, '
          'DescH, 13, False, UiErrorColor,',
        ),
      );
    });

    test('קו ההפרדה של הכותרת התחתונה מוצג רק מעל כפתורים', () {
      final coreText = _read(core);
      final sync = _routine(coreText, 'procedure UiSyncFooter(');
      expect(sync, contains('(UiButtons[I].Img.Parent = UiFooter)'));
      expect(sync, contains('UiFooterLine.Visible := Line;'));
      expect(
        _routine(coreText, 'procedure UiInitializeWizard('),
        contains('UiFooterLine := UiPanel(UiFooter, UiDividerColor);'),
      );
    });
  });

  group('שכבת התצוגה המשותפת — ליבה בלי מוצר', () {
    const core = 'otzaria_ui_core.iss';

    test('$core: אינה מכירה עמוד או מצב של מוצר', () {
      final script = _read(core);
      for (final name in const [
        'ModePage',
        'OtherPage',
        'PresetPage',
        'CustomPage',
        'FolderPage',
        'ConnectPage',
        'DownloadPage',
        'WorkPage',
        'StopRequested',
        'RevealCheck',
        'IsThisComputerMode',
        'DownloadStatus',
        "'title_",
      ]) {
        expect(script, isNot(contains(name)), reason: name);
      }
      expect(
        script,
        isNot(contains('#include')),
        reason: 'העיצוב נכלל לפני הליבה, ב-otzaria_ui_art.iss',
      );
    });

    test('$core: כל טקסט שלה מוצג בה עצמה, בשתי השפות', () {
      final script = _read(core);
      final byLang = _messages(script, 'CustomMessages');
      expect(byLang.keys.toSet(), {'english', 'hebrew'});
      expect(
        byLang['english']!.keys.toSet(),
        byLang['hebrew']!.keys.toSet(),
      );
      for (final key in byLang['english']!.keys) {
        expect(script, contains("CustomMessage('$key')"), reason: key);
      }
    });

    test('המסייע מממש את כל חוזה המתאם שהליבה מצהירה', () {
      final core = _read('otzaria_ui_core.iss');
      final forwards = RegExp(
        r'^(procedure|function) (\w+)\(',
        multiLine: true,
      ).allMatches(core).where((m) => _isForward(core, m.start)).toList();
      expect(forwards.length, greaterThan(5));
      final script = _script(_assistant);
      for (final m in forwards) {
        _routine(script, '${m[1]} ${m[2]}(');
      }
    });
  });

  group('עיצוב המסייע — גרסה נעוצה מריפו העיצוב', () {
    const pinPath = 'installer/assistant_art.pin.json';
    const fetcher = 'tool/release/fetch_assistant_art.ps1';

    test('הנעיצה: Release של Otzaria, sha256 מלא, וגרסה אחת בכל השדות', () {
      final pin =
          jsonDecode(File(pinPath).readAsStringSync()) as Map<String, Object?>;
      final version = pin['version'] as String;

      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(pin['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        pin['url'],
        'https://github.com/Otzaria/otzaria-design/releases/download/'
        'download-assistant-art-v$version/download-assistant-art-$version.zip',
        reason: 'התגית ושם הנכס של pack_release.py נגזרים מהגרסה',
      );
      expect(
        File(fetcher).readAsStringSync(),
        isNot(contains(version)),
        reason: 'הנעיצה היא המקום היחיד שמעדכנים בהעלאת גרסה',
      );
    });

    test('כל workflow שמקמפל את המסייע מושך את העיצוב לפני ISCC', () {
      final compiling = [
        for (final file in Directory('.github/workflows').listSync())
          if (file is File &&
              file.readAsStringSync().contains(
                r'installer\download_assistant.iss',
              ))
            file.path,
      ];
      expect(compiling, isNotEmpty);
      for (final path in compiling) {
        final text = File(path).readAsStringSync();
        final fetch = text.indexOf('& ./tool/release/fetch_assistant_art.ps1');
        expect(fetch, greaterThanOrEqualTo(0), reason: path);
        expect(
          fetch,
          lessThan(
            text.indexOf(r'& "$env:ISCC" installer\download_assistant.iss'),
          ),
          reason: path,
        );
      }
      expect(
        _workflowStep('Build Download Assistant (non-fatal helper tool)'),
        contains('continue-on-error: true'),
        reason: 'כישלון בהורדת העיצוב מפיל רק את המסייע',
      );
    });

    test('כל שלב שמקמפל מתקין של אוצריא מושך את העיצוב לפני ISCC, וקטלני', () {
      // המתקין אינו נבנה בלי העיצוב (#error), ולכן כישלון המשיכה מפיל את השלב.
      const steps = {
        'Build Inno Setup installer': true,
        'Build Inno Setup FULL installer (ARM64)': false,
        'Build regular installer': true,
        'Build regular installer (ARM64)': true,
      };
      for (final MapEntry(key: name, value: fatal) in steps.entries) {
        final step = _workflowStep(name);
        final fetch = step.indexOf('& ./tool/release/fetch_assistant_art.ps1');
        expect(fetch, greaterThanOrEqualTo(0), reason: name);
        for (final m in RegExp(
          r'& "\$env:ISCC"[^\n]*otzaria(?:_full)?\.iss',
        ).allMatches(step)) {
          expect(fetch, lessThan(m.start), reason: name);
        }
        // ה-FULL ל-ARM64 אינו חוסם שחרור ממילא (continue-on-error).
        expect(step.contains('continue-on-error: true'), !fatal, reason: name);
      }
    });

    test('הסקריפט מאמת hash ואת AA_ART_VERSION לפני שהוא פורס ומחליף', () {
      final script = File(fetcher).readAsStringSync().replaceAll('\r\n', '\n');
      final hash = script.indexOf('Get-FileHash');
      final expand = script.indexOf('Expand-Archive');
      final version = script.indexOf('AA_ART_VERSION');
      final replace = script.indexOf(
        r'Move-Item -LiteralPath $staged -Destination $Destination',
      );

      expect(hash, greaterThanOrEqualTo(0));
      expect(
        script.substring(hash, expand),
        contains(r'if ($actual -ne $sha256)'),
      );
      expect(expand, greaterThan(hash), reason: 'פריסה רק אחרי אימות');
      expect(version, greaterThan(expand));
      expect(replace, greaterThan(version), reason: 'מחליפים פעם אחת, בסוף');
      // הדילוג נשען על חותמת ה-sha, לא על קיום קבצים.
      expect(
        script,
        contains(r'(Get-Content -LiteralPath $stamp -Raw).Trim() -eq $sha256'),
      );
      expect(script, contains('-TimeoutSec'));
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
