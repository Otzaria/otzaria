// רוחב הטקסט הוא רוחב יעד קבוע: שינוי גודל חלון או פתיחת/סגירת חלונית צד לא
// משנים את העמודה כל עוד יש מקום, והיא מצטמצמת רק כשאין.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/reading_area_width.dart';

void main() {
  group('resolveTextColumnMaxWidth', () {
    test('יעד נשמר כשיש מקום', () {
      expect(
        resolveTextColumnMaxWidth(setting: 700, availableWidth: 1200),
        700,
      );
    });

    test('מצטמצם לרוחב הפנוי פחות שוליים מזעריים כשאין מקום', () {
      expect(
        resolveTextColumnMaxWidth(setting: 700, availableWidth: 600),
        600 - 2 * kTextColumnMinMargin,
      );
    });

    test('0 = רוחב מלא, בלי שוליים', () {
      expect(resolveTextColumnMaxWidth(setting: 0, availableWidth: 600), 0);
    });

    test('ערך שלילי (רמת אחוזים ישנה) נחשב רוחב מלא', () {
      expect(resolveTextColumnMaxWidth(setting: -11, availableWidth: 1200), 0);
    });
  });

  /// מחזיר את רוחב העמודה שמחושב מהרוחב שהתוכן מקבל בפועל.
  Widget measuringContent(void Function(double) onColumn) => LayoutBuilder(
    builder: (context, constraints) {
      onColumn(
        resolveTextColumnMaxWidth(
          setting: 400,
          availableWidth: constraints.maxWidth,
        ),
      );
      return const SizedBox.expand();
    },
  );

  testWidgets('פתיחת AdaptiveSidePane לא משנה את העמודה כשיש מקום', (
    tester,
  ) async {
    double? column;
    final isOpen = ValueNotifier<bool>(false);
    addTearDown(isOpen.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: ValueListenableBuilder<bool>(
              valueListenable: isOpen,
              builder: (context, open, _) => AdaptiveSidePane(
                isOpen: open,
                onClose: () => isOpen.value = false,
                paneWidth: 200,
                minMainContentWidth: 300,
                paneContent: const SizedBox.expand(),
                mainContent: measuringContent((w) => column = w),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(column, 400);

    isOpen.value = true;
    await tester.pumpAndSettle();
    expect(column, 400);

    isOpen.value = false;
    await tester.pumpAndSettle();
    expect(column, 400);
  });

  testWidgets('חלונית שכנה ב-Row (כמו לוח הכרטיסיות) לא משנה את העמודה', (
    tester,
  ) async {
    double? column;
    final panelOpen = ValueNotifier<bool>(true);
    addTearDown(panelOpen.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: ValueListenableBuilder<bool>(
              valueListenable: panelOpen,
              builder: (context, open, _) => Row(
                children: [
                  if (open) const SizedBox(width: 250),
                  Expanded(child: measuringContent((w) => column = w)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(column, 400);

    panelOpen.value = false;
    await tester.pump();
    expect(column, 400);
  });
}
