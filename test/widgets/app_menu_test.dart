import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

void main() {
  testWidgets('AppPopupMenuButton can open its menu through a GlobalKey', (
    tester,
  ) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPopupMenuButton<String>(
            key: key,
            entries: const [AppMenuEntry<String>(value: 'item', label: 'פריט')],
            child: const Text('פתח'),
          ),
        ),
      ),
    );

    final menuFuture = (key.currentState as dynamic).showMenu() as Future<void>;
    await tester.pumpAndSettle();

    expect(find.text('פריט'), findsOneWidget);
    await tester.tap(find.text('פריט'));
    await tester.pumpAndSettle();
    await menuFuture;
  });

  testWidgets('Disabled app menu entries use muted foreground color', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: AppPopupMenuButton<String>(
                entries: const [
                  AppMenuEntry<String>(
                    value: 'copy',
                    label: 'העתק',
                    icon: FluentIcons.copy_24_regular,
                    enabled: false,
                  ),
                ],
                child: const Text(
                  'פתח',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(FluentIcons.copy_24_regular));
    expect(
      icon.color,
      theme.colorScheme.onSurface.withValues(alpha: 0.38),
    );
  });

  // שורת תפריט רחבה מהתפריט (חלון צר, הגדלת טקסט): התווית מתקצרת ב־"…",
  // בלי גלישת RenderFlex, וה־trailing נשאר בסוף השורה.
  group('שורת תפריט צרה מהתווית', () {
    const long = 'העתק קישור ישיר לעמוד זה בספר הפתוח, עם כל הפרטים';
    final metrics = AppMenuMetrics.create(compactMenus: false);

    Future<void> pumpRow(WidgetTester tester, {Widget? trailing}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: 200,
                  child: Builder(
                    builder: (context) => buildAppMenuRowContent(
                      context,
                      metrics,
                      label: long,
                      icon: FluentIcons.link_24_regular,
                      trailing: trailing,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('בלי trailing', (tester) async {
      await pumpRow(tester);
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text(long));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.getSize(find.text(long)).width, lessThan(200));
    });

    testWidgets('עם trailing: הוא בסוף השורה', (tester) async {
      const trailingKey = Key('trailing');
      await pumpRow(
        tester,
        trailing: const SizedBox(key: trailingKey, width: 16, height: 16),
      );
      expect(tester.takeException(), isNull);
      final row = tester.getRect(find.byType(SizedBox).first);
      final label = tester.getRect(find.text(long));
      final trailing = tester.getRect(find.byKey(trailingKey));
      // RTL: הסוף בשמאל.
      expect(trailing.right, lessThanOrEqualTo(label.left));
      expect(trailing.left, greaterThanOrEqualTo(row.left));
    });
  });
}
