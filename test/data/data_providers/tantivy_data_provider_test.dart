import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';

void main() {
  group('TantivyDataProvider.isRebuildRequiredStatus', () {
    test('מחזיר true כשהאינדקס ישן מדי עבור המנוע (rebuild_required)', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('rebuild_required'),
        isTrue,
      );
    });

    test('מחזיר true כשהאינדקס נוצר ע"י מנוע חדש יותר (engine_too_old)', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('engine_too_old'),
        isTrue,
      );
    });

    test('מחזיר false לאינדקס תקין', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('compatible'),
        isFalse,
      );
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('legacy_compatible'),
        isFalse,
      );
    });

    test('מחזיר false כשאין אינדקס - אינדוקס רגיל יבנה אותו', () {
      expect(
        TantivyDataProvider.isRebuildRequiredStatus('missing_index'),
        isFalse,
      );
    });

    test('מחזיר false כשבדיקת התאימות לא רצה (null)', () {
      expect(TantivyDataProvider.isRebuildRequiredStatus(null), isFalse);
    });
  });
}
