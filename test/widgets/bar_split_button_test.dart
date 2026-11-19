import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/bar_split_button.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('לחיצה על החלק הראשי מפעילה את הפעולה ולא פותחת תפריט', (
    tester,
  ) async {
    var primaryTaps = 0;
    await tester.pumpWidget(
      host(
        BarSplitButton<String>(
          icon: FluentIcons.bookmark_24_regular,
          tooltip: 'שמור',
          onPressed: () => primaryTaps++,
          entries: const [AppMenuEntry(value: 'a', label: 'אפשרות א')],
          onSelected: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(FluentIcons.bookmark_24_regular));
    await tester.pumpAndSettle();

    expect(primaryTaps, 1);
    expect(find.text('אפשרות א'), findsNothing);
  });

  testWidgets('לחיצה על החץ פותחת את התפריט ובחירה מחזירה את הערך', (
    tester,
  ) async {
    var primaryTaps = 0;
    String? selected;
    await tester.pumpWidget(
      host(
        BarSplitButton<String>(
          icon: FluentIcons.bookmark_24_regular,
          tooltip: 'שמור',
          onPressed: () => primaryTaps++,
          entries: const [
            AppMenuEntry(value: 'a', label: 'אפשרות א'),
            AppMenuEntry(value: 'b', label: 'אפשרות ב'),
          ],
          onSelected: (value) => selected = value,
        ),
      ),
    );

    await tester.tap(find.byIcon(FluentIcons.chevron_down_16_regular));
    await tester.pumpAndSettle();
    expect(find.text('אפשרות א'), findsOneWidget);

    await tester.tap(find.text('אפשרות ב'));
    await tester.pumpAndSettle();

    expect(selected, 'b');
    expect(primaryTaps, 0);
  });

  testWidgets('בלי פריטי תפריט החץ מושבת ואינו פותח דבר', (tester) async {
    await tester.pumpWidget(
      host(
        BarSplitButton<String>(
          icon: FluentIcons.bookmark_24_regular,
          tooltip: 'שמור',
          onPressed: () {},
          entries: const [],
          onSelected: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(FluentIcons.chevron_down_16_regular));
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<String>), findsNothing);
  });

  testWidgets(
    'הסרגל החליף את הלחצן המפוצל בזמן שהתפריט פתוח — מופעל הפריט שנבחר',
    (tester) async {
      final opened = <String>[];
      Widget bar(ToolbarActionId id, List<String> items) => host(
        ResponsiveActionBar(
          alwaysInMenu: const [],
          actions: [
            ActionButtonData.split(
              icon: FluentIcons.bookmark_24_regular,
              tooltip: id.name,
              onPressed: () {},
              compact: false,
              actionId: id,
              menuItems: [
                for (final item in items)
                  ActionButtonData(
                    widget: const SizedBox.shrink(),
                    tooltip: item,
                    onPressed: () => opened.add(item),
                  ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        bar(ToolbarActionId.parallelEdition, ['א', 'ב', 'ג', 'ד']),
      );
      await tester.tap(find.byIcon(FluentIcons.chevron_down_16_regular));
      await tester.pumpAndSettle();
      // באותו מקום בסרגל נבנה לחצן מפוצל אחר (של תוסף) עם פריט אחד.
      await tester.pumpWidget(bar(ToolbarActionId.plugin, ['פריט תוסף']));

      await tester.tap(find.text('ד'));
      await tester.pumpAndSettle();

      expect(opened, ['ד']);
    },
  );

  testWidgets('הדגשת הריחוף של החצאים נחתכת לצורתם ואינה מצוירת כמלבן מעוגל', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        BarSplitButton<String>(
          icon: FluentIcons.bookmark_24_regular,
          tooltip: 'פעולה',
          onPressed: () {},
          entries: const [AppMenuEntry(value: 'a', label: 'פריט')],
          onSelected: (_) {},
        ),
      ),
    );

    final inkWells = tester
        .widgetList<InkWell>(
          find.descendant(
            of: find.byType(BarSplitButton<String>),
            matching: find.byType(InkWell),
          ),
        )
        .toList();
    const radius = Radius.circular(BarSplitButton.regularHeight / 2);
    final expectedRadii = [
      const BorderRadius.horizontal(right: radius),
      const BorderRadius.horizontal(left: radius),
    ];

    expect(inkWells, hasLength(2));
    for (var i = 0; i < inkWells.length; i++) {
      expect(inkWells[i].borderRadius, isNull);
      final border = inkWells[i].customBorder;
      expect(border, isA<RoundedRectangleBorder>());
      expect(
        (border! as RoundedRectangleBorder).borderRadius,
        expectedRadii[i],
      );
    }
  });
}
