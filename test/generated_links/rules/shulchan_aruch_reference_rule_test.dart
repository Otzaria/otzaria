import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/rules/shulchan_aruch_reference_rule.dart';

final _ctx = const GeneratedLinkRuleContext(
  sourceBookId: 1,
  sourceBookTitle: 'test',
);

Future<List<DetectedReference>> _detect(String line) async {
  final rule = ShulchanAruchReferenceRule();
  return rule.detect(_ctx, [line], const LineRange(0, 0));
}

void main() {
  group('ShulchanAruchReferenceRule — חלק וסימן', () {
    test('ביו"ד סי׳ פג → שולחן ערוך יורה דעה סימן פג', () async {
      final refs = await _detect('עיין ביו"ד סי׳ פג בדין זה');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שולחן ערוך, יורה דעה'));
      expect(refs.first.targetRefText, equals('סימן פג'));
    });

    test('באו"ח סימן כ"ה → שולחן ערוך אורח חיים סימן כה', () async {
      final refs = await _detect('ראה באו"ח סימן כ"ה');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שולחן ערוך, אורח חיים'));
      expect(refs.first.targetRefText, equals('סימן כה'));
    });

    test('בחו"מ סי׳ יב → שולחן ערוך חושן משפט', () async {
      final refs = await _detect('עי׳ בחו"מ סי׳ יב');
      expect(refs, hasLength(1));
      expect(refs.first.targetBookTitle, equals('שולחן ערוך, חושן משפט'));
      expect(refs.first.targetRefText, equals('סימן יב'));
    });
  });

  group('ShulchanAruchReferenceRule — ש"ך ס"ק', () {
    test('ביו"ד סי׳ פג בש"ך ס"ק טו', () async {
      final refs = await _detect(
        'צינו גבי דגים מלוחים, [אב"ה ביו"ד סי׳ פג בש"ך ס"ק טו ו',
      );
      expect(refs, hasLength(2));

      expect(refs.first.targetBookTitle, equals('שולחן ערוך, יורה דעה'));
      expect(refs.first.targetRefText, equals('סימן פג'));

      expect(
        refs.last.targetBookTitle,
        equals('שפתי כהן על שולחן ערוך יורה דעה'),
      );
      expect(refs.last.targetRefText, equals('סימן פג סעיף טו'));
      expect(refs.last.matchedText, equals('בש"ך ס"ק טו'));
    });

    test('בחו"מ סי׳ יב בשך ס"ק ג', () async {
      final refs = await _detect('ועיין בחו"מ סי׳ יב בשך ס"ק ג');
      expect(refs, hasLength(2));
      expect(
        refs.last.targetBookTitle,
        equals('שפתי כהן על שולחן ערוך חושן משפט'),
      );
      expect(refs.last.targetRefText, equals('סימן יב סעיף ג'));
    });
  });
}
