import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/window_persistence.dart';

void main() {
  // מסך ראשי 1920x1080 ומסך משני משמאלו, בפיקסלים פיזיים.
  const primary = Rect.fromLTWH(0, 0, 1920, 1040);
  const secondary = Rect.fromLTWH(-1920, 0, 1920, 1040);
  const strip = 32.0;

  bool reachable(Rect bounds, List<Rect> displays, {double extent = strip}) =>
      WindowPersistence.titleStripReachableOnAnyDisplay(
        bounds,
        displays,
        extent,
      );

  group('WindowPersistence.titleStripReachableOnAnyDisplay', () {
    test('חלון בתוך המסך הראשי — נגיש', () {
      const bounds = Rect.fromLTWH(100, 100, 1280, 720);
      expect(reachable(bounds, [primary]), isTrue);
    });

    test('גבולות חניה של חלון ממוזער (-32000) — לא נגישים', () {
      const bounds = Rect.fromLTWH(-32000, -32000, 420, 400);
      expect(reachable(bounds, [primary, secondary]), isFalse);
    });

    test('חלון על מסך משני שנותק — לא נגיש', () {
      const bounds = Rect.fromLTWH(-1800, 200, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
      expect(reachable(bounds, [primary, secondary]), isTrue);
    });

    test('רק פינת החלון התחתונה על המסך — פס הכותרת בחוץ, לא נגיש', () {
      const bounds = Rect.fromLTWH(1888, -688, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
    });

    test('פס הכותרת על המסך גם כשרוב החלון בחוץ — נגיש', () {
      const bounds = Rect.fromLTWH(1888, 1000, 1280, 720);
      expect(reachable(bounds, [primary]), isTrue);
    });

    test('פס הכותרת מעל קצה המסך העליון — לא ניתן לאחיזה, לא נגיש', () {
      const bounds = Rect.fromLTWH(100, -20, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
    });

    test('חפיפה אופקית צרה מרצועת האחיזה — לא נגיש', () {
      const bounds = Rect.fromLTWH(1910, 100, 1280, 720);
      expect(reachable(bounds, [primary]), isFalse);
    });

    test('רצועה בקנה מידה פיזי (DPR 1.5) נבדקת לפי ההיקף שסופק', () {
      const bounds = Rect.fromLTWH(1876, 100, 1280, 720);
      expect(reachable(bounds, [primary], extent: strip * 1.5), isFalse);
      expect(reachable(bounds, [primary], extent: strip), isTrue);
    });

    test('רשימת מסכים ריקה — לא נגיש', () {
      const bounds = Rect.fromLTWH(100, 100, 1280, 720);
      expect(reachable(bounds, const []), isFalse);
    });
  });
}
