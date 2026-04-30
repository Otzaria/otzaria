import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/rules/gemara_reference_rule.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';

final _ctx = const GeneratedLinkRuleContext(
  sourceBookId: 1,
  sourceBookTitle: 'test',
);

Future<List<DetectedReference>> _detect(String line) async {
  final rule = GemaraReferenceRule();
  return rule.detect(_ctx, [line], const LineRange(0, 0));
}

Future<List<DetectedReference>> _detectWithContext(
  String line,
  GeneratedLinkRuleContext context,
) async {
  final rule = GemaraReferenceRule();
  return rule.detect(context, [line], const LineRange(0, 0));
}

void main() {
  group('GemaraReferenceRule — תבניות בסיסיות', () {
    test('ברכות ב. — מסכת + דף + נקודה', () async {
      final refs = await _detect('ראה ברכות ב. לפרטים');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ברכות'));
      expect(refs.first.targetRefText, equals('ב א'));
    });

    test('ברכות ב: — נקודתיים כסימן עמוד ב', () async {
      final refs = await _detect('ברכות ב:');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('ב ב'));
    });

    test('ברכות ב א — עמוד מפורש', () async {
      final refs = await _detect('ברכות ב א');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('ב א'));
    });

    test('ברכות ב ב — עמוד ב מפורש', () async {
      final refs = await _detect('ברכות ב ב');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('ב ב'));
    });

    test('ברכות דף ב ע"א — עם מילת דף ועמוד', () async {
      final refs = await _detect('ברכות דף ב ע"א');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ברכות'));
      expect(refs.first.targetRefText, equals('ב א'));
    });

    test('ברכות דף ב ע"ב — גרשיים רגיל', () async {
      final refs = await _detect('ברכות דף ב ע"ב');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('ב ב'));
    });

    test('ברכות דף ב ע״א — גרשיים עברי', () async {
      final refs = await _detect('ברכות דף ב ע״א');
      expect(refs, hasLength(1));
      expect(refs.first.targetRefText, equals('ב א'));
    });
  });

  group('GemaraReferenceRule — אותיות שימוש', () {
    test('בברכות דף ב ע"א — תחילית ב', () async {
      final refs = await _detect('בברכות דף ב ע"א');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ברכות'));
    });

    test('דשבת כ. — תחילית ד', () async {
      final refs = await _detect('דשבת כ.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שבת'));
    });

    test('מגיטין מה. — תחילית מ', () async {
      final refs = await _detect('מגיטין מה.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('גיטין'));
    });

    test('לסנהדרין ה. — תחילית ל', () async {
      final refs = await _detect('לסנהדרין ה.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('סנהדרין'));
    });

    test('כנדרים כ. — תחילית כ', () async {
      final refs = await _detect('כנדרים כ.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('נדרים'));
    });

    test('שבבא קמא ג. — תחילית ש', () async {
      final refs = await _detect('שבבא קמא ג.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בבא קמא'));
    });
  });

  group('GemaraReferenceRule — מסכתות מורכבות', () {
    test('בבא קמא ג.', () async {
      final refs = await _detect('בבא קמא ג.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בבא קמא'));
    });

    test('בבא מציעא קיט.', () async {
      final refs = await _detect('בבא מציעא קיט.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בבא מציעא'));
    });

    test('בבא בתרא קעו.', () async {
      final refs = await _detect('בבא בתרא קעו.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('בבא בתרא'));
    });

    test('ראש השנה ה.', () async {
      final refs = await _detect('ראש השנה ה.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ראש השנה'));
    });

    test('עבודה זרה ב.', () async {
      final refs = await _detect('עבודה זרה ב.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('עבודה זרה'));
    });
  });

  group('GemaraReferenceRule — אימות גבולות', () {
    test('דף גדול מהמקסימום לא מזוהה', () async {
      // ברכות max = 64; דף ס"ה = 65
      final refs = await _detect('ברכות סה.');
      expect(refs, isEmpty);
    });

    test('דף א לא מזוהה (מינימום הוא ב)', () async {
      final refs = await _detect('ברכות א.');
      expect(refs, isEmpty);
    });

    test('בבא בתרא קעז. — מעל המקסימום (176)', () async {
      final refs = await _detect('בבא בתרא קעז.');
      expect(refs, isEmpty);
    });

    test('בבא בתרא קעו. — בדיוק המקסימום תקין', () async {
      final refs = await _detect('בבא בתרא קעו.');
      expect(refs, hasLength(1));
    });
  });

  group('GemaraReferenceRule — false positives', () {
    test('כו\'. לא מזוהה כדף כו', () async {
      // כו' הוא קיצור "כן וכן", לא מספר דף
      final refs = await _detect('ברכות כו\'.');
      expect(refs, isEmpty);
    });

    test('מילה רגילה שמכילה שם מסכת לא מזוהה', () async {
      // "שבתות" מכיל "שבת" אך לא מסכת
      final refs = await _detect('שבתות רבות עברו');
      expect(refs, isEmpty);
    });

    test('הברכות לא מזוהה (ה לפני ברכות)', () async {
      // ה' לפני ברכות מונעת זיהוי כמסכת
      final refs = await _detect('הברכות הן חשובות');
      expect(refs, isEmpty);
    });
  });

  group('GemaraReferenceRule — שני matches באותה שורה', () {
    test('start/end נכונים לפי match.start ולא indexOf', () async {
      const line = 'ראה ברכות ב. וגם שבת כ.';
      final refs = await _detect(line);
      expect(refs, hasLength(2));

      // הראשון: ברכות ב.
      final first = refs.first;
      expect(first.targetBookTitle, equals('ברכות'));
      expect(line.substring(first.start, first.end), equals('ברכות ב.'));

      // השני: שבת כ.
      final second = refs.last;
      expect(second.targetBookTitle, equals('שבת'));
      expect(line.substring(second.start, second.end), equals('שבת כ.'));

      // חשוב: start/end שונים
      expect(second.start, greaterThan(first.end));
    });

    test('שתי הפניות זהות באותה שורה מקבלות מיקומים שונים', () async {
      const line = 'ברכות ב. ואחר כך ברכות ב.';
      final refs = await _detect(line);
      expect(refs, hasLength(2));
      expect(refs.first.start, isNot(equals(refs.last.start)));
    });
  });

  group('GemaraReferenceRule — מסכת עם מילת מסכת', () {
    test('מסכת ברכות ב.', () async {
      final refs = await _detect('מסכת ברכות ב.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ברכות'));
    });
  });

  group('GemaraReferenceRule — סוגריים בין מסכת לדף', () {
    test('דיבמות (דף ד ע"א)', () async {
      final refs = await _detect('כאן הוכיח בתוס׳ פ"ק דיבמות (דף ד ע"א)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('יבמות'));
      expect(refs.first.targetRefText, equals('ד א'));
    });

    test('בברכות (דף כ ע"א ד"ה...)', () async {
      final refs =
          await _detect('וכדאיתא בתוס׳ בברכות (דף כ ע"א ד"ה שב ואל תעשה)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ברכות'));
      expect(refs.first.targetRefText, equals('כ א'));
    });

    test('שבת (דף מז ד"ה...) — דף ללא עמוד לפני ד"ה', () async {
      final refs = await _detect('עצמו כתב בשבת (דף מז ד"ה אגב)');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שבת'));
      expect(refs.first.targetRefText, equals('מז'));
    });

    test('שבת [דף לט ע"ב ד"ה...] — סוגר מרובע לא סגור', () async {
      final refs = await _detect('ובתו׳ פ"ג דשבת [דף לט ע"ב ד"ה וב"ה');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שבת'));
      expect(refs.first.targetRefText, equals('לט ב'));
    });

    test('חגיגה דף י"ז בתוך סוגריים עם טקסט מקדים', () async {
      final refs = await _detect('[אב"ה עיין מ"ש לקמן במסכת חגיגה דף י"ז]:');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('חגיגה'));
      expect(refs.first.targetRefText, equals('יז'));
    });
  });

  group('GemaraReferenceRule — לעיל/לקמן באותו ספר', () {
    test('לעיל [דף כא סוף ע"ב]', () async {
      const ctx = GeneratedLinkRuleContext(
        sourceBookId: 110,
        sourceBookTitle: 'ראש השנה',
      );
      final refs =
          await _detectWithContext('דהא ר"ה קאמר לעיל [דף כא סוף ע"ב]', ctx);
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ראש השנה'));
      expect(refs.first.targetRefText, equals('כא ב'));
    });

    test('לקמן דף יז.', () async {
      const ctx = GeneratedLinkRuleContext(
        sourceBookId: 114,
        sourceBookTitle: 'חגיגה',
      );
      final refs = await _detectWithContext('ועיין לקמן דף יז.', ctx);
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('חגיגה'));
      expect(refs.first.targetRefText, equals('יז א'));
    });

    test("לקמן דף ד' ע\"א", () async {
      const ctx = GeneratedLinkRuleContext(
        sourceBookId: 102,
        sourceBookTitle: 'ביצה',
      );
      final refs = await _detectWithContext(
        "משמיה דרביה ס\"ל להכנה דרבה, [לקמן דף ד' ע\"א אתמר שבת ויו\"ט",
        ctx,
      );
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('ביצה'));
      expect(refs.first.targetRefText, equals('ד א'));
    });
  });

  group('GemaraReferenceRule — כינויי מסכת → שם קנוני', () {
    test('נידה ב. → targetBookTitle = נדה לפי שם הקטלוג', () async {
      final refs = await _detect('נידה ב.');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('נדה'));
    });
  });

  group('GemaraReferenceRule — hebrewToInt', () {
    test('ב = 2', () => expect(GemaraReferenceRule.hebrewToInt('ב'), 2));
    test('י = 10', () => expect(GemaraReferenceRule.hebrewToInt('י'), 10));
    test('טו = 15', () => expect(GemaraReferenceRule.hebrewToInt('טו'), 15));
    test('טז = 16', () => expect(GemaraReferenceRule.hebrewToInt('טז'), 16));
    test('כ = 20', () => expect(GemaraReferenceRule.hebrewToInt('כ'), 20));
    test(
        'קעו = 176', () => expect(GemaraReferenceRule.hebrewToInt('קעו'), 176));
    test('מחרוזת לא עברית מחזירה null',
        () => expect(GemaraReferenceRule.hebrewToInt('abc'), isNull));
  });
}
