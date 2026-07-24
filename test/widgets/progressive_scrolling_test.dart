import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// מקליט קריאות גלילה במקום להזיז רשימה אמיתית.
class _RecordingScrollOffsetController extends ScrollOffsetController {
  final List<double> offsets = [];

  @override
  Future<void> animateScroll({
    required double offset,
    required Duration duration,
    Curve curve = Curves.linear,
  }) async {
    offsets.add(offset);
  }
}

/// מדמה רשימה מחוברת כדי ש-ProgressiveScroll יסכים לגלול.
class _AttachedItemScrollController extends ItemScrollController {
  @override
  bool get isAttached => true;
}

void main() {
  late _RecordingScrollOffsetController offsetController;
  late FocusNode focusNode;

  Future<void> pumpProgressiveScroll(WidgetTester tester) async {
    offsetController = _RecordingScrollOffsetController();
    focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProgressiveScroll(
          scrollController: offsetController,
          itemScrollController: _AttachedItemScrollController(),
          focusNode: focusNode,
          child: const SizedBox.expand(),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
  }

  testWidgets('ללא לחיצת מקש — אין שום קריאת גלילה', (tester) async {
    // רגרסיה: בעבר טיימר תמידי רץ כל 16ms גם בלי שום לחיצה.
    await pumpProgressiveScroll(tester);

    await tester.pump(const Duration(seconds: 1));

    expect(offsetController.offsets, isEmpty);
  });

  testWidgets('לחיצת חץ גוללת ושחרור עוצר את הגלילה', (tester) async {
    await pumpProgressiveScroll(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(offsetController.offsets, isNotEmpty);
    expect(offsetController.offsets.every((offset) => offset > 0), isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // שחרור מוסיף גלישה עדינה אחת (glide) של 100 בכיוון הגלילה
    expect(offsetController.offsets.last, 100.0);

    final countAfterRelease = offsetController.offsets.length;
    await tester.pump(const Duration(seconds: 1));
    expect(
      offsetController.offsets.length,
      countAfterRelease,
      reason: 'אחרי שחרור המקש אסור שתימשך גלילה',
    );
  });

  testWidgets('איבוד פוקוס באמצע לחיצה עוצר את הגלילה', (tester) async {
    // הבאג שתוקן: מעבר פוקוס בולע את ה-KeyUp, והגלילה המשיכה לבד לנצח
    // ו"נלחמה" בגלילת המשתמש.
    await pumpProgressiveScroll(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(offsetController.offsets, isNotEmpty);

    focusNode.unfocus();
    await tester.pump();
    final countAfterUnfocus = offsetController.offsets.length;

    await tester.pump(const Duration(seconds: 2));
    expect(
      offsetController.offsets.length,
      countAfterUnfocus,
      reason: 'איבוד פוקוס חייב לעצור את הגלילה גם בלי KeyUp',
    );

    // ניקוי מצב המקלדת של סביבת הטסט (ה-widget כבר לא בפוקוס)
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  });
}
