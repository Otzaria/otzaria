import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/category.dart';

void main() {
  group('Category', () {
    test('fromJson קורא את שני תיאורי הקטגוריה', () {
      final category = Category.fromJson({
        'id': 7,
        'parentId': 3,
        'title': 'הלכה',
        'level': 1,
        'orderIndex': 4,
        'heShortDesc': 'תיאור קצר',
        'heDesc': 'תיאור מורחב',
      });

      expect(category.heShortDesc, 'תיאור קצר');
      expect(category.heDesc, 'תיאור מורחב');
    });

    test('fromJson תומך בשורת DB ישנה ללא עמודות תיאור', () {
      final category = Category.fromJson({
        'id': 7,
        'title': 'הלכה',
      });

      expect(category.heShortDesc, isNull);
      expect(category.heDesc, isNull);
    });

    test('copyWith שומר תיאורים שלא סופקו ומנקה כל תיאור במפורש', () {
      const original = Category(
        title: 'הלכה',
        heShortDesc: 'תיאור קצר',
        heDesc: 'תיאור מורחב',
      );

      final kept = original.copyWith();
      final shortCleared = original.copyWith(clearHeShortDesc: true);
      final fullCleared = original.copyWith(clearHeDesc: true);

      expect(kept.heShortDesc, 'תיאור קצר');
      expect(kept.heDesc, 'תיאור מורחב');
      expect(shortCleared.heShortDesc, isNull);
      expect(shortCleared.heDesc, 'תיאור מורחב');
      expect(fullCleared.heShortDesc, 'תיאור קצר');
      expect(fullCleared.heDesc, isNull);
    });
  });
}
