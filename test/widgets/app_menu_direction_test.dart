import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// בודק שהתפריטים המעוגנים משמרים את ה-Directionality של הפותח.
///
/// התפריטים נבנים ב-route של ה-Navigator ולכן אינם יורשים את הכיוון של מי
/// שפתח אותם — למשל מסך ההגדרות באנגלית (LTR) בתוך אפליקציה RTL (issue #805).
void main() {
  Future<void> pumpAnchor(
    WidgetTester tester, {
    required TextDirection openerDirection,
    required Future<void> Function(BuildContext anchorContext) onPressed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Directionality(
                textDirection: openerDirection,
                child: SizedBox(
                  width: 240,
                  child: Builder(
                    builder: (anchorContext) => ElevatedButton(
                      onPressed: () => onPressed(anchorContext),
                      child: const Text('פתח'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextDirection directionAt(WidgetTester tester, String text) =>
      Directionality.of(tester.element(find.text(text)));

  group('showAnchoredAppMenu', () {
    Future<void> openMenu(
      WidgetTester tester,
      TextDirection openerDirection,
    ) async {
      await pumpAnchor(
        tester,
        openerDirection: openerDirection,
        onPressed: (anchorContext) => showAnchoredAppMenu<int>(
          context: anchorContext,
          anchorContext: anchorContext,
          itemsBuilder: (metrics) => [
            buildAppPopupMenuItem<int>(
              anchorContext,
              const AppMenuEntry<int>(value: 1, label: 'פריט ראשון'),
              metrics,
              null,
            ),
          ],
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    }

    testWidgets('פותח LTR — פריטי התפריט מקבלים LTR', (tester) async {
      await openMenu(tester, TextDirection.ltr);
      expect(directionAt(tester, 'פריט ראשון'), TextDirection.ltr);
    });

    testWidgets('פותח RTL — פריטי התפריט נשארים RTL', (tester) async {
      await openMenu(tester, TextDirection.rtl);
      expect(directionAt(tester, 'פריט ראשון'), TextDirection.rtl);
    });
  });

  group('showAnchoredAppSearchMenu', () {
    // ארוכה מהעוגן (240px) אך צרה מהמסך — כדי שליישור יהיה כיוון מובחן.
    // בפונט הבדיקה (Ahem) כל תו ברוחב em מלא, לכן התווית קצרה יחסית.
    const wideLabel = 'תווית רחבה מהעוגן קצת';

    Future<void> openMenu(
      WidgetTester tester,
      TextDirection openerDirection,
    ) async {
      await pumpAnchor(
        tester,
        openerDirection: openerDirection,
        onPressed: (anchorContext) => showAnchoredAppSearchMenu<int>(
          context: anchorContext,
          anchorContext: anchorContext,
          entries: const [
            AppMenuEntry<int>(value: 1, label: wideLabel),
          ],
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    }

    Rect menuRect(WidgetTester tester) => tester.getRect(
      find.byWidgetPredicate(
        (w) => w is Material && w.elevation == AppTokens.elevation2,
      ),
    );

    testWidgets('פותח LTR — תוכן התפריט LTR ומיושר לקצה השמאלי של העוגן', (
      tester,
    ) async {
      await openMenu(tester, TextDirection.ltr);

      expect(directionAt(tester, wideLabel), TextDirection.ltr);
      final anchorRect = tester.getRect(find.byType(ElevatedButton));
      final menu = menuRect(tester);
      expect(
        menu.width,
        greaterThan(anchorRect.width),
        reason:
            'התווית אמורה להרחיב את התפריט מעבר לעוגן כדי שליישור יהיה כיוון',
      );
      expect(
        menu.left,
        moreOrLessEquals(anchorRect.left, epsilon: 1),
        reason: 'ב-LTR התפריט מתרחב ימינה מקצה ההתחלה של העוגן',
      );
    });

    testWidgets('פותח RTL — תוכן התפריט RTL ומיושר לקצה הימני של העוגן', (
      tester,
    ) async {
      await openMenu(tester, TextDirection.rtl);

      expect(directionAt(tester, wideLabel), TextDirection.rtl);
      final anchorRect = tester.getRect(find.byType(ElevatedButton));
      final menu = menuRect(tester);
      expect(
        menu.width,
        greaterThan(anchorRect.width),
        reason:
            'התווית אמורה להרחיב את התפריט מעבר לעוגן כדי שליישור יהיה כיוון',
      );
      expect(
        menu.right,
        moreOrLessEquals(anchorRect.right, epsilon: 1),
        reason: 'ב-RTL התפריט מתרחב שמאלה מקצה ההתחלה של העוגן',
      );
    });
  });
}
