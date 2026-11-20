// סעיף 17 (סבב ג'): בסרגל צר פריטי ההתחלה שקופלו עוברים לתפריט "עוד ⋮" של
// פעולות הסרגל, ולא לכפתור ⋮ שני לידו.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

const _moreTooltip = 'עוד פעולות';

AppTopBarItem _item(
  String name,
  List<String> log, {
  AppTopBarPriority priority = AppTopBarPriority.critical,
  bool enabled = true,
}) {
  return AppTopBarItem(
    priority: priority,
    menuAction: priority == AppTopBarPriority.critical
        ? null
        : AppTopBarMenuAction(
            label: 'פעולה $name',
            icon: Icons.add,
            onPressed: enabled ? () => log.add(name) : null,
          ),
    // Listener אטום: SizedBox לבד לא עובר hitTestable.
    widget: Listener(
      key: Key(name),
      behavior: HitTestBehavior.opaque,
      child: const SizedBox(width: 48, height: 40),
    ),
  );
}

Widget _app({
  required double width,
  required List<AppTopBarItem> leading,
  required List<String> log,
}) {
  return MaterialApp(
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: AppTopBar(
            mergeFoldedIntoTrailingMenu: true,
            leadingItems: leading,
            trailingItems: [
              AppTopBarItem(
                flexible: true,
                widget: ResponsiveActionBar(
                  absorbTopBarFolds: true,
                  actions: const [],
                  alwaysInMenu: [
                    ActionButtonData(
                      widget: const SizedBox.shrink(),
                      icon: Icons.print,
                      tooltip: 'הדפסה',
                      onPressed: () => log.add('print'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_moreTooltip));
  await tester.pumpAndSettle();
}

bool _rowEnabled(WidgetTester tester, String label) {
  final item = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
  );
  return (tester.widget(item.first) as PopupMenuItem).enabled;
}

void main() {
  group('AppTopBar: תפריט "עוד ⋮" אחד', () {
    testWidgets('צר: כפתור ⋮ אחד, ובו פעולות ההתחלה ופעולות הסרגל', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(
          width: 150,
          log: log,
          leading: [
            _item('c', log),
            _item('n', log, priority: AppTopBarPriority.normal),
            _item('l', log, priority: AppTopBarPriority.low),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip(_moreTooltip), findsOneWidget);
      expect(tester.any(find.byKey(const Key('c')).hitTestable()), isTrue);
      expect(tester.any(find.byKey(const Key('n')).hitTestable()), isFalse);

      await _openMenu(tester);
      expect(find.text('פעולה n'), findsOneWidget);
      expect(find.text('פעולה l'), findsOneWidget);
      expect(find.text('הדפסה'), findsOneWidget);

      await tester.tap(find.text('פעולה l'));
      await tester.pumpAndSettle();
      expect(log, ['l']);
    });

    testWidgets('רחב: אין פעולות התחלה בתפריט, ופעולות הסרגל נשארות', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(
          width: 400,
          log: log,
          leading: [
            _item('c', log),
            _item('n', log, priority: AppTopBarPriority.normal),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.any(find.byKey(const Key('n')).hitTestable()), isTrue);
      await _openMenu(tester);
      expect(find.text('פעולה n'), findsNothing);
      expect(find.text('הדפסה'), findsOneWidget);
    });

    testWidgets(
      'פעולת התחלה בלי onPressed מוצגת מושבתת, וחוזרת לפעול כשמתעדכנת',
      (
        tester,
      ) async {
        final log = <String>[];
        List<AppTopBarItem> leading({required bool enabled}) => [
          _item('c', log),
          _item(
            'n',
            log,
            priority: AppTopBarPriority.normal,
            enabled: enabled,
          ),
        ];
        await tester.pumpWidget(
          _app(width: 110, log: log, leading: leading(enabled: false)),
        );
        await tester.pump();
        await tester.pump();
        await _openMenu(tester);
        expect(_rowEnabled(tester, 'פעולה n'), isFalse);
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          _app(width: 110, log: log, leading: leading(enabled: true)),
        );
        await tester.pump();
        await tester.pump();
        await _openMenu(tester);
        expect(_rowEnabled(tester, 'פעולה n'), isTrue);
      },
    );
  });
}
