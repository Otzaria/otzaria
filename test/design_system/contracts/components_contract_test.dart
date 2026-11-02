import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import 'contract_harness.dart';

BoxDecoration _decorationIn(WidgetTester tester, Finder of) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(of: of, matching: find.byType(DecoratedBox))
                  .first,
            )
            .decoration
        as BoxDecoration;

void main() {
  group('AppCard', () {
    for (final brightness in Brightness.values) {
      testWidgets('ב-$brightness: משטח AppSurfaces.card בפינות 8 ובמסגרת', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          const AppCard(child: Text('כרטיס')),
          brightness: brightness,
        );
        final context = tester.element(find.byType(AppCard));
        final cs = Theme.of(context).colorScheme;
        final material = firstMaterialIn(tester, find.byType(AppCard));
        expect(
          material.color,
          brightness == Brightness.dark ? cs.surfaceContainer : cs.surface,
        );
        expect(
          material.shape,
          RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusAll,
            side: BorderSide(color: cs.outlineVariant),
          ),
        );
        expect(material.clipBehavior, Clip.antiAlias);
        expect(material.elevation, 0);
      });
    }

    testWidgets('לחיץ: בלי surfaceTint ועם InkWell', (tester) async {
      await pumpInApp(
        tester,
        AppCard(onTap: () {}, child: const Text('כרטיס')),
      );
      final material = firstMaterialIn(tester, find.byType(AppCard));
      expect(material.surfaceTintColor, Colors.transparent);
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('נבחר: רקע selectedRow', (tester) async {
      await pumpInApp(
        tester,
        const AppCard(selected: true, child: Text('כרטיס')),
      );
      final context = tester.element(find.byType(AppCard));
      final overlay = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(
        overlay.color,
        AppSurfaces.selectedRow(Theme.of(context).colorScheme),
      );
    });

    testWidgets('section: רווח 1.5 בין שורות ופינות 8 חיצוניות', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const AppCard.section(children: [Text('שורה א'), Text('שורה ב')]),
      );
      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, AppTokens.borderRadiusAll);
      final gap =
          tester.getTopLeft(find.text('שורה ב')).dy -
          tester.getBottomLeft(find.text('שורה א')).dy;
      expect(gap, AppCard.sectionSpacing);
      expect(AppCard.sectionSpacing, 1.5);
    });
  });

  group('MetaChip', () {
    testWidgets('ברירת מחדל: secondaryContainer, פינות 8, טקסט 12', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const Center(
          child: MetaChip(label: 'ראשונים', icon: FluentIcons.clock_24_regular),
        ),
      );
      final cs = schemeAt(tester, find.byType(MetaChip));
      final decoration = _decorationIn(tester, find.byType(MetaChip));
      expect(decoration.color, cs.secondaryContainer);
      expect(decoration.border, isNull);
      expect(decoration.borderRadius, AppTokens.borderRadiusAll);

      final text = tester.widget<Text>(find.text('ראשונים'));
      expect(text.style?.fontSize, 12);
      expect(text.style?.color, cs.onSecondaryContainer);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 14);
      expect(icon.color, cs.onSecondaryContainer);
      expect(
        tester
            .widget<Padding>(
              find
                  .descendant(
                    of: find.byType(MetaChip),
                    matching: find.byType(Padding),
                  )
                  .first,
            )
            .padding,
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      );
    });

    testWidgets('outlined: בלי מילוי, מסגרת outlineVariant', (tester) async {
      await pumpInApp(
        tester,
        const Center(child: MetaChip(label: 'דור', outlined: true)),
      );
      final cs = schemeAt(tester, find.byType(MetaChip));
      final decoration = _decorationIn(tester, find.byType(MetaChip));
      expect(decoration.color, isNull);
      expect(decoration.border, Border.all(color: cs.outlineVariant));
      expect(
        tester.widget<Text>(find.text('דור')).style?.color,
        cs.onSurfaceVariant,
      );
    });

    testWidgets('error: errorContainer ו-onErrorContainer', (tester) async {
      await pumpInApp(
        tester,
        const Center(child: MetaChip(label: 'חסר', error: true)),
      );
      final cs = schemeAt(tester, find.byType(MetaChip));
      expect(
        _decorationIn(tester, find.byType(MetaChip)).color,
        cs.errorContainer,
      );
      expect(
        tester.widget<Text>(find.text('חסר')).style?.color,
        cs.onErrorContainer,
      );
    });
  });

  group('BarButton', () {
    testWidgets('icon בלי label: עיגול 40, אייקון 20 ב-onSurfaceVariant', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        Center(
          child: BarButton.icon(
            tooltip: 'חיפוש',
            icon: FluentIcons.search_24_regular,
            onPressed: () {},
          ),
        ),
      );
      final cs = schemeAt(tester, find.byType(BarButton));
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.style?.shape?.resolve({}), const CircleBorder());
      expect(tester.getSize(find.byType(IconButton)), const Size(40, 40));
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, Colors.transparent);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 20);
      expect(icon.color, cs.onSurfaceVariant);
      expect(BarButton.toolbarWidth(false), 44);
    });

    testWidgets('icon compact: 36', (tester) async {
      await pumpInApp(
        tester,
        Center(
          child: BarButton.icon(
            tooltip: 'חיפוש',
            icon: FluentIcons.search_24_regular,
            onPressed: () {},
            compact: true,
          ),
        ),
      );
      expect(tester.getSize(find.byType(IconButton)), const Size(36, 36));
      expect(BarButton.toolbarWidth(true), 40);
    });

    testWidgets(
      'icon נבחר: רקע barButtonSelected ואייקון onSecondaryContainer',
      (
        tester,
      ) async {
        await pumpInApp(
          tester,
          Center(
            child: BarButton.icon(
              tooltip: 'חיפוש',
              icon: FluentIcons.search_24_regular,
              onPressed: () {},
              selected: true,
            ),
          ),
        );
        final cs = schemeAt(tester, find.byType(BarButton));
        final decoration =
            tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration!
                as BoxDecoration;
        expect(decoration.color, AppSurfaces.barButtonSelected(cs));
        expect(
          tester.widget<Icon>(find.byType(Icon)).color,
          cs.onSecondaryContainer,
        );
      },
    );

    testWidgets('icon עם label: פינות 8, גובה 40, טקסט 14', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        Center(
          child: BarButton.icon(
            tooltip: 'ספרייה',
            icon: FluentIcons.library_24_regular,
            label: 'ספרייה',
            onPressed: () {},
          ),
        ),
      );
      final material = firstMaterialIn(
        tester,
        find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(material.shape, AppTokens.roundedShape);
      final decoration =
          tester
                  .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                  .decoration!
              as BoxDecoration;
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, AppTokens.borderRadiusAll);
      expect(
        tester.getSize(find.byWidgetPredicate((w) => w is FilledButton)).height,
        40,
      );
      final label = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text('ספרייה'),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      );
      expect(label.style.fontSize, 14);
    });

    testWidgets('text: TextButton בצורת התמה (8) בצבע onSurfaceVariant', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        Center(
          child: BarButton.text(text: 'כניסה', onPressed: () {}),
        ),
      );
      final cs = schemeAt(tester, find.byType(BarButton));
      final material = firstMaterialIn(tester, find.byType(TextButton));
      expect(material.shape, AppTokens.roundedShape);
      expect(material.textStyle?.color, cs.onSurfaceVariant);
    });
  });

  group('OtzariaEmptyState', () {
    testWidgets('רגיל: אייקון 56, כותרת titleMedium w600, הודעה bodyMedium', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const OtzariaEmptyState(
          icon: FluentIcons.search_24_regular,
          title: 'אין תוצאות',
          message: 'נסה מילה אחרת',
        ),
      );
      final theme = Theme.of(tester.element(find.byType(OtzariaEmptyState)));
      final cs = theme.colorScheme;
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 56);
      expect(icon.color, cs.onSurfaceVariant);

      final title = tester.widget<Text>(find.text('אין תוצאות')).style!;
      expect(title.fontSize, theme.textTheme.titleMedium!.fontSize);
      expect(title.fontSize, 16);
      expect(title.fontWeight, FontWeight.w600);
      expect(title.color, cs.onSurface);

      final message = tester.widget<Text>(find.text('נסה מילה אחרת')).style!;
      expect(message.fontSize, 14);
      expect(message.color, cs.onSurfaceVariant);

      expect(
        tester.getTopLeft(find.text('אין תוצאות')).dy -
            tester.getBottomLeft(find.byType(Icon)).dy,
        16,
      );
      expect(
        tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView),
            )
            .padding,
        const EdgeInsets.all(24),
      );
    });

    testWidgets('קומפקטי: אייקון 36, כותרת bodyMedium (14) w600, הודעה 12', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const OtzariaEmptyState(
          icon: FluentIcons.search_24_regular,
          title: 'אין תוצאות',
          message: 'נסה מילה אחרת',
          isCompact: true,
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 36);
      final title = tester.widget<Text>(find.text('אין תוצאות')).style!;
      expect(title.fontSize, 14);
      expect(title.fontWeight, FontWeight.w600);
      final message = tester.widget<Text>(find.text('נסה מילה אחרת')).style!;
      expect(message.fontSize, 12);
      expect(
        tester.getTopLeft(find.text('אין תוצאות')).dy -
            tester.getBottomLeft(find.byType(Icon)).dy,
        8,
      );
      expect(
        tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView),
            )
            .padding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
    });

    testWidgets('כפתורי פעולה במרווח 24 מהטקסט, ממורכזים', (tester) async {
      await pumpInApp(
        tester,
        OtzariaEmptyState(
          title: 'אין ספרים',
          action: ActionButton.recommended(text: 'הוסף', onPressed: () {}),
        ),
      );
      final wrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(wrap.alignment, WrapAlignment.center);
      expect(wrap.spacing, 8);
      expect(
        tester.getTopLeft(find.byType(Wrap)).dy -
            tester.getBottomLeft(find.text('אין ספרים')).dy,
        24,
      );
    });
  });

  group('OtzariaErrorState', () {
    testWidgets('אייקון error 56 (36 בקומפקטי) על מבנה מצב הריק', (
      tester,
    ) async {
      for (final compact in [false, true]) {
        await pumpInApp(
          tester,
          OtzariaErrorState(
            title: 'הטעינה נכשלה',
            details: 'פרטים',
            isCompact: compact,
          ),
        );
        final cs = schemeAt(tester, find.byType(OtzariaErrorState));
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.icon, FluentIcons.error_circle_24_regular);
        expect(icon.size, compact ? 36 : 56);
        expect(icon.color, cs.error);
        final empty = tester.widget<OtzariaEmptyState>(
          find.byType(OtzariaEmptyState),
        );
        expect(empty.isCompact, compact);
        expect(empty.message, 'פרטים');
      }
    });

    testWidgets('details ריק לא מציג הודעה', (tester) async {
      await pumpInApp(
        tester,
        const OtzariaErrorState(title: 'הטעינה נכשלה', details: ''),
      );
      expect(
        tester
            .widget<OtzariaEmptyState>(find.byType(OtzariaEmptyState))
            .message,
        isNull,
      );
    });
  });

  group('LoadingIndicator', () {
    testWidgets('בלי size: ממורכז, עובי 4, צבע primary של התמה', (
      tester,
    ) async {
      await pumpInApp(tester, const LoadingIndicator());
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.strokeWidth, 4);
      expect(indicator.valueColor, isNull);
      expect(
        find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(Center),
        ),
        findsWidgets,
      );
    });

    testWidgets('עם size: תיבה ריבועית בגודל המבוקש', (tester) async {
      await pumpInApp(
        tester,
        const Center(child: LoadingIndicator(size: 20, strokeWidth: 2)),
      );
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(20, 20),
      );
    });
  });

  group('SquareIconButton', () {
    for (final slim in [false, true]) {
      testWidgets('field slim=$slim: ריבוע בגובה שדה, tonal, פינות 8', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          Center(
            child: SquareIconButton.field(
              icon: FluentIcons.filter_24_regular,
              tooltip: 'סינון',
              onPressed: () {},
              slim: slim,
            ),
          ),
        );
        final cs = schemeAt(tester, find.byType(SquareIconButton));
        final side = slim ? 36.0 : 48.0;
        expect(tester.getSize(find.byType(IconButton)), Size(side, side));
        final material = firstMaterialIn(tester, find.byType(IconButton));
        expect(material.color, cs.surfaceContainerHighest);
        expect(material.shape, AppTokens.roundedShape);
        expect(tester.widget<Icon>(find.byType(Icon)).size, slim ? 18 : 20);
      });
    }

    testWidgets('toolbar: רקע שקוף', (tester) async {
      await pumpInApp(
        tester,
        Center(
          child: SquareIconButton.toolbar(
            icon: FluentIcons.filter_24_regular,
            tooltip: 'סינון',
            onPressed: () {},
            slim: false,
          ),
        ),
      );
      expect(
        firstMaterialIn(tester, find.byType(IconButton)).color,
        Colors.transparent,
      );
    });
  });

  group('SettingsCard', () {
    testWidgets('כותרת titleMedium מודגשת ב-primary מעל AppCard.section', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const SingleChildScrollView(
          child: SettingsCard(
            title: 'תצוגה',
            subtitle: 'הגדרות המסך',
            children: [Text('שורה')],
          ),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(SettingsCard)));
      final title = tester.widget<Text>(find.text('תצוגה')).style!;
      expect(title.fontSize, theme.textTheme.titleMedium!.fontSize);
      expect(title.fontWeight, FontWeight.bold);
      expect(title.color, theme.colorScheme.primary);
      final subtitle = tester.widget<Text>(find.text('הגדרות המסך')).style!;
      expect(subtitle.color, theme.colorScheme.onSurfaceVariant);
      expect(find.byType(AppCard), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(AppCard)).dy -
            tester.getBottomLeft(find.text('הגדרות המסך')).dy,
        12,
      );
    });

    testWidgets('בלי כותרת: AppCard.section בלבד', (tester) async {
      await pumpInApp(
        tester,
        const SingleChildScrollView(
          child: SettingsCard(children: [Text('שורה')]),
        ),
      );
      expect(
        tester.getTopLeft(find.byType(AppCard)),
        tester.getTopLeft(find.byType(SettingsCard)),
      );
    });
  });
}
