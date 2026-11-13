import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tour/widgets/tour_progress_dots.dart';

/// UI-031: נקודות ההתקדמות נגישות למקלדת ולקורא מסך.
void main() {
  testWidgets('נקודה מקבלת פוקוס ב-Tab, Enter מפעיל, ויש לה שם נגיש', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TourProgressDots(
              currentIndex: 0,
              total: 3,
              onDotTap: tapped.add,
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapped, [1]);

    expect(
      tester.getSemantics(find.bySemanticsLabel('שלב 1 מתוך 3')),
      matchesSemantics(
        label: 'שלב 1 מתוך 3',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });
}
