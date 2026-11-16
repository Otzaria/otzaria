import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/utils/tab_swipe_settle.dart';

void main() {
  int settle({
    required double page,
    double? dragged,
    required int anchor,
    double velocity = 0,
    int tabCount = 5,
  }) => tabSwipeSettleIndex(
    page: page,
    anchorIndex: anchor,
    draggedPages: dragged ?? page - anchor,
    pageVelocity: velocity,
    tabCount: tabCount,
  );

  group('tabSwipeSettleIndex', () {
    test('גרירה איטית מתיישבת על העמוד הקרוב', () {
      expect(settle(page: 2.4, anchor: 2), 2);
      expect(settle(page: 2.6, anchor: 2), 3);
    });

    test('הנפה מעבירה לטאב הסמוך בכיוון ההנפה', () {
      expect(settle(page: 2.05, anchor: 2, velocity: 600), 3);
      expect(settle(page: 1.95, anchor: 2, velocity: -600), 1);
    });

    test('גרירה קדימה והנפה חזרה נשארת בטאב', () {
      expect(settle(page: 2.3, anchor: 2, velocity: -600), 2);
    });

    test('הנפה באמצע אנימציה נמדדת מהטאב הנבחר (#5211)', () {
      // הטאב הנבחר 3, התצוגה עוד ב-2.59 בדרך אליו.
      expect(settle(page: 2.68, dragged: 0.09, anchor: 3, velocity: 600), 4);
      expect(settle(page: 1.32, dragged: -0.09, anchor: 1, velocity: -600), 0);
      // הנפה חזרה באמצע האנימציה חוזרת לטאב שממנו יצאה הקודמת.
      expect(settle(page: 2.5, dragged: -0.09, anchor: 3, velocity: -600), 2);
    });

    test('לא חורג מגבולות הטאבים', () {
      expect(settle(page: 4.05, anchor: 4, velocity: 600), 4);
      expect(settle(page: -0.05, anchor: 0, velocity: -600), 0);
    });
  });
}
