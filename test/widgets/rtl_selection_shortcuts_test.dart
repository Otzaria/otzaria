import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

  group('RtlSelectionShortcuts — התנהגות בשדה קלט RTL', () {
    Future<TextEditingController> pumpRtlTextField(WidgetTester tester) async {
      final controller = TextEditingController(text: 'שלום עולם ועד');
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('he')],
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: RtlSelectionShortcuts(
              child: Scaffold(
                body: TextField(
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      return controller;
    }

    Future<void> sendCtrlShift(
      WidgetTester tester,
      LogicalKeyboardKey arrow,
    ) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(arrow);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets(
      'Ctrl+Shift+חץ-שמאל מרחיב מילה במורד הזרם (downstream) — לא הפוך',
      (tester) async {
        final controller = await pumpRtlTextField(tester);
        // הסמן בתחילת המחרוזת (הקצה הימני ויזואלית ב-RTL).
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();

        await sendCtrlShift(tester, LogicalKeyboardKey.arrowLeft);

        // בעברית חץ שמאל = מורד הזרם → ה-extent חייב לגדול (לבחור "שלום"),
        // ולא להישאר 0 כפי שקורה עם הכיוון ההפוך של ברירת המחדל.
        expect(controller.selection.extentOffset, greaterThan(0));
      },
    );

    testWidgets(
      'Ctrl+Shift+חץ-ימין מרחיב מילה במעלה הזרם (upstream) — לא הפוך',
      (tester) async {
        final controller = await pumpRtlTextField(tester);
        // הסמן בסוף המחרוזת (הקצה השמאלי ויזואלית ב-RTL).
        final end = controller.text.length;
        controller.selection = TextSelection.collapsed(offset: end);
        await tester.pump();

        await sendCtrlShift(tester, LogicalKeyboardKey.arrowRight);

        // חץ ימין = מעלה הזרם → ה-extent חייב לקטון, ולא להישאר בסוף.
        expect(controller.selection.extentOffset, lessThan(end));
      },
    );
  });
}
