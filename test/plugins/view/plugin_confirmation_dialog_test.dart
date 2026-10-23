import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_confirmation_dialog.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

void main() {
  Future<BuildContext> host(
    WidgetTester tester, {
    ThemeData? theme,
    DialogThemeData? localDialogTheme,
  }) async {
    const content = Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: Text('מקור')),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: localDialogTheme == null
            ? content
            : DialogTheme(data: localDialogTheme, child: content),
      ),
    );
    return tester.element(find.text('מקור'));
  }

  for (final confirmed in [true, false]) {
    testWidgets('החלטה אנושית אחרי 31 שניות נשמרת: $confirmed', (tester) async {
      final context = await host(tester);
      final dialog = PluginConfirmationDialog();
      addTearDown(dialog.dispose);
      bool? result;
      final pending = dialog
          .show(context: context, title: 'תיקון', content: 'לשלוח?')
          .then((value) => result = value);
      await tester.pumpAndSettle();
      final route =
          ModalRoute.of(tester.element(find.text('לשלוח?')))!
              as DialogRoute<bool>;
      expect(route.barrierColor, Colors.black54);
      expect(route.traversalEdgeBehavior, TraversalEdgeBehavior.closedLoop);
      await tester.pump(const Duration(seconds: 31));
      expect(result, isNull);
      expect(find.text('לשלוח?'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('לשלוח?'))),
        TextDirection.rtl,
      );
      await tester.tap(find.text(confirmed ? 'אישור' : 'ביטול'));
      await tester.pumpAndSettle();
      await pending;
      expect(result, confirmed);
    });
  }

  testWidgets(
    'צבע מחסום והקפת פוקוס נשמרים לפי ה-theme של הדיאלוגים המשותפים',
    (
      tester,
    ) async {
      const barrier = Color(0x11010203);
      final context = await host(
        tester,
        theme: ThemeData(
          dialogTheme: const DialogThemeData(barrierColor: barrier),
        ),
        localDialogTheme: const DialogThemeData(),
      );
      final dialog = PluginConfirmationDialog();
      addTearDown(dialog.dispose);
      final pending = dialog.show(
        context: context,
        title: 'תוסף',
        content: 'לשלוח?',
      );
      await tester.pumpAndSettle();
      final route =
          ModalRoute.of(tester.element(find.text('לשלוח?')))!
              as DialogRoute<bool>;
      expect(route.barrierColor, barrier);
      for (var press = 0; press < 8; press++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<AppDialog>(),
          isNotNull,
        );
      }
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await pending, isFalse);
    },
  );

  testWidgets(
    'אישור מקביל נדחה בלי לפגוע בדיאלוג הראשון ואחריו אפשר לפתוח שוב',
    (
      tester,
    ) async {
      final context = await host(tester);
      final dialog = PluginConfirmationDialog();
      addTearDown(dialog.dispose);
      final pending = dialog.show(
        context: context,
        title: 'ראשון',
        content: 'לשלוח?',
      );
      await tester.pumpAndSettle();
      await expectLater(
        dialog.show(context: context, title: 'שני', content: 'לשלוח?'),
        throwsA(
          predicate((error) => error.toString().contains('error.conflict')),
        ),
      );
      expect(find.text('ראשון'), findsOneWidget);
      expect(find.text('שני'), findsNothing);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await pending, isFalse);
      final next = dialog.show(
        context: context,
        title: 'חדש',
        content: 'לשלוח?',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();
      expect(await next, isTrue);
    },
  );

  testWidgets('סגירת חלון האישור משחררת מופע חי לאישור בחלון אחר', (
    tester,
  ) async {
    final context = await host(tester);
    final dialog = PluginConfirmationDialog();
    addTearDown(dialog.dispose);
    bool? result;
    final pending = dialog
        .show(context: context, title: 'חלון שנסגר', content: 'לשלוח?')
        .then((value) => result = value);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(await pending, isFalse);

    final nextContext = await host(tester);
    final next = dialog.show(
      context: nextContext,
      title: 'חלון אחר',
      content: 'לשלוח?',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();
    expect(await next, isTrue);
  });

  testWidgets('סגירת מופע מסיימת אישור ב-false ומשאירה דיאלוג זר פתוח', (
    tester,
  ) async {
    final context = await host(tester);
    final dialog = PluginConfirmationDialog();
    final pending = dialog.show(
      context: context,
      title: 'תוסף',
      content: 'הצעה',
    );
    await tester.pumpAndSettle();
    final unrelated = showTwoActionsDialog(
      context: context,
      title: 'אחר',
      content: 'לשמור?',
    );
    await tester.pumpAndSettle();
    dialog.dispose();
    expect(
      await dialog.show(context: context, title: 'חדש', content: ''),
      isFalse,
    );
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(find.text('אחר'), findsOneWidget);
    expect(find.text('תוסף'), findsNothing);
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(await unrelated, isFalse);
    expect(find.text('מקור'), findsOneWidget);
    dialog.dispose();
  });
}
