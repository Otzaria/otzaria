import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// `docs/plugin-sdk/ICONS.md` הוא הרשימה שמחברי תוספים עובדים לפיה, והיא
/// נגזרת משתי ספריות שממשיכות לגדול (`pubspec.lock` אינו במעקב, וגרסת
/// `otzaria_icons` מתחלפת בכל עדכון `ref`).
///
/// לכן הרשימה **מגונררת ולא נערכת ביד**: הבדיקה בונה את הבלוק מהספריות
/// ומשווה אותו לקובץ, וב-`--dart-define=update_icons_doc=true` כותבת אותו
/// מחדש במקום להיכשל. אייקון שנוסף לספרייה הוא לכן פקודה אחת, לא עריכה של
/// עשרות שורות טבלה — וגם אינו יכול לחמוק בשקט, כי הרשימה היא חוזה כלפי
/// מחברי תוספים ושם שנמחק ממנה שובר תוסף מותקן.
const String kIconsDocPath = 'docs/plugin-sdk/ICONS.md';

const String _beginMarker = '<!-- BEGIN GENERATED: otzaria-icons';
const String _endMarker = '<!-- END GENERATED: otzaria-icons -->';

/// הפקודה שמרעננת את הבלוק. מופיעה גם בהודעת הכישלון וגם ב-ICONS.md עצמו,
/// כדי שמי שנתקל בכישלון לא יצטרך לחפש אותה.
const String kRegenerateCommand =
    'flutter test test/plugins/utils/plugin_icon_resolver_docs_test.dart '
    '--dart-define=update_icons_doc=true';

/// כשמופעל, הבדיקה כותבת את הבלוק מחדש במקום להשוות.
const bool kUpdateMode = bool.fromEnvironment('update_icons_doc');

/// השמות שקיימים בשתי הספריות — עליהם כלל הקדימות מכריע, ועליהם בלבד
/// התחילית `fluent:` משנה את התוצאה.
Set<String> get sharedNames => OtzariaIcons.allIcons.keys
    .where((name) => fluentIconFromName(name) != null)
    .toSet();

/// בונה את הבלוק המגונרר: שורת התקציר עם שני המספרים, ואז הטבלה.
///
/// המספרים חיים כאן ולא בפרוזה שמסביב — פרוזה עם מספר קבוע מתיישנת בשקט
/// ואינה ניתנת לגינרוט חלקי.
String buildGeneratedBlock() {
  final names = OtzariaIcons.allIcons.keys.toList()..sort();
  final shared = sharedNames;
  final buffer = StringBuffer()
    ..writeln(
      'הספרייה מכילה **${names.length} אייקונים**, ומהם **${shared.length}** '
      'קיימים גם בפלואנט.',
    )
    ..writeln()
    ..writeln('| שם | גם בפלואנט |')
    ..writeln('|-----|:---:|');
  for (final name in names) {
    buffer.writeln('| `$name` | ${shared.contains(name) ? '✔' : ''} |');
  }
  return buffer.toString().trimRight();
}

/// מחליף את התוכן שבין הסמנים, ומשאיר את הסמנים ואת שאר הקובץ כמות שהם.
String replaceGeneratedBlock(String doc, String block) {
  final begin = doc.indexOf(_beginMarker);
  final beginEnd = doc.indexOf('-->', begin);
  final end = doc.indexOf(_endMarker, beginEnd);
  return '${doc.substring(0, beginEnd + 3)}\n\n$block\n\n'
      '${doc.substring(end)}';
}

/// התוכן שבין הסמנים, או null כשאחד מהם חסר.
String? extractGeneratedBlock(String doc) {
  final begin = doc.indexOf(_beginMarker);
  if (begin < 0) return null;
  final beginEnd = doc.indexOf('-->', begin);
  if (beginEnd < 0) return null;
  final end = doc.indexOf(_endMarker, beginEnd);
  if (end < 0) return null;
  return normalizeEol(doc.substring(beginEnd + 3, end).trim());
}

/// מנרמל סופי שורה להשוואה.
///
/// `core.autocrlf=true` (ברירת המחדל ב-Windows) מוציא את הקובץ מ-git עם
/// CRLF, בעוד שהבלוק נבנה כאן עם LF. בלי הנרמול הבדיקה נופלת בכל checkout
/// טרי במערכת הפעלה אחת בלבד — כישלון שאין לו שום קשר לתוכן שהיא בודקת.
String normalizeEol(String value) => value.replaceAll('\r\n', '\n');

