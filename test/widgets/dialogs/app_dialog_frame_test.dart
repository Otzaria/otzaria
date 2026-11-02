import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/widgets_exports.dart' show ActionButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialog(
    WidgetTester tester, {
    String title = 'כותרת',
    bool scrollable = true,
    bool fitTitle = true,
    Size size = const Size(800, 600),
    Widget child = const SizedBox.shrink(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: AppDialogFrame(
            title: title,
            icon: FluentIcons.list_24_regular,
            size: AppDialogSize.large,
            fitTitle: fitTitle,
            scrollable: scrollable,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('חסימת סגירה משאירה Tab, Enter ו-Space לביטול פעולה', (
    tester,
  ) async {
    var cancelled = 0;
    final dismissible = ValueNotifier(false);
    addTearDown(dismissible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ValueListenableBuilder<bool>(
                valueListenable: dismissible,
                builder: (_, canDismiss, _) => AppDialogFrame(
                  title: 'התקנה',
                  icon: FluentIcons.puzzle_piece_24_regular,
                  closeEnabled: canDismiss,
                  actions: [
                    ActionButton.ghost(
                      text: 'ביטול פריסה',
                      onPressed: () => cancelled++,
                    ),
                  ],
                  child: const Text('תוכן'),
                ),
              ),
            ),
            child: const Text('פתח'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('התקנה'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(cancelled, 2);
    expect(find.text('התקנה'), findsOneWidget);

    dismissible.value = true;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('התקנה'), findsNothing);
  });

  group('AppDialogFrame — fitTitle', () {
    testWidgets('הכותרת בשורה אחת ב-FittedBox עם BoxFit.scaleDown', (
      tester,
    ) async {
      const longTitle = 'כותרת ארוכה מאוד שעשויה לגלוש בתצוגה רגילה';
      await pumpDialog(tester, size: const Size(350, 700), title: longTitle);

      expect(tester.widget<Text>(find.text(longTitle)).maxLines, 1);
      expect(
        tester
            .widgetList<FittedBox>(find.byType(FittedBox))
            .where((fb) => fb.fit == BoxFit.scaleDown),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppDialogFrame — גלילה', () {
    testWidgets(
      'scrollable: פס גלילה גלוי, והריפוד dialogPadding בתוך הגלילה',
      (
        tester,
      ) async {
        const childKey = Key('dialog-content');
        await pumpDialog(
          tester,
          child: const SizedBox(key: childKey, height: 10),
        );

        expect(find.byType(Scrollbar), findsOneWidget);
        final scrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        expect(scrollView.padding, AppTokens.dialogPadding);
        final scrollbarRect = tester.getRect(find.byType(Scrollbar));
        final contentRect = tester.getRect(find.byKey(childKey));
        expect(
          scrollbarRect.right - contentRect.right,
          closeTo(AppTokens.spaceLG, 0.5),
        );
      },
    );

    testWidgets('בלי scrollable — אין Scrollbar ואין SingleChildScrollView', (
      tester,
    ) async {
      await pumpDialog(tester, scrollable: false);

      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });
}
