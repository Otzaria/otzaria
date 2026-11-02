import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import 'contract_harness.dart';

Finder _button<T extends Widget>(String text) => find
    .ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate((w) => w is T),
    )
    .first;

void main() {
  group('AppDialog.twoActions', () {
    testWidgets('משטח surfaceContainerHigh בפינות 8 וכותרת titleLarge', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'מחיקת קבוצה', content: 'להמשיך?'),
      );
      final cs = schemeAt(tester, find.byType(AlertDialog));
      final surface = firstMaterialIn(tester, find.byType(AlertDialog));

      expect(surface.color, cs.surfaceContainerHigh);
      expect(surface.shape, AppTokens.roundedShape);
      expect(find.byType(AppDialogTitle), findsOneWidget);
      expect(find.byType(AppDialogHeader), findsNothing);
      expect(find.byType(AppDialogIconBadge), findsNothing);
      final title = tester.widget<Text>(find.text('מחיקת קבוצה'));
      expect(
        title.style,
        Theme.of(tester.element(find.byType(AlertDialog))).textTheme.titleLarge,
      );
    });

    testWidgets('ביטול tonal לפני אישור מלא, באותה צורה של 8', (tester) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      final cs = schemeAt(tester, find.byType(AlertDialog));
      final cancel = firstMaterialIn(tester, _button<FilledButton>('ביטול'));
      final confirm = firstMaterialIn(tester, _button<FilledButton>('אישור'));

      expect(cancel.color, cs.secondaryContainer);
      expect(confirm.color, cs.primary);
      expect(cancel.shape, AppTokens.roundedShape);
      expect(confirm.shape, AppTokens.roundedShape);
      // RTL: הביטול בצד ימין של האישור.
      expect(
        tester.getCenter(find.text('ביטול')).dx,
        greaterThan(tester.getCenter(find.text('אישור')).dx),
      );
    });

    testWidgets('אישור מחזיר true וביטול מחזיר false', (tester) async {
      var outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isTrue);

      outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isFalse);
    });

    testWidgets('לחיצה על הרקע סוגרת עם null', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isNull);
    });

    testWidgets('רקע הכיסוי של הדיאלוג הוא AppSurfaces.scrim', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      final barrier = tester.widget<ModalBarrier>(
        find.byType(ModalBarrier).last,
      );
      final cs = Theme.of(tester.element(find.byType(AlertDialog))).colorScheme;
      expect(barrier.color, AppSurfaces.scrim(cs));
    });
  });

  group('AppDialog.twoActions עם headerBand', () {
    testWidgets('רצועת כותרת surfaceContainerHighest עם קו outlineVariant', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'ייבוא ספרים',
          content: 'תוכן',
          icon: FluentIcons.folder_24_regular,
          headerBand: true,
        ),
      );
      final cs = schemeAt(tester, find.byType(AlertDialog));
      final header = tester.widget<AppDialogHeader>(
        find.byType(AppDialogHeader),
      );
      expect(header.compact, isTrue);
      expect(header.icon, FluentIcons.folder_24_regular);

      final band = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppDialogHeader),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = band.decoration! as BoxDecoration;
      expect(decoration.color, cs.surfaceContainerHighest);
      expect(
        decoration.border,
        Border(bottom: BorderSide(color: cs.outlineVariant)),
      );
      expect(
        band.padding,
        const EdgeInsetsDirectional.fromSTEB(24, 8, 8, 8),
      );

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.clipBehavior, Clip.antiAlias);
      expect(dialog.titlePadding, EdgeInsets.zero);
      expect(dialog.contentPadding, const EdgeInsets.fromLTRB(24, 16, 24, 16));
    });

    testWidgets('תג האייקון: ריבוע מעוגל 40 ב-primaryContainer, אייקון 22', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: 'תוכן',
          icon: FluentIcons.folder_24_regular,
          headerBand: true,
        ),
      );
      final cs = schemeAt(tester, find.byType(AlertDialog));
      expect(
        tester.getSize(find.byType(AppDialogIconBadge)),
        const Size(40, 40),
      );
      final badge = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppDialogIconBadge),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = badge.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, AppTokens.borderRadiusAll);
      expect(decoration.color, cs.primaryContainer);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(AppDialogIconBadge),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.size, 22);
      expect(icon.color, cs.onPrimaryContainer);
    });

    testWidgets('האיקס בכותרת סוגר עם null', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: 'תוכן',
          headerBand: true,
        ),
      );
      final close = find.byTooltip('סגור');
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isNull);
    });
  });

  group('AppDialog.warning', () {
    testWidgets('תג אזהרה בגוון error, ביטול מלא ואישור טקסט אדום', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.warning(title: 'איפוס', content: 'כל ההגדרות יאופסו'),
      );
      final cs = schemeAt(tester, find.byType(AlertDialog));
      final title = tester.widget<AppDialogTitle>(find.byType(AppDialogTitle));
      expect(title.icon, FluentIcons.warning_24_regular);
      expect(title.tone, AppDialogHeaderTone.error);
      final badge = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppDialogIconBadge),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((badge.decoration! as BoxDecoration).color, cs.errorContainer);

      final cancel = firstMaterialIn(tester, _button<FilledButton>('ביטול'));
      expect(cancel.color, cs.primary);
      final confirm = firstMaterialIn(tester, _button<TextButton>('המשך'));
      expect(confirm.color, Colors.transparent);
      expect(confirm.textStyle?.color, cs.error);
      expect(confirm.shape, AppTokens.roundedShape);
    });

    testWidgets('שורת המשנה בצבע error בגודל 13', (tester) async {
      await showInApp<bool>(
        tester,
        const AppDialog.warning(
          title: 'איפוס',
          content: 'כל ההגדרות יאופסו',
          subtitle: 'אי אפשר לבטל',
        ),
      );
      final cs = schemeAt(tester, find.byType(AlertDialog));
      final subtitle = tester.widget<Text>(find.text('אי אפשר לבטל'));
      expect(subtitle.style?.color, cs.error);
      expect(subtitle.style?.fontSize, 13);
    });

    testWidgets('showWarningDialog: טקסט האישור כברירת מחדל הוא "איפוס"', (
      tester,
    ) async {
      final outcome = await openDialog<bool>(
        tester,
        (context) => showWarningDialog(
          context: context,
          title: 'כותרת',
          content: 'תוכן',
        ),
      );
      expect(find.text('איפוס'), findsOneWidget);
      await tester.tap(find.text('איפוס'));
      await tester.pumpAndSettle();
      expect(outcome.value, isTrue);
    });
  });

  group('AppDialog.singleAction', () {
    testWidgets('כפתור אישור מלא יחיד שמחזיר true', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.singleAction(title: 'הודעה', content: 'הסתיים'),
      );
      final cs = schemeAt(tester, find.byType(AlertDialog));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
        findsOneWidget,
      );
      expect(
        firstMaterialIn(tester, _button<FilledButton>('אישור')).color,
        cs.primary,
      );
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();
      expect(outcome.value, isTrue);
    });

    testWidgets('onConfirm שמחזיר false משאיר את הדיאלוג פתוח', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        AppDialog.singleAction(
          title: 'הודעה',
          content: 'הסתיים',
          onConfirm: () => false,
        ),
      );
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();
      expect(outcome.closed, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('AppDialogFrame', () {
    testWidgets('רוחב 560, ריפוד חיצוני 16, משטח הדיאלוג של התמה', (
      tester,
    ) async {
      await showInApp<void>(
        tester,
        AppDialogFrame(
          title: 'מסגרת',
          actions: [ActionButton.recommended(text: 'שמור', onPressed: () {})],
          child: const Text('גוף'),
        ),
      );
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(surface.color, cs.surfaceContainerHigh);
      expect(surface.shape, AppTokens.roundedShape);
      expect(surface.clipBehavior, Clip.antiAlias);
      expect(tester.getSize(find.byWidget(surface)).width, 560);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.insetPadding, const EdgeInsets.all(16));
      expect(
        tester.widget<AppDialogHeader>(find.byType(AppDialogHeader)).compact,
        isTrue,
      );
    });

    testWidgets('במסך צר הרוחב מצטמצם לרוחב הפנוי פחות הריפוד', (tester) async {
      await showInApp<void>(
        tester,
        const AppDialogFrame(title: 'מסגרת', child: Text('גוף')),
        size: const Size(400, 800),
      );
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(tester.getSize(find.byWidget(surface)).width, 400 - 32);
    });

    testWidgets('שורת הפעולות צמודה לסוף (שמאל ב-RTL)', (tester) async {
      await showInApp<void>(
        tester,
        AppDialogFrame(
          title: 'מסגרת',
          actions: [ActionButton.recommended(text: 'שמור', onPressed: () {})],
          child: const Text('גוף'),
        ),
      );
      final surface = tester.getRect(
        find.byWidget(firstMaterialIn(tester, find.byType(AppDialogFrame))),
      );
      final save = tester.getRect(_button<FilledButton>('שמור'));
      expect(save.left - surface.left, 16);
    });

    testWidgets('הכותרת היא שם המסלול לקורא מסך', (tester) async {
      final handle = tester.ensureSemantics();
      await showInApp<void>(
        tester,
        const AppDialogFrame(title: 'מסגרת', child: Text('גוף')),
      );
      expect(
        tester.getSemantics(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'מסגרת',
          ),
        ),
        isSemantics(
          label: 'מסגרת',
          scopesRoute: true,
          namesRoute: true,
        ),
      );
      handle.dispose();
    });
  });
}
