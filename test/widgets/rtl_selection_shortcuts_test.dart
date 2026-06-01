import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

void main() {
  group('RtlSelectionShortcuts', () {
    testWidgets('בכיווניות RTL עוטף את הילד ב-Shortcuts', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: RtlSelectionShortcuts(child: SizedBox()),
        ),
      );

      expect(find.byType(Shortcuts), findsOneWidget);
    });

    testWidgets('בכיווניות LTR שקוף — אינו מוסיף Shortcuts', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RtlSelectionShortcuts(child: SizedBox()),
        ),
      );

      expect(find.byType(Shortcuts), findsNothing);
    });

    testWidgets('ממפה את ארבעת מקשי Shift+חץ הבסיסיים', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: RtlSelectionShortcuts(child: SizedBox()),
        ),
      );

      final shortcuts =
          tester.widget<Shortcuts>(find.byType(Shortcuts)).shortcuts;

      expect(
        shortcuts.containsKey(
          const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true),
        ),
        isTrue,
      );
      expect(
        shortcuts.containsKey(
          const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
        ),
        isTrue,
      );
      expect(
        shortcuts.containsKey(
          const SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            shift: true,
            control: true,
          ),
        ),
        isTrue,
      );
      expect(
        shortcuts.containsKey(
          const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            shift: true,
            control: true,
          ),
        ),
        isTrue,
      );
    });

    testWidgets('אינו מיירט חיצים רגילים (ללא Shift)', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: RtlSelectionShortcuts(child: SizedBox()),
        ),
      );

      final shortcuts =
          tester.widget<Shortcuts>(find.byType(Shortcuts)).shortcuts;

      expect(
        shortcuts.containsKey(
          const SingleActivator(LogicalKeyboardKey.arrowLeft),
        ),
        isFalse,
      );
      expect(
        shortcuts.containsKey(
          const SingleActivator(LogicalKeyboardKey.arrowRight),
        ),
        isFalse,
      );
    });
  });
}
