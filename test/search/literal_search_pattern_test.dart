import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';

void main() {
  group('normalizeLiteralQuery', () {
    test('מסיר ניקוד', () {
      expect(normalizeLiteralQuery('הֲרֵעֹתִי'), 'הרעתי');
    });

    test('ממיר מקף עברי לרווח — זהה לניקוי התוכן', () {
      expect(normalizeLiteralQuery('אשר־שמע'), 'אשר שמע');
    });

    test('ממיר פסק לרווח', () {
      expect(normalizeLiteralQuery('אשר ׀ שמע'), 'אשר שמע');
    });

    test('מכווץ רצפי רווח ומקצץ', () {
      expect(normalizeLiteralQuery('  שמע   ישראל  '), 'שמע ישראל');
    });
  });
}
