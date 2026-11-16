import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/user_content_import/services/user_import_parser.dart';

Link _link({
  required String heRef,
  String path2 = 'רמב"ן על דברים',
  String? heRefEnd,
  int? index2End,
}) => Link(
  heRef: heRef,
  index1: 1,
  path2: path2,
  index2: 0,
  connectionType: LinkTypes.commentary,
  heRefEnd: heRefEnd,
  index2End: index2End,
);

void main() {
  group('כתובת התצוגה מוותרת על הרמה האחרונה', () {
    test('רמב"ן: אינדקס הפירוש בתוך הפסוק יורד מהתצוגה', () {
      expect(
        _link(heRef: 'רמב"ן על דברים,  ז, ט, א').fallbackDisplayReference,
        'רמב"ן על דברים, ז, ט',
      );
      expect(
        _link(heRef: 'רמב"ן על דברים,  ז, יב, א').fallbackDisplayReference,
        'רמב"ן על דברים, ז, יב',
      );
    });

    test('קישור-טווח שמובחן ברמה האחרונה שומר עליה', () {
      final link = _link(
        heRef: 'רמב"ן על דברים,  יג, ה, ב',
        heRefEnd: 'רמב"ן על דברים,  יג, ה, ג',
        index2End: 5,
      );
      expect(
        link.fallbackDisplayReference.startsWith('רמב"ן על דברים, יג, ה, ב'),
        isTrue,
        reason: 'got ${link.fallbackDisplayReference}',
      );
    });

    test('כתובת דו-רכיבית לא מתקצרת לשם הספר בלבד', () {
      expect(
        _link(
          heRef: 'משנה ברורה,  לב',
          path2: 'משנה ברורה',
        ).fallbackDisplayReference,
        'משנה ברורה, לב',
      );
    });

    test('משנה ברורה: הס"ק נשמר — כתובת תלת-רכיבית לא מתקצרת', () {
      expect(
        _link(
          heRef: 'משנה ברורה,  לב, ה',
          path2: 'משנה ברורה',
        ).fallbackDisplayReference,
        'משנה ברורה, לב, ה',
      );
    });
  });

  group('הפורמט המופרד (פסיק אחרי שם הספר) נמדד לפי רמות המיקום', () {
    test('רש"י על הגמרא: מספרי הקטע והפירוש שאחרי הדף יורדים', () {
      expect(
        _link(
          heRef: 'רש"י על חולין, ו., ה, ב',
          path2: 'רש"י על חולין',
        ).fallbackDisplayReference,
        'רש"י על חולין, ו.',
      );
    });

    test('שם ספר עם פסיק: הסעיף אינו נמחק למרות 4 רכיבי-פסיק', () {
      expect(
        _link(
          heRef: 'שולחן ערוך, אורח חיים, יא, ב',
          path2: 'שולחן ערוך, אורח חיים',
        ).fallbackDisplayReference,
        'שולחן ערוך, אורח חיים, יא, ב',
      );
      expect(
        _link(
          heRef: 'משנה תורה, הלכות שבת, א, א',
          path2: 'משנה תורה, הלכות שבת',
        ).fallbackDisplayReference,
        'משנה תורה, הלכות שבת, א, א',
      );
    });

    test('הפורמט הדבוק הישן שומר על ההתנהגות הקיימת', () {
      expect(
        _link(
          heRef: 'רש"י על חולין ו., ה, ב',
          path2: 'רש"י על חולין',
        ).fallbackDisplayReference,
        'רש"י על חולין ו., ה, ב',
      );
    });
  });

  group('כתובת לפי דף מוצגת עד הדף, בלי מספר הקטע (issue #2480)', () {
    test('הגמרא ומפרש דו-רמתי עליה', () {
      expect(
        _link(
          heRef: 'עירובין, כו:, יז',
          path2: 'עירובין',
        ).fallbackDisplayReference,
        'עירובין, כו:',
      );
      expect(
        _link(
          heRef: 'רש"ש על זבחים, ב:, ב',
          path2: 'רש"ש על זבחים',
        ).fallbackDisplayReference,
        'רש"ש על זבחים, ב:',
      );
    });

    test('דף בעומק שלוש רמות נשמר אחרי הסרת הקטע', () async {
      final link = _link(
        heRef: 'דברי אמת, דברי אמת על הגמרא, שבת,  ה., א',
        path2: 'דברי אמת',
      );
      const expected = 'דברי אמת, דברי אמת על הגמרא, שבת, ה.';
      expect(link.fallbackDisplayReference, expected);
      expect(await link.displayReference, expected);
    });

    test('טווח קטעים באותו דף עמוק אינו מקצר גם את הדף', () {
      expect(
        _link(
          heRef: 'דברי אמת, דברי אמת על הגמרא, שבת,  ה., א',
          heRefEnd: 'דברי אמת, דברי אמת על הגמרא, שבת,  ה., ב',
          path2: 'דברי אמת',
          index2End: 5,
        ).fallbackDisplayReference,
        'דברי אמת, דברי אמת על הגמרא, שבת, ה.',
      );
    });

    test('טווח דפים בעומק שלוש רמות שומר על שני הדפים', () {
      expect(
        _link(
          heRef: 'דברי אמת, דברי אמת על הגמרא, שבת, ה., א',
          heRefEnd: 'דברי אמת, דברי אמת על הגמרא, שבת, ה:, ב',
          path2: 'דברי אמת',
          index2End: 5,
        ).fallbackDisplayReference,
        'דברי אמת, דברי אמת על הגמרא, שבת, ה.–ה:',
      );
    });

    test('קישור-טווח באותו דף מוצג כדף אחד', () {
      expect(
        _link(
          heRef: 'כתובות, עט., ג',
          heRefEnd: 'כתובות, עט., ד',
          path2: 'כתובות',
          index2End: 5,
        ).fallbackDisplayReference,
        'כתובות, עט.',
      );
    });

    test('קישור-טווח בין דפים מציג את שני הדפים בלבד', () {
      expect(
        _link(
          heRef: 'סוטה, יב:, כג',
          heRefEnd: 'סוטה, יג., א',
          path2: 'סוטה',
          index2End: 5,
        ).fallbackDisplayReference,
        'סוטה, יב:–יג.',
      );
    });

    test('טווח בספר אוצריא אינו מוסיף את כתובת השורה הגולמית', () async {
      final ranged = _link(
        heRef: 'חברותא על בכורות 4790',
        heRefEnd: 'חברותא על בכורות 4793',
        path2: 'חברותא על בכורות',
        index2End: 4793,
      );
      final single = _link(
        heRef: 'חברותא על בכורות 4790',
        path2: 'חברותא על בכורות',
      );
      expect(ranged.fallbackDisplayReference, single.fallbackDisplayReference);
      expect(await ranged.displayReference, single.fallbackDisplayReference);
    });

    for (final (separator, label) in [
      (', ', 'רווח'),
      (',', 'ללא רווח'),
      (',\u00a0', 'רווח קשיח'),
      (',\t', 'טאב'),
      (' ', 'ללא פסיק'),
    ]) {
      test('טווח מייבוא אישי שומר את הקצה הקריא: $label', () async {
        final start = 'רש״י על בראשית א$separatorלא';
        final end = 'רש״י על בראשית ב$separatorא';
        final parsed = UserImportParser.parseNativeLinksJson(
          jsonEncode([
            {
              'line_index_1': 1,
              'line_index_2': 1,
              'line_index_2_end': 40,
              'path_2': 'רש״י על בראשית',
              'heRef_2': start,
              'heRef_2_end': end,
            },
          ]),
        );
        expect(parsed.errors, isEmpty);
        final row = parsed.rows.single;
        expect(row.targetRef, start);
        expect(row.targetRefEnd, end);
        final link = _link(
          heRef: row.targetRef!,
          heRefEnd: row.targetRefEnd,
          path2: row.targetTitle,
          index2End: row.targetLineNumberEnd,
        );
        expect(link.fallbackDisplayReference, endsWith(' – $end'));
        expect(await link.displayReference, endsWith(' – $end'));
        expect(link.heRefEnd, end);
        expect(link.index2End, 40);
      });
    }

    for (final (title, end, last) in [
      ('ספר אישי', 'ספר אישי 12', 40),
      ('ספר אישי', 'ספר אחר 40', 40),
      ('ספר אישי', 'ספר אישי 40', null),
    ]) {
      test('קצה ללא פסיק נשמר כשכתובת השורה אינה ודאית: $end/$last', () async {
        final link = _link(
          heRef: '$title א',
          heRefEnd: end,
          path2: title,
          index2End: last,
        );
        expect(link.fallbackDisplayReference, endsWith(' – $end'));
        expect(await link.displayReference, endsWith(' – $end'));
      });
    }

    test('כתובת שורה סינתטית עם פסיק בשם הספר נשמטת', () async {
      final ranged = _link(
        heRef: 'ספר, חלק א 12',
        heRefEnd: 'ספר, חלק א 40',
        path2: 'ספר, חלק א',
        index2End: 40,
      );
      final single = _link(heRef: ranged.heRef, path2: ranged.path2);
      expect(ranged.fallbackDisplayReference, single.fallbackDisplayReference);
      expect(await ranged.displayReference, single.fallbackDisplayReference);
    });

    test('הרמה האחרונה בספר שאינו לפי דף נשמרת', () {
      expect(
        _link(heRef: 'יהושע, ב, יג', path2: 'יהושע').fallbackDisplayReference,
        'יהושע, ב, יג',
      );
    });
  });

  test('מטמון כתובת התצוגה מבחין בין הפניות לאותה שורת יעד', () async {
    final first = _link(
      heRef: 'מטמון הפניות ייחודי, א',
      path2: 'מטמון הפניות ייחודי',
    );
    final second = _link(
      heRef: 'מטמון הפניות ייחודי, ב',
      path2: 'מטמון הפניות ייחודי',
    );

    expect(await first.displayReference, first.fallbackDisplayReference);
    expect(await second.displayReference, second.fallbackDisplayReference);
  });

  test('מטמון כתובת התצוגה מבחין בין קצות טווח', () async {
    final first = _link(
      heRef: 'מטמון טווח ייחודי, א',
      heRefEnd: 'מטמון טווח ייחודי, ב',
      path2: 'מטמון טווח ייחודי',
    );
    final second = _link(
      heRef: 'מטמון טווח ייחודי, א',
      heRefEnd: 'מטמון טווח ייחודי, ג',
      path2: 'מטמון טווח ייחודי',
    );

    expect(await first.displayReference, first.fallbackDisplayReference);
    expect(await second.displayReference, second.fallbackDisplayReference);
  });
}
