import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_bar_button.dart';

/// בחלון צר הפאנל מכסה את כל החלון — כפתור הסגירה חייב להיראות ולסגור (#3031).
void main() {
  testWidgets('פאנל תצוגת הטקסט בחלון צר: נכנס לרוחב ונסגר ב-X', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
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
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    final panel = find.byType(TextDisplayPopupPanel);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, lessThan(420));

    final close = find.byTooltip('סגור');
    final closeRect = tester.getRect(close);
    expect(closeRect.left, greaterThanOrEqualTo(0));
    expect(closeRect.right, lessThanOrEqualTo(420));

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });
}
