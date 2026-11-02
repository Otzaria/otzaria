import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import 'contract_harness.dart';

Material _dialogSurface(WidgetTester tester) =>
    firstMaterialIn(tester, find.byType(Dialog));

void main() {
  group('AppCustomContentDialog', () {
    testWidgets('דסקטופ: 50% רוחב ו-80% גובה של החלון', (tester) async {
      await showInApp<void>(
        tester,
        const AppCustomContentDialog(title: 'רשימה', child: Text('גוף')),
      );
      expect(
        tester.getSize(find.byWidget(_dialogSurface(tester))),
        const Size(600, 640),
      );
    });

    testWidgets('מתחת ל-600: 95% רוחב, עד הריפוד החיצוני (16 מכל צד)', (
      tester,
    ) async {
      await showInApp<void>(
        tester,
        const AppCustomContentDialog(title: 'רשימה', child: Text('גוף')),
        size: const Size(500, 800),
      );
      expect(
        tester.getSize(find.byWidget(_dialogSurface(tester))),
        const Size(500 - 32, 640),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('רקע ב-$brightness: רקע הלוח', (tester) async {
        await showInApp<void>(
          tester,
          const AppCustomContentDialog(title: 'רשימה', child: Text('גוף')),
          brightness: brightness,
        );
        final context = tester.element(find.byType(AppCustomContentDialog));
        final surface = _dialogSurface(tester);
        expect(surface.color, AppSurfaces.panelBackground(context));
        expect(surface.shape, AppTokens.roundedShape);
        expect(surface.clipBehavior, Clip.antiAlias);
        expect(
          tester.widget<Dialog>(find.byType(Dialog)).insetPadding,
          const EdgeInsets.all(16),
        );
      });
    }

    testWidgets('כותרת: AppDialogHeader קומפקטי שמתכווץ לרוחב', (tester) async {
      await showInApp<void>(
        tester,
        const AppCustomContentDialog(
          title: 'רשימה',
          icon: FluentIcons.list_24_regular,
          child: Text('גוף'),
        ),
      );
      final header = tester.widget<AppDialogHeader>(
        find.byType(AppDialogHeader),
      );
      expect(header.compact, isTrue);
      expect(header.fitTitle, isTrue);
      expect(header.closeEnabled, isTrue);
    });

    testWidgets('שורת הפעולות בריפוד 16 בצמוד לסוף', (tester) async {
      await showInApp<void>(
        tester,
        AppCustomContentDialog(
          title: 'רשימה',
          actions: [ActionButton.recommended(text: 'שמור', onPressed: () {})],
          child: const Text('גוף'),
        ),
      );
      final surface = tester.getRect(find.byWidget(_dialogSurface(tester)));
      final save = tester.getRect(
        find.ancestor(
          of: find.text('שמור'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(save.left - surface.left, 16);
      expect(surface.bottom - save.bottom, 16);
    });
  });

  group('ListDialogFrame', () {
    Widget frame() => const ListDialogFrame(
      icon: FluentIcons.book_24_regular,
      title: 'ספרים',
      counter: '12 ספרים',
      children: [Text('שורה')],
    );

    testWidgets('דסקטופ: רוחב 720, גובה מרבי 85%', (tester) async {
      await showInApp<void>(tester, frame());
      final constraints = tester
          .widget<ConstrainedBox>(
            find
                .descendant(
                  of: find.byType(ListDialogFrame),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is ConstrainedBox && w.constraints.maxHeight.isFinite,
                  ),
                )
                .first,
          )
          .constraints;
      expect(constraints.maxWidth, 720);
      expect(constraints.maxHeight, 800 * 0.85);
      expect(tester.getSize(find.byWidget(_dialogSurface(tester))).width, 720);
    });

    testWidgets('מסך צר: 90% מרוחב החלון, עד ריפוד ברירת המחדל של Dialog', (
      tester,
    ) async {
      await showInApp<void>(tester, frame(), size: const Size(600, 800));
      // 90% הם 540, אבל Dialog משאיר 40 מכל צד.
      expect(
        tester.getSize(find.byWidget(_dialogSurface(tester))).width,
        600 - 2 * 40,
      );
    });

    testWidgets('משטח הדיאלוג של התמה, מונה ב-bodyMedium onSurfaceVariant', (
      tester,
    ) async {
      await showInApp<void>(tester, frame());
      final context = tester.element(find.byType(ListDialogFrame));
      final theme = Theme.of(context);
      final surface = _dialogSurface(tester);
      expect(surface.color, theme.colorScheme.surfaceContainerHigh);
      expect(surface.shape, AppTokens.roundedShape);

      final counter = tester.widget<Text>(find.text('12 ספרים'));
      expect(counter.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
      expect(counter.style?.color, theme.colorScheme.onSurfaceVariant);
      final header = tester.widget<AppDialogHeader>(
        find.byType(AppDialogHeader),
      );
      expect(header.compact, isTrue);
    });

    testWidgets('גוף הרשימה בריפוד 24 מהצדדים ו-16 מלמטה', (tester) async {
      await showInApp<void>(tester, frame());
      final surface = tester.getRect(find.byWidget(_dialogSurface(tester)));
      final row = tester.getRect(find.text('שורה'));
      expect(row.right, surface.right - 24);
      expect(surface.bottom - row.bottom, 16);
    });

    testWidgets('ListDialogCard: משטח כרטיס, פינות 8 ומסגרת outlineVariant', (
      tester,
    ) async {
      await pumpInApp(tester, const ListDialogCard(child: Text('שורה')));
      final context = tester.element(find.byType(ListDialogCard));
      final material = firstMaterialIn(tester, find.byType(ListDialogCard));
      expect(material.color, AppSurfaces.card(context));
      expect(
        material.shape,
        RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      );
    });
  });
}
