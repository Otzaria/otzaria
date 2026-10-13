import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

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
