import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
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
    testWidgets('משטח surfaceContainerHigh בפינות 8, רצועה ותג תמיד', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'מחיקת קבוצה', content: 'להמשיך?'),
      );
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));

      expect(surface.color, cs.surfaceContainerHigh);
      expect(surface.shape, AppTokens.roundedShape);
      final header = tester.widget<AppDialogHeader>(
        find.byType(AppDialogHeader),
      );
      expect(header.compact, isTrue);
      // בלי אייקון שאומר משהו: אייקון משפחת האישור.
      expect(header.icon, AppDialogIcons.confirm);
      expect(find.byType(AppDialogIconBadge), findsOneWidget);
      final title = tester.widget<Text>(find.text('מחיקת קבוצה'));
      expect(
        title.style,
        Theme.of(
          tester.element(find.byType(AppDialogFrame)),
        ).textTheme.titleLarge,
      );
    });

    testWidgets('small: רוחב 400, הגוף בריפוד dialogPadding', (tester) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      final frame = tester.widget<AppDialogFrame>(find.byType(AppDialogFrame));
      expect(frame.size, AppDialogSize.small);
      expect(frame.padding, AppTokens.dialogPadding);
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(tester.getSize(find.byWidget(surface)).width, 400);
    });

    testWidgets('ביטול tonal לפני אישור מלא, באותה צורה של 8', (tester) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
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
      final cs = Theme.of(
        tester.element(find.byType(AppDialogFrame)),
      ).colorScheme;
      expect(barrier.color, AppSurfaces.scrim(cs));
    });
  });

  group('AppDialog — רצועת הכותרת', () {
    testWidgets('רצועת כותרת surfaceContainerHighest עם קו outlineVariant', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'ייבוא ספרים',
          content: 'תוכן',
          icon: FluentIcons.folder_24_regular,
        ),
      );
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
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

      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(surface.clipBehavior, Clip.antiAlias);
      expect(
        tester.widget<AppDialogFrame>(find.byType(AppDialogFrame)).padding,
        const EdgeInsets.fromLTRB(24, 16, 24, 16),
      );
    });

    testWidgets('תג האייקון: ריבוע מעוגל 40 ב-primaryContainer, אייקון 20', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: 'תוכן',
          icon: FluentIcons.folder_24_regular,
        ),
      );
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
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
      expect(icon.size, AppTokens.iconMD);
      expect(icon.color, cs.onPrimaryContainer);
    });

    testWidgets('small: בלי איקס בכותרת (DD-07)', (tester) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(title: 'כותרת', content: 'תוכן'),
      );
      expect(find.byType(AppDialogHeader), findsOneWidget);
      expect(find.byTooltip('סגור'), findsNothing);
    });

    testWidgets('האיקס בכותרת סוגר עם false, כמו ביטול', (tester) async {
      final outcome = await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'כותרת',
          content: 'תוכן',
          size: AppDialogSize.medium,
        ),
      );
      final close = find.byTooltip('סגור');
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(outcome.closed, isTrue);
      expect(outcome.value, isFalse);
    });

    testWidgets('headerTrailing יושב בכותרת לפני האיקס', (tester) async {
      await showInApp<bool>(
        tester,
        const AppDialog.twoActions(
          title: 'בחירת תאריך',
          customContent: Text('לוח'),
          headerTrailing: Text('עברי'),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(AppDialogHeader),
          matching: find.text('עברי'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('size: medium לתוכן מותאם רחב', (tester) async {
      await showInApp<bool>(
        tester,
        const AppDialog.singleAction(
          title: 'אודות',
          customContent: Text('פרטים'),
          size: AppDialogSize.medium,
        ),
      );
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(tester.getSize(find.byWidget(surface)).width, 560);
    });
  });

  group('AppDialog.warning', () {
    testWidgets('תג אזהרה בגוון error, ביטול מלא ואישור מלא ב-error', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.warning(title: 'איפוס', content: 'כל ההגדרות יאופסו'),
      );
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
      final header = tester.widget<AppDialogHeader>(
        find.byType(AppDialogHeader),
      );
      expect(header.icon, FluentIcons.warning_24_regular);
      expect(header.tone, AppDialogHeaderTone.error);
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
      final confirm = firstMaterialIn(tester, _button<FilledButton>('המשך'));
      expect(confirm.color, cs.error);
      expect(confirm.textStyle?.color, cs.onError);
      expect(confirm.shape, AppTokens.roundedShape);
    });

    testWidgets('שורת המשנה ב־bodySmall בצבע error (DESIGN_SYSTEM §2.4.1)', (
      tester,
    ) async {
      await showInApp<bool>(
        tester,
        const AppDialog.warning(
          title: 'איפוס',
          content: 'כל ההגדרות יאופסו',
          subtitle: 'אי אפשר לבטל',
        ),
      );
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
      final subtitle = tester.widget<Text>(find.text('אי אפשר לבטל'));
      expect(subtitle.style?.color, cs.error);
      final bodySmall = Theme.of(
        tester.element(find.text('אי אפשר לבטל')),
      ).textTheme.bodySmall!;
      expect(subtitle.style?.fontSize, bodySmall.fontSize);
      expect(subtitle.style?.height, bodySmall.height);
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
      final cs = schemeAt(tester, find.byType(AppDialogFrame));
      expect(
        tester.widget<AppDialogHeader>(find.byType(AppDialogHeader)).icon,
        AppDialogIcons.info,
      );
      // כפתור אחד מלבד ה-X שבכותרת.
      int buttonsIn(Type type) => find
          .descendant(
            of: find.byType(type),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .evaluate()
          .length;
      expect(buttonsIn(AppDialogFrame) - buttonsIn(AppDialogHeader), 1);
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
      expect(find.byType(AppDialogFrame), findsOneWidget);
    });

    testWidgets(
      'scrollable: הגוף גולל בתוך ריפוד הדיאלוג, ופס הגלילה בשוליים',
      (
        tester,
      ) async {
        await showInApp<bool>(
          tester,
          AppDialog.singleAction(
            title: 'הסבר',
            size: AppDialogSize.medium,
            scrollable: true,
            customContent: Column(
              children: [for (var i = 0; i < 60; i++) Text('שורה $i')],
            ),
          ),
        );
        final frame = tester.widget<AppDialogFrame>(
          find.byType(AppDialogFrame),
        );
        expect(frame.scrollable, isTrue);
        final body = find.byType(PanelScrollableContent);
        expect(body, findsOneWidget);
        expect(
          tester.widget<PanelScrollableContent>(body).padding,
          AppTokens.dialogPadding,
        );
        // ריפוד הדיאלוג בתוך הגלילה: הטקסט רחוק מקצות הגוף, שם יושב הפס.
        final bodyRect = tester.getRect(body);
        final lineRect = tester.getRect(
          find.descendant(of: body, matching: find.byType(Column)).first,
        );
        expect(
          lineRect.left - bodyRect.left,
          AppTokens.dialogPadding.horizontal / 2,
        );
        expect(
          bodyRect.right - lineRect.right,
          AppTokens.dialogPadding.horizontal / 2,
        );
      },
    );
  });

  group('AppDialogFrame', () {
    testWidgets('medium כברירת מחדל: רוחב 560, ריפוד חיצוני 16, משטח התמה', (
      tester,
    ) async {
      await showInApp<void>(
        tester,
        AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
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

    // DD-16: מתחת ל-600 small/medium ברוחב החלון פחות 16, large/full במסך מלא.
    for (final size in [AppDialogSize.small, AppDialogSize.medium]) {
      testWidgets('מתחת ל-600: ${size.name} ברוחב החלון פחות 16', (
        tester,
      ) async {
        await showInApp<void>(
          tester,
          AppDialogFrame(
            title: 'מסגרת',
            icon: FluentIcons.folder_24_regular,
            size: size,
            child: const Text('גוף'),
          ),
          size: const Size(590, 800),
        );
        final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
        final rect = tester.getRect(find.byWidget(surface));
        expect(rect.width, 590 - 16);
        expect(rect.height, lessThan(300));
        expect(surface.shape, AppTokens.roundedShape);
      });
    }

    for (final size in [AppDialogSize.large, AppDialogSize.full]) {
      testWidgets('מתחת ל-600: ${size.name} במסך מלא, בלי פינות, עם X', (
        tester,
      ) async {
        await showInApp<void>(
          tester,
          AppDialogFrame(
            title: 'מסגרת',
            icon: FluentIcons.folder_24_regular,
            size: size,
            child: const Text('גוף'),
          ),
          size: const Size(400, 800),
        );
        final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
        expect(tester.getSize(find.byWidget(surface)), const Size(400, 800));
        expect(surface.shape, const RoundedRectangleBorder());
        expect(find.byTooltip('סגור'), findsOneWidget);
      });
    }

    testWidgets('מ-600 ומעלה: small נשאר 400 בפינות 8', (tester) async {
      await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          size: AppDialogSize.small,
          child: Text('גוף'),
        ),
        size: const Size(600, 800),
      );
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(tester.getSize(find.byWidget(surface)).width, 400);
    });

    testWidgets('שורת הפעולות צמודה לסוף (שמאל ב-RTL), בריפוד dialogPadding', (
      tester,
    ) async {
      await showInApp<void>(
        tester,
        AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          actions: [ActionButton.recommended(text: 'שמור', onPressed: () {})],
          child: const Text('גוף'),
        ),
      );
      final surface = tester.getRect(
        find.byWidget(firstMaterialIn(tester, find.byType(AppDialogFrame))),
      );
      final save = tester.getRect(_button<FilledButton>('שמור'));
      expect(save.left - surface.left, 24);
      expect(surface.bottom - save.bottom, 16);
    });

    for (final (size, width) in [
      (AppDialogSize.small, 400.0),
      (AppDialogSize.medium, 560.0),
      (AppDialogSize.large, 720.0),
      (AppDialogSize.full, 1200.0 - 32),
    ]) {
      testWidgets('${size.name}: רוחב $width', (tester) async {
        await showInApp<void>(
          tester,
          AppDialogFrame(
            title: 'מסגרת',
            icon: FluentIcons.folder_24_regular,
            size: size,
            child: const Text('גוף'),
          ),
        );
        final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
        expect(tester.getSize(find.byWidget(surface)).width, width);
      });
    }

    testWidgets('large: גובה לפי התוכן', (tester) async {
      await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          size: AppDialogSize.large,
          child: SizedBox(height: 100),
        ),
      );
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(tester.getSize(find.byWidget(surface)).height, lessThan(300));
    });

    testWidgets('large: תוכן ארוך נעצר ב-85% מגובה החלון', (tester) async {
      await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          size: AppDialogSize.large,
          scrollable: true,
          child: SizedBox(height: 2000),
        ),
      );
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(tester.getSize(find.byWidget(surface)).height, 800 * 0.85);
    });

    testWidgets('full: ממלא את החלון פחות הריפוד', (tester) async {
      await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          size: AppDialogSize.full,
          child: Text('גוף'),
        ),
      );
      final surface = firstMaterialIn(tester, find.byType(AppDialogFrame));
      expect(
        tester.getSize(find.byWidget(surface)),
        const Size(1200 - 32, 800 - 32),
      );
    });

    // DD-07: X לפי הגודל — בלי X ב-small, עם X מ-medium; showClose גובר.
    for (final (size, showClose, expected) in [
      (AppDialogSize.small, null, findsNothing),
      (AppDialogSize.medium, null, findsOneWidget),
      (AppDialogSize.large, null, findsOneWidget),
      (AppDialogSize.small, true, findsOneWidget),
    ]) {
      testWidgets('X ב-${size.name} (showClose: $showClose)', (tester) async {
        await showInApp<void>(
          tester,
          AppDialogFrame(
            title: 'מסגרת',
            icon: FluentIcons.folder_24_regular,
            size: size,
            showClose: showClose,
            child: const Text('גוף'),
          ),
        );
        expect(find.byTooltip('סגור'), expected);
      });
    }

    testWidgets('מתחת ל-600: small בלי X', (tester) async {
      await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          size: AppDialogSize.small,
          child: Text('גוף'),
        ),
        size: const Size(400, 800),
      );
      expect(find.byTooltip('סגור'), findsNothing);
    });

    testWidgets('showClose: false מסתיר את האיקס', (tester) async {
      await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          showClose: false,
          child: Text('גוף'),
        ),
      );
      expect(find.byTooltip('סגור'), findsNothing);
    });

    testWidgets('הכותרת היא שם המסלול לקורא מסך', (tester) async {
      final handle = tester.ensureSemantics();
      await showInApp<void>(
        tester,
        const AppDialogFrame(
          title: 'מסגרת',
          icon: FluentIcons.folder_24_regular,
          child: Text('גוף'),
        ),
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
