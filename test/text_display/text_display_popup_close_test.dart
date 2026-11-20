import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_bar_button.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

/// החלונית צרה ונכנסת גם לחלון צר (#3031). אין בה X: היא נסגרת ב-Esc
/// ובלחיצה מחוץ לה, כמו כל תפריט.
void main() {
  Future<void> pumpAndOpen(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showTextDisplayPopup(
                    context,
                    anchorContext: context,
                    panelBuilder: (_) => TextDisplayPopupPanel(
                      viewLabel: 'כרטיסיית מפרשים',
                      sections: [
                        TextDisplaySection(
                          title: 'גוף הספר',
                          profile: TextDisplayProfile.defaults,
                          onChanged: (_) {},
                        ),
                      ],
                      footer: 'הערה',
                    ),
                  ),
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
  }

  for (final width in [420.0, 900.0]) {
    testWidgets('חלונית תצוגת הטקסט ברוחב $width: נכנסת לרוחב, כותרת בלי X', (
      tester,
    ) async {
      await pumpAndOpen(tester, width);

      final panel = find.byType(TextDisplayPopupPanel);
      expect(panel, findsOneWidget);
      // התפריט של Material מעגל את הרוחב כלפי מעלה לכפולה של 56 —
      // 300 הופך ל-336.
      final panelWidth = tester.getSize(panel).width;
      expect(panelWidth, greaterThanOrEqualTo(TextDisplayPopupPanel.width));
      expect(panelWidth, lessThanOrEqualTo(TextDisplayPopupPanel.width + 56));
      final rect = tester.getRect(panel);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));

      // כותרת ושם התצוגה מתחתיה — בלי רצועת הדיאלוג ובלי כפתור סגירה.
      expect(
        find.descendant(of: panel, matching: find.text('תצוגת הטקסט')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('כרטיסיית מפרשים')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(AppDialogHeader)),
        findsNothing,
      );
      expect(find.byTooltip('סגור'), findsNothing);
      expect(
        find.descendant(of: panel, matching: find.byType(IconButton)),
        findsNothing,
      );
    });
  }

  testWidgets('Esc סוגר את החלונית', (tester) async {
    await pumpAndOpen(tester, 900);
    expect(find.byType(TextDisplayPopupPanel), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TextDisplayPopupPanel), findsNothing);
  });

  testWidgets('Esc סוגר רק את החלונית ולא את המסך שמתחתיה', (tester) async {
    // שני מטפלי Esc (גלובלי ובפוקוס) — אסור שיסגרו גם את ה-route שמתחת.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showTextDisplayPopup(
                        context,
                        anchorContext: context,
                        panelBuilder: (_) => TextDisplayPopupPanel(
                          viewLabel: 'תצוגה רגילה',
                          sections: [
                            TextDisplaySection(
                              title: 'גוף הספר',
                              profile: TextDisplayProfile.defaults,
                              onChanged: (_) {},
                            ),
                          ],
                          footer: 'הערה',
                        ),
                      ),
                      child: const Text('פתח'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('מסך שני'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('מסך שני'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    expect(find.byType(TextDisplayPopupPanel), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TextDisplayPopupPanel), findsNothing);
    expect(find.text('פתח'), findsOneWidget);
  });

  testWidgets('לחיצה מחוץ לחלונית סוגרת אותה', (tester) async {
    await pumpAndOpen(tester, 900);
    final panel = find.byType(TextDisplayPopupPanel);
    expect(panel, findsOneWidget);

    // פינה תחתונה של החלון — רחוק מהחלונית ומהכפתור.
    final rect = tester.getRect(panel);
    expect(rect.bottom, lessThan(690));
    await tester.tapAt(const Offset(10, 690));
    await tester.pumpAndSettle();

    expect(panel, findsNothing);
  });
}
