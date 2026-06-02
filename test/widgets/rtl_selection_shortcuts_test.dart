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

    testWidgets('גם בכיווניות LTR מוסיף Shortcuts לסינון לפי יעד הפוקוס',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RtlSelectionShortcuts(child: SizedBox()),
        ),
      );

      expect(find.byType(Shortcuts), findsOneWidget);
    });

    testWidgets('ממפה את קיצורי Shift+חץ הנתמכים', (tester) async {
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
      expect(
        shortcuts.containsKey(
          const SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            shift: true,
            alt: true,
          ),
        ),
        isTrue,
      );
      expect(
        shortcuts.containsKey(
          const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            shift: true,
            alt: true,
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
    Future<TextEditingController> pumpTextField(
      WidgetTester tester, {
      required TextDirection appDirection,
      required TextDirection fieldDirection,
      required String text,
    }) async {
      final controller = TextEditingController(text: text);
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
            textDirection: appDirection,
            child: RtlSelectionShortcuts(
              child: Directionality(
                textDirection: fieldDirection,
                child: Scaffold(
                  body: TextField(
                    controller: controller,
                    focusNode: focusNode,
                  ),
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
        final controller = await pumpTextField(
          tester,
          appDirection: TextDirection.rtl,
          fieldDirection: TextDirection.rtl,
          text: 'שלום עולם ועד',
        );
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
        final controller = await pumpTextField(
          tester,
          appDirection: TextDirection.rtl,
          fieldDirection: TextDirection.rtl,
          text: 'שלום עולם ועד',
        );
        // הסמן בסוף המחרוזת (הקצה השמאלי ויזואלית ב-RTL).
        final end = controller.text.length;
        controller.selection = TextSelection.collapsed(offset: end);
        await tester.pump();

        await sendCtrlShift(tester, LogicalKeyboardKey.arrowRight);

        // חץ ימין = מעלה הזרם → ה-extent חייב לקטון, ולא להישאר בסוף.
        expect(controller.selection.extentOffset, lessThan(end));
      },
    );

    testWidgets(
      'שדה LTR בתוך אפליקציה RTL נשאר עם כיוון ברירת המחדל',
      (tester) async {
        final controller = await pumpTextField(
          tester,
          appDirection: TextDirection.rtl,
          fieldDirection: TextDirection.ltr,
          text: 'one two three',
        );
        final end = controller.text.length;
        controller.selection = TextSelection.collapsed(offset: end);
        await tester.pump();

        await sendCtrlShift(tester, LogicalKeyboardKey.arrowLeft);

        expect(controller.selection.extentOffset, lessThan(end));
      },
    );
  });

  group('RtlSelectionShortcuts — התנהגות באזור בחירה RTL', () {
    Future<Intent?> invokeShortcutOnSelectionTarget(
      WidgetTester tester,
      LogicalKeyboardKey arrow,
    ) async {
      final focusNode = FocusNode();
      Intent? invokedIntent;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: RtlSelectionShortcuts(
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ExtendSelectionByCharacterIntent:
                      CallbackAction<ExtendSelectionByCharacterIntent>(
                    onInvoke: (intent) {
                      invokedIntent = intent;
                      return true;
                    },
                  ),
                },
                child: Focus(
                  focusNode: focusNode,
                  child: const Text(
                    'טקסט לבחירה',
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(arrow);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      addTearDown(focusNode.dispose);
      return invokedIntent;
    }

    testWidgets('Shift+חץ-שמאל מומר ל-forward באזור בחירה RTL', (tester) async {
      final intent = await invokeShortcutOnSelectionTarget(
        tester,
        LogicalKeyboardKey.arrowLeft,
      );

      expect(intent, isA<ExtendSelectionByCharacterIntent>());
      expect((intent as ExtendSelectionByCharacterIntent).forward, isTrue);
      expect(intent.collapseSelection, isFalse);
    });

    testWidgets('Shift+חץ-ימין מומר ל-backward באזור בחירה RTL',
        (tester) async {
      final intent = await invokeShortcutOnSelectionTarget(
        tester,
        LogicalKeyboardKey.arrowRight,
      );

      expect(intent, isA<ExtendSelectionByCharacterIntent>());
      expect((intent as ExtendSelectionByCharacterIntent).forward, isFalse);
      expect(intent.collapseSelection, isFalse);
    });
  });
}
