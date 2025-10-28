import 'package:flutter_test/flutter_test.dart';
import 'package:shamor_zachor/utils/category_aliases.dart';

void main() {
  group('CategoryAliases', () {
    test('normalize maps legacy names to new display names', () {
      expect(CategoryAliases.normalize('תנך'), 'תנ"ך');
      expect(CategoryAliases.normalize('ש"ס'), 'תלמוד בבלי');
      expect(CategoryAliases.normalize('ירושלמי'), 'תלמוד ירושלמי');
      // unchanged
      expect(CategoryAliases.normalize('משנה'), 'משנה');
    });

    test('legacyAliasesForNew returns the old keys', () {
      expect(CategoryAliases.legacyAliasesForNew('תנ"ך'), contains('תנך'));
      expect(CategoryAliases.legacyAliasesForNew('תלמוד בבלי'), contains('ש"ס'));
      expect(CategoryAliases.legacyAliasesForNew('תלמוד ירושלמי'), contains('ירושלמי'));
      expect(CategoryAliases.legacyAliasesForNew('משנה'), isEmpty);
    });
  });
}
