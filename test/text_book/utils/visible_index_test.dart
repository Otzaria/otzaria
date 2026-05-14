import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/visible_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

ItemPosition _pos(int index) =>
    ItemPosition(index: index, itemLeadingEdge: 0, itemTrailingEdge: 0);

void main() {
  group('topmostVisibleIndex', () {
    test('מחזיר 0 כשהקולקציה ריקה', () {
      expect(topmostVisibleIndex(const <ItemPosition>[]), 0);
    });

    test('מחזיר את האינדקס היחיד כשיש פריט אחד', () {
      expect(topmostVisibleIndex([_pos(42)]), 42);
    });

    test('מחזיר מינימום כשהפריטים בסדר עולה', () {
      expect(
        topmostVisibleIndex([_pos(10), _pos(11), _pos(12)]),
        10,
      );
    });

    test('מחזיר מינימום גם כשסדר האיטרציה הפוך לאינדקס (הבאג של .first)', () {
      // מדמה את התרחיש הבעייתי: itemPositions הוא Set שסדר ההכנסה שלו
      // אינו תואם לאינדקס. ב-.first נקבל 12, אבל הפריט העליון הוא 10.
      expect(
        topmostVisibleIndex([_pos(12), _pos(11), _pos(10)]),
        10,
      );
    });

    test('מחזיר מינימום בסדר ערבוב כללי', () {
      expect(
        topmostVisibleIndex([_pos(50), _pos(20), _pos(80), _pos(35)]),
        20,
      );
    });

    test('עובד עם אינדקסים שליליים (קצה תיאורטי)', () {
      expect(topmostVisibleIndex([_pos(-1), _pos(0), _pos(1)]), -1);
    });
  });

  group('bottommostVisibleIndex', () {
    test('מחזיר 0 כשהקולקציה ריקה', () {
      expect(bottommostVisibleIndex(const <ItemPosition>[]), 0);
    });

    test('מחזיר את האינדקס היחיד כשיש פריט אחד', () {
      expect(bottommostVisibleIndex([_pos(42)]), 42);
    });

    test('מחזיר מקסימום כשהפריטים בסדר עולה', () {
      expect(
        bottommostVisibleIndex([_pos(10), _pos(11), _pos(12)]),
        12,
      );
    });

    test('מחזיר מקסימום גם כשסדר האיטרציה לא תואם לאינדקס', () {
      // .last יחזיר 10, אבל הפריט התחתון הוא 12.
      expect(
        bottommostVisibleIndex([_pos(12), _pos(11), _pos(10)]),
        12,
      );
    });

    test('מחזיר מקסימום בסדר ערבוב כללי', () {
      expect(
        bottommostVisibleIndex([_pos(50), _pos(20), _pos(80), _pos(35)]),
        80,
      );
    });
  });

  group('עקביות עם ValueNotifier של ItemPositionsListener', () {
    test('עובד על ה-Iterable שמוחזר מ-ItemPositionsListener', () {
      final listener = ItemPositionsListener.create();
      (listener.itemPositions as dynamic).value = [
        _pos(7),
        _pos(5),
        _pos(9),
      ];

      expect(topmostVisibleIndex(listener.itemPositions.value), 5);
      expect(bottommostVisibleIndex(listener.itemPositions.value), 9);
    });
  });
}
