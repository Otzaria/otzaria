import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_bar_button.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// בחלון צר הפאנל מכסה את כל החלון — כפתור הסגירה חייב להיראות ולסגור (#3031).
void main() {
  for (final width in [420.0, 900.0]) {
    testWidgets('פאנל תצוגת הטקסט ברוחב $width: נכנס לרוחב ונסגר ב-X', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
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
      expect(tester.getSize(panel).width, lessThan(width));

      final close = find.byTooltip('סגור');
      final closeRect = tester.getRect(
        find.ancestor(of: close, matching: find.byType(IconButton)),
      );
      expect(
        closeRect.left,
        closeTo(tester.getRect(panel).left + AppTokens.spaceMD, 0.01),
      );
      expect(
        find.descendant(of: close, matching: find.byType(Text)),
        findsNothing,
      );
      expect(closeRect.left, greaterThanOrEqualTo(0));
      expect(closeRect.right, lessThanOrEqualTo(width));

      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    });
  }
}
