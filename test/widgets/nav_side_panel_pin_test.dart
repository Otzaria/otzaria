// #5202: כפתור נעיצת חלונית הניווט מוצג רק כשלחלונית יש מקום להידחק ליד
// התוכן. מחוץ לזה הנעיצה אינה עושה דבר, כי החלונית נפתחת כ-overlay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

Future<({bool canPin, bool? pushes})> _probe(
  WidgetTester tester, {
  required double width,
  required double paneWidth,
  required double minMain,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var canPin = false;
  bool? pushes;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            canPin = NavSidePanel.canPin(
              context,
              paneWidth: paneWidth,
              minMainContentWidth: minMain,
            );
            return NavSidePanel(
              isOpen: true,
              isPinned: true,
              paneWidth: paneWidth,
              minMainContentWidth: minMain,
              onClose: () {},
              onLayoutModeChanged: (v) => pushes = v,
              paneContent: const SizedBox(),
              mainContent: const SizedBox(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (canPin: canPin, pushes: pushes);
}

void main() {
  group('NavSidePanel.canPin זהה להחלטת הפריסה של החלונית', () {
    // (רוחב חלון, רוחב חלונית, מינימום לתוכן): כולל את הגבול בדיוק ומילימטר
    // מתחתיו, ואת שלוש הצורות שבהן המסכים משתמשים בחלונית.
    const cases = [
      (500.0, 340.0, 520.0), // טלפון/צר
      (700.0, 340.0, 520.0), // רחב מ-600, אך בלי מקום (קורא טקסט): הבאג
      (859.0, 340.0, 520.0), // מילימטר מתחת לגבול
      (860.0, 340.0, 520.0), // הגבול
      (1100.0, 340.0, 520.0), // רחב
      (650.0, 320.0, 500.0), // לשונית מפרשים: 820 נדרשים
      (820.0, 320.0, 500.0),
      (600.0, 400.0, 200.0), // PDF: מינימום 200 לתוכן
      (599.0, 400.0, 200.0),
    ];
    for (final (width, pane, min) in cases) {
      testWidgets('חלון $width, חלונית $pane, מינימום $min', (tester) async {
        final r = await _probe(
          tester,
          width: width,
          paneWidth: pane,
          minMain: min,
        );
        expect(
          r.canPin,
          r.pushes,
          reason: 'canPin=${r.canPin} pushes=${r.pushes}',
        );
        expect(r.canPin, width >= pane + min);
      });
    }
  });

  testWidgets('NavPanelPaneWidthScope גובר על רוחב החלון (תצוגה מפוצלת)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var canPin = true;
    await tester.pumpWidget(
      MaterialApp(
        home: NavPanelPaneWidthScope(
          width: 700,
          child: Builder(
            builder: (context) {
              canPin = NavSidePanel.canPin(
                context,
                paneWidth: 340,
                minMainContentWidth: 520,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(canPin, isFalse);
  });
}
