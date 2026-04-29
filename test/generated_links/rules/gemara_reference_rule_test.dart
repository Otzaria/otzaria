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
