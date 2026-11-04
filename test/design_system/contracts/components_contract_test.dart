import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
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
  // DD-04, q9 שאלה 3, q10 שאלה 22: כפתור אייקון שקוף עגול מערכת הנושא, וכפתור
  // אייקון עם רקע גלוי משלו נשאר בפינות 8.
  group('צורת כפתורי אייקון', () {
    testWidgets('שקוף: עיגול מ-iconButtonTheme', (tester) async {
      await pumpInApp(
        tester,
        IconButton(
          tooltip: 'מחק',
          icon: const Icon(FluentIcons.delete_24_regular),
          onPressed: () {},
        ),
      );
      final material = firstMaterialIn(tester, find.byType(IconButton));
      expect(material.shape, const CircleBorder());
    });

    for (final (name, button) in <(String, Widget)>[
      (
        'SecondaryIconButton',
        SecondaryIconButton(
          icon: FluentIcons.edit_24_regular,
          tooltip: 'עריכה',
          onPressed: () {},
        ),
      ),
      ('PrimaryIconButton', PrimaryIconButton(onPressed: () {})),
      (
        'OtzariaSearchFieldButton נבחר',
        OtzariaSearchFieldButton(
          icon: FluentIcons.filter_24_regular,
          tooltip: 'סינון',
          selected: true,
          onPressed: () {},
        ),
      ),
    ]) {
      testWidgets('עם רקע: $name נשאר בפינות 8', (tester) async {
        await pumpInApp(tester, button);
        final material = firstMaterialIn(tester, find.byType(IconButton));
        expect(material.shape, AppTokens.roundedShape);
      });
    }
  });

  group('AppCard', () {
    testWidgets('active: מסגרת הבחירה (primary, 1.5) במקום outlineVariant', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        AppCard(active: true, onTap: () {}, child: const Text('כרטיס')),
      );
      final cs = schemeAt(tester, find.byType(AppCard));
      final material = firstMaterialIn(tester, find.byType(AppCard));
      final side = (material.shape! as RoundedRectangleBorder).side;
      expect(side.color, AppSurfaces.multiSelectedBorder(cs));
      expect(side.width, AppTokens.multiSelectedBorderWidth);
      expect(material.shape, AppCard.shape(cs, active: true));
      expect(
        material.color,
        AppSurfaces.card(tester.element(find.text('כרטיס'))),
      );
    });

    for (final (tone, bg, on) in [
      (AppCardTone.primary, 'primaryContainer', 'onPrimaryContainer'),
      (AppCardTone.error, 'errorContainer', 'onErrorContainer'),
    ]) {
      testWidgets('tone ${tone.name}: רקע $bg, טקסט $on, מסגרת נשארת', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          AppCard(tone: tone, child: const Text('כרטיס')),
        );
        final cs = schemeAt(tester, find.byType(AppCard));
        final material = firstMaterialIn(tester, find.byType(AppCard));
        expect(
          material.color,
          tone == AppCardTone.primary ? cs.primaryContainer : cs.errorContainer,
        );
        expect(material.shape, AppCard.shape(cs));
        final text = tester.widget<RichText>(
          find
              .descendant(
                of: find.text('כרטיס'),
                matching: find.byType(RichText),
              )
              .first,
        );
        expect(
          text.text.style?.color,
          tone == AppCardTone.primary
              ? cs.onPrimaryContainer
              : cs.onErrorContainer,
        );
      });
    }

    testWidgets('tone inset: רקע surfaceContainerHigh, מסגרת נשארת', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const AppCard(tone: AppCardTone.inset, child: Text('כרטיס')),
      );
      final cs = schemeAt(tester, find.byType(AppCard));
      final material = firstMaterialIn(tester, find.byType(AppCard));
      expect(material.color, cs.surfaceContainerHigh);
      expect(material.shape, AppCard.shape(cs));
    });

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
      // על ה-Material, כדי שהריחוף והלחיצה יצוירו מעליו.
      expect(
        firstMaterialIn(tester, find.byType(AppCard)).color,
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
    testWidgets('ברירת מחדל: neutral, פינות 8, labelMedium 12, אייקון 16', (
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
      expect(decoration.color, cs.surfaceContainerHighest);
      expect(decoration.border, isNull);
      expect(decoration.borderRadius, AppTokens.borderRadiusAll);

      final text = tester.widget<Text>(find.text('ראשונים'));
      expect(text.style?.fontSize, 12);
      expect(text.style?.color, cs.onSurfaceVariant);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 16);
      expect(icon.color, cs.onSurfaceVariant);
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
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('small: labelSmall 11, אייקון 12, ריפוד 6×2', (tester) async {
      await pumpInApp(
        tester,
        const Center(
          child: MetaChip(
            label: 'דור',
            icon: FluentIcons.clock_24_regular,
            size: MetaChipSize.small,
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('דור')).style?.fontSize, 11);
      expect(tester.widget<Icon>(find.byType(Icon)).size, 12);
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
        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('ב-$brightness: צבעי הטונים; success חום ולא ירוק', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          Column(
            children: [
              for (final tone in MetaChipTone.values)
                MetaChip(label: tone.name, tone: tone),
            ],
          ),
          brightness: brightness,
        );
        final context = tester.element(find.byType(Column).first);
        final cs = Theme.of(context).colorScheme;
        final expected = {
          MetaChipTone.neutral: (
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
          ),
          MetaChipTone.primary: (cs.primaryContainer, cs.onPrimaryContainer),
          MetaChipTone.error: (cs.errorContainer, cs.onErrorContainer),
          MetaChipTone.warning: (
            AppSurfaces.warningContainer(context),
            AppSurfaces.onWarningContainer(context),
          ),
          MetaChipTone.success: (
            cs.secondaryContainer,
            cs.onSecondaryContainer,
          ),
        };
        for (final MapEntry(key: tone, value: (bg, fg)) in expected.entries) {
          final chip = find.widgetWithText(MetaChip, tone.name);
          expect(_decorationIn(tester, chip).color, bg, reason: tone.name);
          expect(
            tester.widget<Text>(find.text(tone.name)).style?.color,
            fg,
            reason: tone.name,
          );
        }
      });
    }

    testWidgets('tooltip ו-maxLines', (tester) async {
      await pumpInApp(
        tester,
        const Center(
          child: MetaChip(label: 'א ב', tooltip: 'תאריך', maxLines: 2),
        ),
      );
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'תאריך');
      expect(tester.widget<Text>(find.text('א ב')).maxLines, 2);
    });
  });

  group('AppSectionLabel', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'ב-$brightness: titleMedium 16 w700 ב-primary, כותרת לקורא מסך',
        (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await pumpInApp(
            tester,
            const Center(child: AppSectionLabel('תצוגת הטקסט')),
            brightness: brightness,
          );
          final cs = schemeAt(tester, find.byType(AppSectionLabel));
          final style = tester.widget<Text>(find.text('תצוגת הטקסט')).style!;
          expect(style.fontSize, 16);
          expect(style.fontWeight, FontWeight.w700);
          expect(style.color, cs.primary);
          expect(
            tester.getSemantics(find.text('תצוגת הטקסט')),
            matchesSemantics(label: 'תצוגת הטקסט', isHeader: true),
          );
          handle.dispose();
        },
      );
    }

    testWidgets('SettingsCard: הכותרת היא AppSectionLabel', (tester) async {
      await pumpInApp(
        tester,
        const SingleChildScrollView(
          child: SettingsCard(title: 'כללי', children: [Text('שורה')]),
        ),
      );
      expect(find.widgetWithText(AppSectionLabel, 'כללי'), findsOneWidget);
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

    testWidgets('message: ספינר ממורכז והודעה ב-bodyMedium onSurfaceVariant', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const LoadingIndicator(message: 'טוען מפרשים...'),
      );
      final cs = schemeAt(tester, find.byType(LoadingIndicator));
      final text = tester.widget<Text>(find.text('טוען מפרשים...'));
      expect(text.style?.fontSize, 14);
      expect(text.style?.color, cs.onSurfaceVariant);
      expect(
        tester.getCenter(find.byType(CircularProgressIndicator)).dx,
        moreOrLessEquals(
          tester.getCenter(find.text('טוען מפרשים...')).dx,
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('inline: 16 על 16, עובי 2, בצבע שהועבר', (tester) async {
      await pumpInApp(
        tester,
        const Center(child: LoadingIndicator.inline(color: Colors.red)),
      );
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(16, 16),
      );
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.strokeWidth, 2);
      expect(
        (indicator.valueColor! as AlwaysStoppedAnimation<Color>).value,
        Colors.red,
      );
    });
  });

  group('SkeletonLines', () {
    testWidgets('רוחב לפי המקום שקיבלו ולא לפי החלון, מיושר לתחילת השורה', (
      tester,
    ) async {
      await pumpInApp(
        tester,
        const Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: 300,
            child: SkeletonLines(widths: [1, 0.5], lineHeight: 10, spacing: 4),
          ),
        ),
      );
      final lines = find.descendant(
        of: find.byType(SkeletonLines),
        matching: find.byType(Container),
      );
      expect(tester.getSize(lines.at(0)), const Size(300, 10));
      expect(tester.getSize(lines.at(1)), const Size(150, 10));
      // RTL: תחילת השורה בימין.
      expect(
        tester.getTopRight(lines.at(1)).dx,
        tester.getTopRight(lines.at(0)).dx,
      );
      expect(
        tester.getTopLeft(lines.at(1)).dy -
            tester.getBottomLeft(lines.at(0)).dy,
        4,
      );
    });
  });

  group('AppInfoBanner', () {
    for (final brightness in Brightness.values) {
      testWidgets('ב-$brightness: צבעי הטונים; success חום ולא ירוק', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          Column(
            children: [
              for (final tone in AppInfoBannerTone.values)
                AppInfoBanner(tone: tone, message: tone.name),
            ],
          ),
          brightness: brightness,
        );
        final context = tester.element(find.byType(Column).first);
        final cs = Theme.of(context).colorScheme;
        final expected = {
          AppInfoBannerTone.info: (cs.surfaceContainerHighest, cs.onSurface),
          AppInfoBannerTone.warning: (
            AppSurfaces.warningContainer(context),
            AppSurfaces.onWarningContainer(context),
          ),
          AppInfoBannerTone.error: (cs.errorContainer, cs.onErrorContainer),
          AppInfoBannerTone.success: (
            cs.secondaryContainer,
            cs.onSecondaryContainer,
          ),
        };
        for (final MapEntry(key: tone, value: (bg, fg)) in expected.entries) {
          final banner = find.widgetWithText(AppInfoBanner, tone.name);
          final decoration = _decorationIn(tester, banner);
          expect(decoration.color, bg, reason: tone.name);
          expect(decoration.borderRadius, AppTokens.borderRadiusAll);
          expect(
            tester.widget<Text>(find.text(tone.name)).style?.color,
            fg,
            reason: tone.name,
          );
        }
      });
    }

    testWidgets('כותרת titleSmall מעל ההודעה, אייקון 18', (tester) async {
      await pumpInApp(
        tester,
        const AppInfoBanner(
          tone: AppInfoBannerTone.warning,
          title: 'כותרת',
          message: 'הודעה',
        ),
      );
      expect(tester.widget<Text>(find.text('כותרת')).style?.fontSize, 14);
      expect(
        tester.getBottomLeft(find.text('כותרת')).dy,
        lessThan(tester.getTopLeft(find.text('הודעה')).dy),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).size, 18);
    });
  });

  group('OtzariaEmptyState.large', () {
    testWidgets(
      'אייקון 64, headlineSmall, bodyLarge, פעולות ברוחב מלא עד 420',
      (
        tester,
      ) async {
        await pumpInApp(
          tester,
          OtzariaEmptyState.large(
            icon: FluentIcons.library_24_regular,
            title: 'לא נמצאה ספריית ספרים',
            message: 'הסבר',
            actions: [
              ActionButton.recommended(text: 'בחר', onPressed: () {}),
              ActionButton.neutral(text: 'הגדרות', onPressed: () {}),
            ],
          ),
        );
        expect(tester.widget<Icon>(find.byType(Icon).first).size, 64);
        final title = tester.widget<Text>(find.text('לא נמצאה ספריית ספרים'));
        expect(title.style?.fontSize, 22);
        expect(title.style?.fontWeight, FontWeight.w600);
        expect(tester.widget<Text>(find.text('הסבר')).style?.fontSize, 16);
        final first = tester.getRect(find.byType(ActionButton).first);
        final second = tester.getRect(find.byType(ActionButton).last);
        expect(first.width, 420);
        expect(second.width, 420);
        expect(second.top - first.bottom, AppTokens.spaceSM);
      },
    );
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

  group('AppIconButton', () {
    for (final size in AppIconButtonSize.values) {
      testWidgets('${size.name}: אייקון ${size.iconSize}, ריבוע +16, עיגול', (
        tester,
      ) async {
        await pumpInApp(
          tester,
          Center(
            child: AppIconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              tooltip: 'סגור',
              size: size,
              onPressed: () {},
            ),
          ),
        );
        final side = size.iconSize + 16;
        expect(_iconButtonBox(tester), Size(side, side));
        expect(tester.getSize(find.byType(Icon)).width, size.iconSize);
        expect(
          firstMaterialIn(tester, find.byType(IconButton)).shape,
          const CircleBorder(),
        );
        expect(find.byTooltip('סגור'), findsOneWidget);
      });
    }

    testWidgets('צפיפות קומפקטית: ריבוע +12', (tester) async {
      await pumpInApp(
        tester,
        Theme(
          data: appTheme(
            Brightness.light,
          ).copyWith(extensions: const [AppDensity.compact]),
          child: Center(
            child: AppIconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              tooltip: 'סגור',
              size: AppIconButtonSize.small,
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(_iconButtonBox(tester), const Size(28, 28));
    });

    testWidgets('נבחר: primary; מושבת כשאין onPressed', (tester) async {
      await pumpInApp(
        tester,
        const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: Icon(FluentIcons.pin_24_regular),
                tooltip: 'נעץ',
                isSelected: true,
                onPressed: _noop,
              ),
              AppIconButton(
                icon: Icon(FluentIcons.delete_24_regular),
                tooltip: 'מחק',
                onPressed: null,
              ),
            ],
          ),
        ),
      );
      final cs = schemeAt(tester, find.byType(Row));
      final pin = tester.widget<RichText>(
        find
            .descendant(
              of: find.byTooltip('נעץ'),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(pin.text.style?.color, cs.primary);
      final delete = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('מחק'),
          matching: find.byType(IconButton),
        ),
      );
      expect(delete.onPressed, isNull);
    });
  });

  // review-r5, q-search-22: גם בשדה החיפוש אין 22 — הכול iconMD (DD-03).
  group('OtzariaSearchField: אייקונים ב־iconMD', () {
    for (final slim in [false, true]) {
      testWidgets('אייקון החיפוש ${slim ? 'בשדה צר' : 'בשדה רחב'}', (
        tester,
      ) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpInApp(
          tester,
          Center(
            child: SizedBox(
              width: 300,
              child: OtzariaSearchField(
                controller: controller,
                hintText: 'חיפוש',
                slim: slim,
              ),
            ),
          ),
        );
        expect(
          tester.widget<Icon>(find.byIcon(OtzariaIcons.search_24_regular)).size,
          AppTokens.iconMD,
        );
      });
    }

    testWidgets('OtzariaSearchDisplayBar רחב', (tester) async {
      await pumpInApp(
        tester,
        const Center(
          child: OtzariaSearchDisplayBar(slim: false, child: Text('בראשית')),
        ),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).size, AppTokens.iconMD);
    });

    test('כפתורים בשדה טופס: אייקון ו־X ב־iconMD', () {
      expect(OtzariaSearchActionSize.form.icon, AppTokens.iconMD);
      expect(OtzariaSearchActionSize.form.clearIcon, AppTokens.iconMD);
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

void _noop() {}

/// הריבוע הנראה של כפתור האייקון, בלי אזור המגע של 48 במובייל.
Size _iconButtonBox(WidgetTester tester) => tester.getSize(
  find
      .descendant(of: find.byType(IconButton), matching: find.byType(Material))
      .first,
);