void main() {
  late File file;
  late String doc;

  setUpAll(() {
    file = File(kIconsDocPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$kIconsDocPath חסר — אם הוזז, עדכן את הנתיב בבדיקה',
    );

    if (kUpdateMode) {
      final original = file.readAsStringSync();
      var updated = replaceGeneratedBlock(original, buildGeneratedBlock());
      // שמירה על סופי השורה שהיו בקובץ. כתיבה ב-LF על קובץ ש-git הוציא
      // ב-CRLF הייתה מסמנת את כל הקובץ כמשונה, גם כשהתוכן זהה.
      if (original.contains('\r\n')) {
        updated = updated.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
      }
      file.writeAsStringSync(updated);
      // ignore: avoid_print
      print('[update_icons_doc] $kIconsDocPath עודכן מהספרייה.');
    }
    doc = file.readAsStringSync();
  });

  group('ICONS.md מסונכרן עם ספריות האייקונים', () {
    test('הסמנים קיימים ותוחמים בלוק', () {
      expect(
        extractGeneratedBlock(doc),
        isNotNull,
        reason:
            'סמני הגינרוט חסרים או הפוכים ב-$kIconsDocPath. '
            'שחזר אותם ואז הרץ:\n  $kRegenerateCommand',
      );
    });

    test('הבלוק המגונרר תואם לספריות', () {
      expect(
        extractGeneratedBlock(doc),
        buildGeneratedBlock(),
        reason:
            'רשימת האייקונים ב-$kIconsDocPath אינה תואמת לספריות '
            '(אייקון נוסף/נמחק, או שם שהתחיל להתקיים גם בפלואנט).\n'
            'אל תערוך את הטבלה ידנית — הרץ:\n  $kRegenerateCommand',
      );
    });

    test('הפרוזה שמחוץ לבלוק אינה נושאת מספרים שיתיישנו', () {
      final outside = doc.replaceRange(
        doc.indexOf(_beginMarker),
        doc.indexOf(_endMarker) + _endMarker.length,
        '',
      );
      // המספר של פלואנט מעוגל בכוונה ("כ-4,500") ואינו מתיישן; מספר
      // האייקונים של אוצריא, לעומתו, חייב לחיות רק בבלוק המגונרר.
      expect(
        outside,
        isNot(contains('${OtzariaIcons.allIcons.length} אייקונים')),
        reason:
            'מספר האייקונים חזר לפרוזה. הוא מתיישן שם בשקט — '
            'השאר אותו בבלוק המגונרר בלבד',
      );
    });

    test('הפקודה לרענון מופיעה בקובץ עצמו', () {
      expect(
        doc,
        contains('--dart-define=update_icons_doc=true'),
        reason: 'בלי הפקודה בקובץ, הקורא לא ידע איך לרענן את הרשימה',
      );
    });
  });

  group('בניית הבלוק', () {
    test('סימון "גם בפלואנט" תואם לחפיפה בפועל', () {
      final rows = RegExp(
        r'^\| `([a-z0-9_]+)` \|(.*)\|$',
        multiLine: true,
      ).allMatches(buildGeneratedBlock());

      expect(rows, isNotEmpty);
      final shared = sharedNames;
      for (final row in rows) {
        final name = row.group(1)!;
        expect(row.group(2)!.contains('✔'), shared.contains(name), reason: name);
      }
    });

    test('כל שמות הספרייה מופיעים, ממוינים', () {
      final names = RegExp(
        r'^\| `([a-z0-9_]+)` \|',
        multiLine: true,
      ).allMatches(buildGeneratedBlock()).map((m) => m.group(1)!).toList();

      expect(names.toSet(), OtzariaIcons.allIcons.keys.toSet());
      expect(names, List<String>.from(names)..sort());
    });

    test('replaceGeneratedBlock נוגע רק בבלוק', () {
      final original = File(kIconsDocPath).readAsStringSync();
      final rewritten = replaceGeneratedBlock(original, 'תוכן חדש');

      expect(extractGeneratedBlock(rewritten), 'תוכן חדש');
      expect(
        rewritten.substring(0, rewritten.indexOf(_beginMarker)),
        original.substring(0, original.indexOf(_beginMarker)),
      );
      expect(
        rewritten.substring(rewritten.indexOf(_endMarker)),
        original.substring(original.indexOf(_endMarker)),
      );
    });
  });
}
