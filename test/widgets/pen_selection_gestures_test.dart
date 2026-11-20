import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// עט בוחר טקסט בגרירה כמו עכבר (סעיף 9), ולא גולל כמו אצבע.
void main() {
  const text = 'טקסט שנבחר בגרירה של עט';

  Widget harness(Widget child) => MaterialApp(
    locale: const Locale('he', 'IL'),
    theme: ThemeData(platform: TargetPlatform.windows),
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: AppSelectionArea(child: child),
      ),
    ),
  );

  /// גרירה אופקית מעל כל הטקסט, מקצהו הימני אל מעבר לקצהו השמאלי.
  Future<void> dragAcrossText(
    WidgetTester tester,
    PointerDeviceKind kind,
  ) async {
    final rect = tester.getRect(find.text(text));
    final y = rect.center.dy;
    final gesture = await tester.startGesture(
      Offset(rect.right - 5, y),
      kind: kind,
    );
    await tester.pump();
    for (var x = rect.right - 5; x > rect.left; x -= 25) {
      await gesture.moveTo(Offset(x, y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.moveTo(Offset(rect.left + 5, y));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// רוחב הבחירה הנוכחית של האזור בפיקסלים; 0 כשאין בחירה.
  double selectionWidth(WidgetTester tester) {
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    try {
      final points = region.selectionEndpoints;
      if (points.length < 2) return 0;
      return (points.first.point.dx - points.last.point.dx).abs();
    } on TypeError {
      // ב-Flutter ה-getter מפעיל null assertion כשאין קצוות בחירה.
      return 0;
    }
  }

  testWidgets('גרירה בעט בוחרת את הטקסט כמו בעכבר', (tester) async {
    await tester.pumpWidget(harness(const Text(text)));
    await tester.pumpAndSettle();

    await dragAcrossText(tester, PointerDeviceKind.stylus);

    expect(
      selectionWidth(tester),
      greaterThan(tester.getSize(find.text(text)).width - 25),
      reason: 'כל הטקסט נבחר',
    );
  });

  testWidgets('קצה הנעילה של העט (invertedStylus) נחשב גם הוא כעכבר', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const Text(text)));
    await tester.pumpAndSettle();

    await dragAcrossText(tester, PointerDeviceKind.invertedStylus);

    expect(
      selectionWidth(tester),
      greaterThan(tester.getSize(find.text(text)).width - 25),
      reason: 'כל הטקסט נבחר',
    );
  });

  testWidgets('גרירה בעט מעל טקסט בתוך רשימה בוחרת ולא גוללת אותה', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: ListView(
              controller: controller,
              children: [
                AppSelectionArea(child: const Text(text)),
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 48, child: Text('$i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.text(text));
    final gesture = await tester.startGesture(
      Offset(rect.right - 1, rect.center.dy),
      kind: PointerDeviceKind.stylus,
    );
    // תנועה בעיקר אנכית: באצבע (ובעט, בלי התיקון) זו גלילה.
    await gesture.moveBy(const Offset(-4, -30));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-4, -40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.offset, 0, reason: 'עט לא גולל בגרירה, כמו עכבר');
  });

  testWidgets('גרירה באצבע לא בוחרת טקסט (ללא שינוי)', (tester) async {
    await tester.pumpWidget(harness(const Text(text)));
    await tester.pumpAndSettle();

    await dragAcrossText(tester, PointerDeviceKind.touch);

    expect(selectionWidth(tester), 0);
  });

  testWidgets('גרירה בעכבר עדיין בוחרת טקסט (ללא שינוי)', (tester) async {
    await tester.pumpWidget(harness(const Text(text)));
    await tester.pumpAndSettle();

    await dragAcrossText(tester, PointerDeviceKind.mouse);

    expect(
      selectionWidth(tester),
      greaterThan(tester.getSize(find.text(text)).width - 25),
      reason: 'כל הטקסט נבחר',
    );
  });
}
