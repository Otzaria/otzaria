import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import 'contract_harness.dart';

void main() {
  group('DialogKeyboardNavigator', () {
    late int confirms;
    late int presses;
    late FocusNode inner;
    late FocusNode singleLine;
    late FocusNode multiLine;
    late FocusNode button;
    late TextEditingController ltrText;

    setUp(() {
      confirms = 0;
      presses = 0;
      inner = FocusNode();
      singleLine = FocusNode();
      multiLine = FocusNode();
      button = FocusNode();
      ltrText = TextEditingController(text: 'abc');
    });

    tearDown(() {
      inner.dispose();
      singleLine.dispose();
      multiLine.dispose();
      button.dispose();
      ltrText.dispose();
    });

    /// פותח דיאלוג עם הנווט, שדה חד־שורתי, שדה רב־שורתי, כפתור ורכיב שאינו
    /// מגיב ל-Enter, וממקד את [focus].
    Future<DialogOutcome<Object>> open(
      WidgetTester tester, {
      required FocusNode Function() focus,
      bool handleEnterKey = true,
      bool barrierDismissible = true,
    }) async {
      final outcome = await openDialog<Object>(
        tester,
        (context) => showDialog<Object>(
          context: context,
          barrierDismissible: barrierDismissible,
          builder: (_) => DialogKeyboardNavigator(
            onConfirm: () => confirms++,
            handleEnterKey: handleEnterKey,
            dismissResult: 'נסגר',
            child: Material(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Focus(focusNode: inner, child: const Text('פנימי')),
                  TextField(focusNode: singleLine),
                  TextField(focusNode: multiLine, maxLines: 3),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(controller: ltrText),
                  ),
                  TextButton(
                    focusNode: button,
                    onPressed: () => presses++,
                    child: const Text('כפתור'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      focus().requestFocus();
      await tester.pump();
      return outcome;
    }

    testWidgets('Enter בשדה חד־שורתי מפעיל את onConfirm', (tester) async {
      await open(tester, focus: () => singleLine);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(confirms, 1);
    });

    testWidgets('handleEnterKey=false: Enter בשדה חד־שורתי עובר לשדה', (
      tester,
    ) async {
      await open(tester, focus: () => singleLine, handleEnterKey: false);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(handled, isFalse);
      expect(confirms, 0);
    });

    testWidgets('Enter בשדה רב־שורתי לא נבלע (מוסיף שורה)', (tester) async {
      final outcome = await open(tester, focus: () => multiLine);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(handled, isFalse, reason: 'המקש ממשיך לשדה ומוסיף שורה');
      expect(confirms, 0);
      expect(outcome.closed, isFalse);
    });

    testWidgets('Enter על כפתור ממוקד מפעיל את הכפתור ולא את onConfirm', (
      tester,
    ) async {
      await open(tester, focus: () => button);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect((presses, confirms), (1, 0));
    });

    testWidgets('Enter על רכיב שאינו מגיב ל-Enter מפעיל את onConfirm', (
      tester,
    ) async {
      await open(tester, focus: () => inner);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      expect(confirms, 1);
    });

    testWidgets('חיצים מגיעים לשדה הטקסט', (tester) async {
      await open(tester, focus: () => singleLine);
      await tester.tap(find.byType(TextField).at(2));
      await tester.pump();
      ltrText.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(ltrText.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('Escape סוגר עם dismissResult גם כשהרקע לא סוגר', (
      tester,
    ) async {
      final outcome = await open(
        tester,
        focus: () => singleLine,
        barrierDismissible: false,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, 'נסגר');
    });
  });

  group('AppDialog — מקלדת', () {
    testWidgets('twoActions: Enter מחזיר true', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isTrue);
    });

    testWidgets('twoActions: Escape מחזיר false', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isFalse);
    });

    testWidgets('warning: Enter מחזיר false (הביטול ממוקד)', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.warning(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.value, isFalse);
    });

    testWidgets('warning: חץ ואז Enter מחזיר true', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.warning(title: 'כותרת', content: 'תוכן'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.value, isTrue);
    });

    testWidgets('twoActions עם handleEnterKey=false: Enter לא סוגר', (
      tester,
    ) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: 'תוכן',
          handleEnterKey: false,
        ),
      );
      // הפוקוס על כפתור האישור; Enter עובר ל-Shortcuts של האפליקציה ומפעיל אותו.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.value, isTrue);
    });
  });

  group('AppDialog — Enter לפי הפוקוס', () {
    testWidgets('twoActions: Enter על "ביטול" מחזיר false', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      Focus.of(tester.element(find.text('ביטול'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isFalse);
    });

    testWidgets('customContent: Enter על תיבת סימון מסמן ולא סוגר', (
      tester,
    ) async {
      var checked = false;
      final checkboxFocus = FocusNode();
      addTearDown(checkboxFocus.dispose);
      final outcome = await showInApp<bool>(
        tester,
        StatefulBuilder(
          builder: (context, setState) => AppDialog.twoActions(
            title: 'כותרת',
            content: '',
            customContent: Checkbox(
              focusNode: checkboxFocus,
              value: checked,
              onChanged: (v) => setState(() => checked = v!),
            ),
          ),
        ),
      );
      checkboxFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(checked, isTrue);
      expect(outcome.closed, isFalse);
    });

    testWidgets('customContent: Enter בשדה רב־שורתי לא סוגר', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: '',
          customContent: TextField(maxLines: 4),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(handled, isFalse);
      expect(outcome.closed, isFalse);
    });

    testWidgets('customContent: Enter בשדה חד־שורתי מאשר', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: '',
          customContent: TextField(),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.value, isTrue);
    });
  });

  group('שינויים שלא נשמרו (isDirty)', () {
    late ValueNotifier<bool> dirty;

    setUp(() => dirty = ValueNotifier(true));
    tearDown(() => dirty.dispose());

    // ל-X צריך medium: ב-small אין X (DD-07).
    Future<DialogOutcome<bool>> open(
      WidgetTester tester, {
      AppDialogSize size = AppDialogSize.small,
    }) => openDialog<bool>(
      tester,
      (context) => showTwoActionsDialog(
        context: context,
        title: 'עריכה',
        content: 'תוכן',
        isDirty: dirty,
        size: size,
      ),
    );

    Future<void> answer(WidgetTester tester, String button) async {
      expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }

    final exits = <String, Future<void> Function(WidgetTester)>{
      'Escape': (t) => t.sendKeyEvent(LogicalKeyboardKey.escape),
      'ביטול': (t) => t.tap(find.text('ביטול')),
      'X': (t) => t.tap(find.byTooltip('סגור')),
      'לחיצה בחוץ': (t) => t.tapAt(const Offset(5, 5)),
      'חזרה': (t) => t.binding.handlePopRoute(),
    };

    for (final MapEntry(key: name, value: exit) in exits.entries) {
      testWidgets('$name שואל, "המשך לערוך" משאיר פתוח', (tester) async {
        final outcome = await open(
          tester,
          size: name == 'X' ? AppDialogSize.medium : AppDialogSize.small,
        );
        await exit(tester);
        await tester.pumpAndSettle();
        await answer(tester, 'המשך לערוך');
        expect(outcome.closed, isFalse);
        expect(find.text('עריכה'), findsOneWidget);
      });

      testWidgets('$name שואל, "סגור בלי לשמור" סוגר', (tester) async {
        final outcome = await open(
          tester,
          size: name == 'X' ? AppDialogSize.medium : AppDialogSize.small,
        );
        await exit(tester);
        await tester.pumpAndSettle();
        await answer(tester, 'סגור בלי לשמור');
        expect(outcome.closed, isTrue);
        expect(outcome.value, isNot(isTrue));
      });
    }

    testWidgets('בלי שינויים Escape סוגר בלי לשאול', (tester) async {
      dirty.value = false;
      final outcome = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('לסגור בלי לשמור?'), findsNothing);
      expect(outcome.closed, isTrue);
      expect(outcome.value, isFalse);
    });

    testWidgets('אישור סוגר בלי לשאול', (tester) async {
      final outcome = await open(tester);
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();
      expect(find.text('לסגור בלי לשמור?'), findsNothing);
      expect(outcome.value, isTrue);
    });

    testWidgets('AppDialogFrame: Escape שואל', (tester) async {
      final outcome = await showInApp<void>(
        tester,
        AppDialogFrame(
          title: 'טופס',
          icon: Icons.edit,
          isDirty: dirty,
          child: const Focus(autofocus: true, child: Text('גוף')),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await answer(tester, 'סגור בלי לשמור');
      expect(outcome.closed, isTrue);
    });

    testWidgets('AppDialogFrame: X שואל', (tester) async {
      final outcome = await showInApp<void>(
        tester,
        AppDialogFrame(
          title: 'טופס',
          icon: Icons.edit,
          isDirty: dirty,
          child: const Text('גוף'),
        ),
      );
      await tester.tap(find.byTooltip('סגור'));
      await tester.pumpAndSettle();
      await answer(tester, 'המשך לערוך');
      expect(outcome.closed, isFalse);
    });
  });

  group('onDismissRequest: שאלת סגירה של הטופס עצמו', () {
    final exits = <String, Future<void> Function(WidgetTester)>{
      'Escape': (t) => t.sendKeyEvent(LogicalKeyboardKey.escape),
      'X': (t) => t.tap(find.byTooltip('סגור')),
      'לחיצה בחוץ': (t) => t.tapAt(const Offset(5, 5)),
      'חזרה': (t) => t.binding.handlePopRoute(),
    };

    for (final MapEntry(key: name, value: exit) in exits.entries) {
      testWidgets('$name קורא לו ולא סוגר', (tester) async {
        var requests = 0;
        final outcome = await showInApp<void>(
          tester,
          AppDialogFrame(
            title: 'עורך',
            icon: Icons.edit,
            onDismissRequest: () => requests++,
            child: const Focus(autofocus: true, child: Text('גוף')),
          ),
        );
        await exit(tester);
        await tester.pumpAndSettle();
        expect(requests, 1);
        expect(outcome.closed, isFalse);
        expect(find.text('לסגור בלי לשמור?'), findsNothing);
      });
    }

    testWidgets('הקורא סוגר ב-Navigator.pop', (tester) async {
      final outcome = await openDialog<void>(
        tester,
        (context) => showDialog<void>(
          context: context,
          builder: (dialogContext) => AppDialogFrame(
            title: 'עורך',
            icon: Icons.edit,
            onDismissRequest: () => Navigator.of(dialogContext).pop(),
            child: const Focus(autofocus: true, child: Text('גוף')),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
    });
  });

  group('סגירת החלון: confirmWindowClose (q11 Q3)', () {
    late ValueNotifier<bool> dirty;

    setUp(() => dirty = ValueNotifier(true));
    tearDown(() => dirty.dispose());

    Future<DialogOutcome<bool>> open(WidgetTester tester) => openDialog<bool>(
      tester,
      (context) => showTwoActionsDialog(
        context: context,
        title: 'עריכה',
        content: 'תוכן',
        isDirty: dirty,
      ),
    );

    /// מבקש סגירת חלון ומחזיר את התשובה, אחרי שהשאלה (אם יש) נענתה.
    Future<bool?> closeWindow(
      WidgetTester tester, {
      String? answer,
      AppWindowKeys? window,
    }) async {
      bool? allowed;
      unawaited(
        DialogDismissGuard.confirmWindowClose(
          window: window,
        ).then((value) => allowed = value),
      );
      await tester.pumpAndSettle();
      if (answer != null) {
        expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
        await tester.tap(find.text(answer));
        await tester.pumpAndSettle();
      } else {
        expect(find.text('לסגור בלי לשמור?'), findsNothing);
      }
      return allowed;
    }

    testWidgets('שינויים: "המשך לערוך" עוצר את הסגירה ומשאיר את הדיאלוג', (
      tester,
    ) async {
      final outcome = await open(tester);
      expect(await closeWindow(tester, answer: 'המשך לערוך'), isFalse);
      expect(outcome.closed, isFalse);
      expect(find.text('עריכה'), findsOneWidget);
    });

    testWidgets('שינויים: "סגור בלי לשמור" סוגר את הדיאלוג ומתיר', (
      tester,
    ) async {
      final outcome = await open(tester);
      expect(await closeWindow(tester, answer: 'סגור בלי לשמור'), isTrue);
      expect(outcome.closed, isTrue);
      expect(outcome.value, isNot(isTrue));
    });

    testWidgets('בלי שינויים: מתיר בלי לשאול, והדיאלוג לא נוגע', (
      tester,
    ) async {
      dirty.value = false;
      final outcome = await open(tester);
      expect(await closeWindow(tester), isTrue);
      expect(outcome.closed, isFalse);
    });

    testWidgets('דיאלוג בחלון אחר אינו נשאל בסגירת החלון הזה', (tester) async {
      await open(tester);
      final other = AppWindowKeys(id: const AppWindowId('window-view-9'));
      expect(await closeWindow(tester, window: other), isTrue);
      expect(find.text('עריכה'), findsOneWidget);
    });

    testWidgets('תפריט מעל הדיאלוג נסגר, והשאלה נפתחת מעל הדיאלוג', (
      tester,
    ) async {
      final outcome = await open(tester);
      final context = tester.element(find.text('תוכן'));
      unawaited(
        showMenu<void>(
          context: context,
          position: const RelativeRect.fromLTRB(10, 10, 10, 10),
          items: const [PopupMenuItem(child: Text('פריט'))],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('פריט'), findsOneWidget);
      expect(await closeWindow(tester, answer: 'סגור בלי לשמור'), isTrue);
      expect(find.text('פריט'), findsNothing);
      expect(outcome.closed, isTrue);
    });

    testWidgets('Escape שכבר שואל: סגירת החלון מחכה לאותה שאלה', (
      tester,
    ) async {
      final outcome = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await closeWindow(tester, answer: 'סגור בלי לשמור'), isTrue);
      expect(outcome.closed, isTrue);
    });

    for (final closes in [true, false]) {
      testWidgets(
        'onDismissRequest: סגירת החלון ממתינה לשאלת הטופס '
        '(${closes ? 'נסגר' : 'נשאר'})',
        (tester) async {
          var requests = 0;
          late BuildContext dialogContext;
          final outcome = await openDialog<void>(
            tester,
            (context) => showDialog<void>(
              context: context,
              builder: (context) {
                dialogContext = context;
                return AppDialogFrame(
                  title: 'עורך',
                  icon: Icons.edit,
                  onDismissRequest: () async {
                    requests++;
                    await Future<void>.delayed(Duration.zero);
                    if (closes && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('גוף'),
                );
              },
            ),
          );
          expect(await closeWindow(tester), closes);
          expect(requests, 1);
          expect(outcome.closed, closes);
        },
      );
    }
  });

  group('AppDialogFrame — מקלדת', () {
    const focusedBody = Focus(autofocus: true, child: Text('גוף'));

    testWidgets('בלי onConfirm Enter לא סוגר ו-Escape סוגר', (tester) async {
      final outcome = await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'רשימה',
          icon: Icons.list,
          child: focusedBody,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
    });

    for (final handleEnterKey in [false, true]) {
      testWidgets('onConfirm עם handleEnterKey=$handleEnterKey', (
        tester,
      ) async {
        var confirms = 0;
        await showInApp<void>(
          tester,
          AppDialogFrame(
            title: 'רשימה',
            icon: Icons.list,
            onConfirm: () => confirms++,
            handleEnterKey: handleEnterKey,
            child: focusedBody,
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(confirms, handleEnterKey ? 1 : 0);
      });
    }

    testWidgets('בלי רכיב ממוקד בתוכן Enter לא מגיע ל-onConfirm', (
      tester,
    ) async {
      var confirms = 0;
      await showInApp<void>(
        tester,
        AppDialogFrame(
          title: 'רשימה',
          icon: Icons.list,
          onConfirm: () => confirms++,
          handleEnterKey: true,
          child: const Text('גוף'),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(confirms, 0);
    });

    testWidgets('closeEnabled=false: Escape לא סוגר', (tester) async {
      final outcome = await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'רשימה',
          icon: Icons.list,
          closeEnabled: false,
          child: focusedBody,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isFalse);
    });
  });

  group('SelectionDialog — מקלדת', () {
    const items = [
      SelectionItem(label: 'אלף', value: 1),
      SelectionItem(label: 'בית', value: 2),
    ];

    testWidgets('לחיצה על פריט מחזירה את ערכו', (tester) async {
      final outcome = await showInApp<int>(
        tester,
        const SelectionDialog<int>(title: 'בחירה', items: items),
      );
      await tester.tap(find.text('בית'));
      await tester.pumpAndSettle();
      expect(outcome.value, 2);
    });

    testWidgets('Enter בשדה החיפוש לא סוגר', (tester) async {
      final outcome = await showInApp<int>(
        tester,
        const SelectionDialog<int>(title: 'בחירה', items: items),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isFalse);
    });

    testWidgets('Enter על פריט ממוקד בוחר אותו', (tester) async {
      final outcome = await showInApp<int>(
        tester,
        const SelectionDialog<int>(title: 'בחירה', items: items),
      );
      Focus.of(tester.element(find.text('בית'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, 2);
    });

    testWidgets('Escape סוגר גם כשהרקע לא סוגר', (tester) async {
      final outcome = await openDialog<int>(
        tester,
        (context) => showSelectionDialog<int>(
          context: context,
          title: 'בחירה',
          items: items,
          barrierDismissible: false,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isNull);
    });
  });
}
