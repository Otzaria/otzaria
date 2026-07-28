import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _itemHeight = 40.0;
const _itemCount = 500;
const _viewportHeight = 600.0;
const _notch = 100.0;

void main() {
  late ItemScrollController itemController;
  late ScrollOffsetController offsetController;
  late ItemPositionsListener positions;
  var itemBuilds = 0;

  Widget buildList({bool smooth = true}) {
    itemController = ItemScrollController();
    offsetController = ScrollOffsetController();
    positions = ItemPositionsListener.create();
    itemBuilds = 0;

    final list = ScrollablePositionedList.builder(
      itemScrollController: itemController,
      scrollOffsetController: offsetController,
      itemPositionsListener: positions,
      itemCount: _itemCount,
      itemBuilder: (context, index) {
        itemBuilds++;
        return SizedBox(height: _itemHeight, child: Text('שורה $index'));
      },
    );

    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: _viewportHeight,
          width: 400,
          child: smooth ? SmoothWheelScroll(child: list) : list,
        ),
      ),
    );
  }

  /// האופסט האבסולוטי ביחידות פיקסלים, מחושב ממיקומי הפריטים (שהם היחידים
  /// שנשארים נכונים גם אחרי החלפת עוגן).
  double offset() {
    final first = positions.itemPositions.value.reduce(
      (a, b) => a.index < b.index ? a : b,
    );
    return first.index * _itemHeight - first.itemLeadingEdge * _viewportHeight;
  }

  void wheel(
    WidgetTester tester, {
    double dy = _notch,
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) {
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ScrollablePositionedList)),
        scrollDelta: Offset(0, dy),
        kind: kind,
      ),
    );
  }

  Future<void> frames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('נקישה בודדת', () {
    testWidgets('התזוזה נפרסת על פריימים ואינה קפיצה אחת', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      wheel(tester);
      await tester.pump(const Duration(milliseconds: 16));
      final afterFirstFrame = offset();

      expect(
        afterFirstFrame,
        greaterThan(0.0),
        reason: 'הפריים הראשון חייב להתחיל לזוז',
      );
      expect(
        afterFirstFrame,
        lessThan(_notch * 0.5),
        reason: 'קפיצה של יותר מחצי הדרך בפריים אחד = הגלגלת לא נחטפה',
      );
    });

    testWidgets('הנחיתה היא בדיוק על אותו מרחק שהגלגלת ביקשה', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      wheel(tester);
      await tester.pumpAndSettle();

      expect(offset(), closeTo(_notch, 0.01));
    });

    testWidgets('התנועה מונוטונית — אין ריצוד או חזרה אחורה', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      wheel(tester);
      var previous = offset();
      var moved = false;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final current = offset();
        expect(
          current,
          greaterThanOrEqualTo(previous - 0.01),
          reason: 'תזוזה אחורה בפריים $i',
        );
        if (current > previous) moved = true;
        previous = current;
      }
      expect(moved, isTrue);
    });
  });

  group('נקישות רצופות', () {
    // מלכודת: שרשור נאיבי של animateScroll מודד מהמקום הנוכחי שעוד לא הגיע,
    // ואיבד 75% מהגלילה. היעד המצטבר הוא מה ששומר על המרחק המלא.
    testWidgets('ארבע נקישות באמצע החלקה = בדיוק ארבעה מרחקים', (
      tester,
    ) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      for (var n = 0; n < 4; n++) {
        wheel(tester);
        await frames(tester, 3);
      }
      await tester.pumpAndSettle();

      expect(offset(), closeTo(_notch * 4, 0.01));
    });

    testWidgets('החלקה אינה מוסיפה בניות פריטים מעל קפיצה', (tester) async {
      await tester.pumpWidget(buildList(smooth: false));
      await tester.pumpAndSettle();
      final jumpBase = itemBuilds;
      for (var n = 0; n < 4; n++) {
        wheel(tester);
        await frames(tester, 4);
      }
      await tester.pumpAndSettle();
      final jumpBuilds = itemBuilds - jumpBase;

      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();
      final smoothBase = itemBuilds;
      for (var n = 0; n < 4; n++) {
        wheel(tester);
        await frames(tester, 4);
      }
      await tester.pumpAndSettle();
      final smoothBuilds = itemBuilds - smoothBase;

      expect(smoothBuilds, lessThanOrEqualTo(jumpBuilds));
    });
  });

  group('קצות הרשימה', () {
    testWidgets('בראש הרשימה גלילה למעלה אינה מזיזה', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      wheel(tester, dy: -_notch);
      await tester.pumpAndSettle();

      expect(offset(), 0.0);
    });

    testWidgets('בסוף הרשימה נעצר בקצה בלי חריגה', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      const maxOffset = _itemCount * _itemHeight - _viewportHeight;
      for (var n = 0; n < 250; n++) {
        wheel(tester);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(offset(), closeTo(maxOffset, 1.0));
    });
  });

  group('מה לא נחטף', () {
    testWidgets('משטח מגע נשאר במסלול המקורי — לו יש אינרציה', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      wheel(tester, kind: PointerDeviceKind.trackpad);
      await tester.pump(const Duration(milliseconds: 16));

      expect(offset(), closeTo(_notch, 0.01));
    });

    testWidgets('Ctrl+גלגלת נשאר במסלול המקורי', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      wheel(tester);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(offset(), closeTo(_notch, 0.01));
    });
  });

  group('שיתוף השליטה', () {
    testWidgets('קפיצה חיצונית באמצע החלקה עוצרת אותה ולא נלחמת בה', (
      tester,
    ) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      wheel(tester);
      await tester.pump(const Duration(milliseconds: 16));

      itemController.jumpTo(index: 300);
      await tester.pumpAndSettle();
      final afterJump = offset();

      await frames(tester, 10);

      expect(offset(), closeTo(afterJump, 0.01));
      expect(afterJump, closeTo(300 * _itemHeight, 0.01));
    });

    // מלכודת: עטיפה ב-render object מרובה-ילדים (Stack) מייצרת את הרשימה
    // החדשה לפני שחרור הקודמת, ואז ItemScrollController נצמד פעמיים וזורק.
    testWidgets('החלפת key של הרשימה אינה מכשילה את חיבור הבקרים', (
      tester,
    ) async {
      final sharedItemController = ItemScrollController();
      final sharedOffsetController = ScrollOffsetController();

      Widget keyed(String tag) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: _viewportHeight,
            width: 400,
            child: SmoothWheelScroll(
              child: ScrollablePositionedList.builder(
                key: ValueKey(tag),
                itemScrollController: sharedItemController,
                scrollOffsetController: sharedOffsetController,
                itemPositionsListener: positions,
                itemCount: _itemCount,
                itemBuilder: (context, index) =>
                    SizedBox(height: _itemHeight, child: Text('שורה $index')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(keyed('a'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(keyed('b'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('פירוק הווידג\'ט באמצע החלקה אינו זורק', (tester) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      wheel(tester);
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });
  });
}
