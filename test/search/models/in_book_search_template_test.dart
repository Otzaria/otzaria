import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';

void main() {
  test('תבנית מעתיקה קלט ושוויון/hash אינם תלויים בסדר המפה', () {
    final input = {'ראשי תיבות': true, 'קידומות דקדוקיות': false};
    final template = InBookSearchTemplate(
      wordDefaults: input,
      requestedPolicy: const SearchMatchPolicy(anyOrder: true),
    );
    input.clear();
    final equal = InBookSearchTemplate(
      wordDefaults: {'קידומות דקדוקיות': false, 'ראשי תיבות': true},
      requestedPolicy: const SearchMatchPolicy(anyOrder: true),
    );
    expect(template, equal);
    expect(template.hashCode, equal.hashCode);
    expect(() => template.wordDefaults!['אחר'] = true, throwsUnsupportedError);
    expect(InBookSearchTemplate.tryFromJson(template.toJson()), template);
  });

  test(
    'מדיניות פר-מילה נשמרת גם בלי תבנית מילים כשמילה אחת מצמצמת בכל סדר',
    () {
      final settings = const InBookSearchSettings(
        matchPolicy: SearchMatchPolicy(anyOrder: true),
      ).forQuery('ממון');
      expect(settings.matchPolicy.anyOrder, isFalse);
      final template = settings.template!;
      expect(template.wordDefaults, isNull);
      expect(template.requestedPolicy.anyOrder, isTrue);
      expect(InBookSearchTemplate.tryFromJson(template.toJson()), template);
      expect(const InBookSearchSettings().template, isNull);
    },
  );
}
