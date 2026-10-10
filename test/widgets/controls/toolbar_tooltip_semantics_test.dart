// כפתורי הסרגל המשותפים יושבים לעיתים בתוך עוגן overlay אחר (OverlayPortal,
// MenuAnchor). ה-tooltip שלהם חייב צומת סמנטיקה משלו, אחרת עוגן הבלון מתמזג
// לצומת של העוגן החיצוני ונשמט, והבלון נשלח למערכת ההפעלה בלי אב.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/controls/bar_split_button.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../../helpers/semantics_update_recorder.dart';

void main() {
  SemanticsRecordingBinding.ensure();
  final recorder = SemanticsRecordingBinding.recorder;

  final splitButton = BarSplitButton<int>(
    icon: FluentIcons.save_24_regular,
    tooltip: 'שמור',
    menuTooltip: 'אפשרויות',
    onPressed: () {},
    entries: const [AppMenuEntry(value: 1, label: 'פריט')],
    onSelected: (_) {},
  );

  final cases = <String, (Widget, List<String>)>{
    'BarButton.icon': (
      BarButton.icon(
        tooltip: 'קודם',
        icon: FluentIcons.chevron_left_24_regular,
        onPressed: () {},
      ),
      ['קודם'],
    ),
    'BarButton.icon עם תווית': (
      BarButton.icon(
        tooltip: 'הסבר',
        label: 'תצוגה',
        icon: FluentIcons.eye_24_regular,
        onPressed: () {},
      ),
      ['הסבר'],
    ),
    'SecondaryIconButton': (
      SecondaryIconButton(
        tooltip: 'משני',
        icon: FluentIcons.copy_24_regular,
        onPressed: () {},
      ),
      ['משני'],
    ),
    'PrimaryIconButton': (PrimaryIconButton(onPressed: () {}), ['פתח מקור']),
    'BarSplitButton': (splitButton, ['שמור', 'אפשרויות']),
  };

  for (final MapEntry(key: name, value: (button, tooltips)) in cases.entries) {
    for (final tooltip in tooltips) {
      testWidgets(
        '$name בתוך OverlayPortal: הבלון "$tooltip" נשלח עם אב (issue #1915)',
        (tester) async {
          recorder.reset();
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: OverlayPortal(
                    controller: OverlayPortalController(),
                    overlayChildBuilder: (_) => const SizedBox.shrink(),
                    child: button,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(find.byTooltip(tooltip)));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text(tooltip), findsOneWidget, reason: 'הבלון נפתח');

          expect(recorder.violations, isEmpty);
          // ההודעה מוכרזת פעם אחת, בצומת של הכפתור ולא בצומת העוגן החיצוני.
          final node = tester.getSemantics(find.byTooltip(tooltip));
          expect(node, isSemantics(tooltip: tooltip));
          expect(
            node.traversalParentIdentifier,
            isNotNull,
            reason: 'עוגן הבלון שמור על הצומת של ה-tooltip',
          );
          expect(
            find.semantics.byPredicate((n) => n.tooltip == tooltip),
            findsOne,
            reason: 'ההודעה אינה מוכפלת',
          );
          handle.dispose();
        },
      );
    }
  }
}
