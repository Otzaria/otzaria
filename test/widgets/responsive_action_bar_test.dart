import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

void main() {
  testWidgets(
      'כשיש alwaysInMenu לא מציגים את כל הכפתורים אם עדיין צריך overflow',
      (tester) async {
    Widget buildAction(IconData icon, String tooltip) {
      return IconButton(
        onPressed: () {},
        icon: Icon(icon),
        tooltip: tooltip,
      );
    }

    final actions = [
      ActionButtonData(
        widget: buildAction(FluentIcons.book_24_regular, 'ספר'),
        icon: FluentIcons.book_24_regular,
        tooltip: 'ספר',
        onPressed: () {},
      ),
      ActionButtonData(
        widget: buildAction(FluentIcons.search_24_regular, 'חיפוש'),
        icon: FluentIcons.search_24_regular,
        tooltip: 'חיפוש',
        onPressed: () {},
      ),
      ActionButtonData(
        widget: buildAction(FluentIcons.settings_24_regular, 'הגדרות'),
        icon: FluentIcons.settings_24_regular,
        tooltip: 'הגדרות',
        onPressed: () {},
      ),
    ];

    final alwaysInMenu = [
      ActionButtonData(
        widget: buildAction(FluentIcons.more_horizontal_24_regular, 'נוסף'),
        icon: FluentIcons.more_horizontal_24_regular,
        tooltip: 'נוסף',
        onPressed: () {},
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              actions: [
                ResponsiveActionBar(
                  actions: actions,
                  alwaysInMenu: alwaysInMenu,
                  maxVisibleButtons: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.book_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.search_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.settings_24_regular), findsNothing);
  });

  group('maxToolbarButtonsForWidth', () {
    test('מסך צר מאוד מחזיר 0 כפתורים (רק overflow)', () {
      expect(maxToolbarButtonsForWidth(260), 0);
      expect(maxToolbarButtonsForWidth(200), 0);
    });

    test('מסכי מובייל מציגים יותר כפתורים ככל שהרוחב גדל', () {
      // ככל שהרוחב גדל, מספר הכפתורים לא יורד
      final w360 = maxToolbarButtonsForWidth(360);
      final w400 = maxToolbarButtonsForWidth(400);
      final w500 = maxToolbarButtonsForWidth(500);
      expect(w360, lessThanOrEqualTo(w400));
      expect(w400, lessThanOrEqualTo(w500));
      // 360px: (360-260)/44 = 2
      expect(w360, 2);
    });

    test('מסך רחב מציג הרבה כפתורים', () {
      expect(maxToolbarButtonsForWidth(1400), greaterThan(20));
    });
  });
}
