import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_tokens.dart';
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

  testWidgets(
    'הדגשת הריחוף של החצאים נחתכת לצורתם, ברדיוס התוכנה בצד החיצוני',
    (
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
      // רדיוס התוכנה (8) ולא חצי עיגול, ורק בצד החיצוני של כל חצי.
      const radius = Radius.circular(AppTokens.radius);
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
    },
  );

  testWidgets('הריחוף והלחיצה בשקיפויות של IconButton', (tester) async {
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

    final inkWells = tester.widgetList<InkWell>(
      find.descendant(
        of: find.byType(BarSplitButton<String>),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWells, hasLength(2));
    for (final inkWell in inkWells) {
      final overlay = inkWell.overlayColor!;
      expect(overlay.resolve({WidgetState.hovered})!.a, closeTo(0.08, 0.005));
      expect(overlay.resolve({WidgetState.pressed})!.a, closeTo(0.10, 0.005));
      expect(overlay.resolve({WidgetState.focused})!.a, closeTo(0.10, 0.005));
      expect(overlay.resolve(<WidgetState>{}), isNull);
      expect(inkWell.splashColor!.a, closeTo(0.10, 0.005));
      // ההדגשה בלחיצה באה מ-overlayColor (pressed), בלי highlightColor נפרד.
      expect(inkWell.highlightColor, isNull);
    }
  });

  testWidgets('החץ מתהפך כל עוד ה-Future של onArrowPressed לא הסתיים', (
    tester,
  ) async {
    var calls = 0;
    Completer<void>? closed;
    await tester.pumpWidget(
      host(
        BarSplitButton<String>(
          icon: FluentIcons.bookmark_24_regular,
          tooltip: 'פעולה',
          onPressed: () {},
          entries: const [],
          onSelected: (_) {},
          onArrowPressed: (_) {
            calls++;
            final completer = closed = Completer<void>();
            return completer.future;
          },
        ),
      ),
    );

    double turns() => tester
        .widget<AnimatedRotation>(
          find.ancestor(
            of: find.byIcon(FluentIcons.chevron_down_16_regular),
            matching: find.byType(AnimatedRotation),
          ),
        )
        .turns;

    expect(turns(), 0);

    await tester.tap(find.byIcon(FluentIcons.chevron_down_16_regular));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(turns(), 0.5);

    // לחיצה נוספת בזמן שהחלון פתוח אינה פותחת אותו שוב.
    await tester.tap(find.byIcon(FluentIcons.chevron_down_16_regular));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(turns(), 0.5);

    closed!.complete();
    await tester.pumpAndSettle();
    expect(turns(), 0);

    // אחרי הסגירה החץ פותח שוב.
    await tester.tap(find.byIcon(FluentIcons.chevron_down_16_regular));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(turns(), 0.5);
    closed!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('החץ מתהפך בזמן שתפריט הפריטים פתוח, וחוזר כשהוא נסגר', (
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
    double turns() => tester
        .widget<AnimatedRotation>(
          find.ancestor(
            of: find.byIcon(FluentIcons.chevron_down_16_regular),
            matching: find.byType(AnimatedRotation),
          ),
        )
        .turns;

    await tester.tap(find.byIcon(FluentIcons.chevron_down_16_regular));
    await tester.pumpAndSettle();
    expect(find.text('פריט'), findsOneWidget);
    expect(turns(), 0.5);

    await tester.tap(find.text('פריט'));
    await tester.pumpAndSettle();
    expect(turns(), 0);
  });
}
