import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';

import 'contract_harness.dart';

void main() {
  group('AppThemeData — טיפוגרפיה', () {
    for (final brightness in Brightness.values) {
      testWidgets('ב-$brightness: סולם DD-02, גוף 14', (
        tester,
      ) async {
        late TextTheme text;
        await tester.pumpWidget(
          Theme(
            data: appTheme(brightness),
            child: Builder(
              builder: (context) {
                text = Theme.of(context).textTheme;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(text.headlineSmall?.fontSize, 22);
        expect(text.headlineSmall?.fontWeight, FontWeight.w600);
        expect(text.titleLarge?.fontSize, 18);
        expect(text.titleLarge?.fontWeight, FontWeight.w600);
        expect(text.titleMedium?.fontSize, 16);
        expect(text.titleMedium?.fontWeight, FontWeight.w700);
        expect(text.titleSmall?.fontSize, 14);
        expect(text.titleSmall?.fontWeight, FontWeight.w600);
        expect(text.bodyLarge?.fontSize, 16);
        expect(text.bodyMedium?.fontSize, 14);
        expect(text.bodySmall?.fontSize, 12);
        expect(text.labelLarge?.fontSize, 14);
        expect(text.labelMedium?.fontSize, 12);
        expect(text.labelSmall?.fontSize, 11);
      });
    }

    test('ב-ThemeData: גדלים מהסולם, וגופן הממשק של הפלטפורמה', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final theme = appTheme(Brightness.light);
      final text = theme.textTheme;
      expect(text.bodyMedium?.fontSize, AppTokens.fontMD);
      expect(text.titleLarge?.fontSize, AppTokens.fontXL);
      expect(text.displayLarge?.fontSize, isNull);
      expect(theme.dialogTheme.titleTextStyle?.fontSize, AppTokens.fontXL);
      expect(theme.dialogTheme.titleTextStyle?.fontWeight, FontWeight.w600);
      expect(AppThemeData.uiFontFamily, 'Segoe UI');
      for (final style in [
        text.bodyMedium,
        text.titleLarge,
        theme.dialogTheme.titleTextStyle,
        theme.popupMenuTheme.textStyle,
        theme.dropdownMenuTheme.textStyle,
        theme.menuButtonTheme.style?.textStyle?.resolve({}),
      ]) {
        expect(style?.fontFamily, 'Segoe UI');
        expect(style?.fontFamilyFallback, AppThemeData.uiFontFamilyFallback);
      }
    });

    test('סולם הגופן ב-AppTokens', () {
      expect(
        [
          AppTokens.fontXS,
          AppTokens.fontSM,
          AppTokens.fontMD,
          AppTokens.fontLG,
          AppTokens.fontXL,
          AppTokens.font2XL,
        ],
        [11, 12, 14, 16, 18, 22],
      );
      expect(AppTextStyles.settingTitle.fontSize, 16);
      expect(AppTextStyles.settingSubtitle.fontSize, 13);
    });
  });

  group('AppThemeData — צבעים וצורות', () {
    for (final brightness in Brightness.values) {
      test('ב-$brightness: דיאלוג, כרטיס, שדה וכפתורים ברדיוס 8', () {
        final theme = appTheme(brightness);
        final cs = theme.colorScheme;
        expect(theme.dialogTheme.backgroundColor, cs.surfaceContainerHigh);
        expect(theme.dialogTheme.shape, AppTokens.roundedShape);
        expect(theme.dialogTheme.barrierColor, AppSurfaces.scrim(cs));
        expect(
          theme.cardTheme.shape,
          RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusAll,
            side: BorderSide(color: cs.outlineVariant),
          ),
        );
        expect(theme.cardTheme.elevation, 0);
        expect(
          theme.inputDecorationTheme.border,
          const OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
        );
        for (final style in [
          theme.filledButtonTheme.style,
          theme.textButtonTheme.style,
          theme.outlinedButtonTheme.style,
        ]) {
          expect(style?.shape?.resolve({}), AppTokens.roundedShape);
        }
        // כפתור אייקון בלבד עגול (DD-04, q9 שאלה 3).
        expect(
          theme.iconButtonTheme.style?.shape?.resolve({}),
          const CircleBorder(),
        );
      });

      test('ב-$brightness: תפריטים, בועות מידע ולשוניות', () {
        final theme = appTheme(brightness);
        final cs = theme.colorScheme;
        expect(theme.popupMenuTheme.color, cs.surfaceContainerHigh);
        expect(
          theme.menuTheme.style?.backgroundColor?.resolve({}),
          cs.surfaceContainerHigh,
        );
        expect(theme.popupMenuTheme.shape, AppTokens.roundedShape);
        expect(theme.popupMenuTheme.elevation, AppTokens.elevation2);
        final tooltip = theme.tooltipTheme.decoration! as BoxDecoration;
        expect(tooltip.color, cs.surfaceContainerHigh);
        expect(tooltip.borderRadius, AppTokens.borderRadiusAll);
        final indicator = theme.tabBarTheme.indicator! as BoxDecoration;
        expect(indicator.color, cs.secondaryContainer);
        expect(theme.tabBarTheme.labelStyle?.fontSize, AppTokens.fontMD);
      });
    }

    test('Theme.primaryColor: primary בבהיר, surface בכהה', () {
      final light = appTheme(Brightness.light);
      final dark = appTheme(Brightness.dark);
      expect(light.primaryColor, light.colorScheme.primary);
      expect(dark.primaryColor, dark.colorScheme.surface);
    });

    for (final brightness in Brightness.values) {
      test('chipTheme ב-$brightness: פינות 8, תווית labelMedium 12', () {
        final theme = appTheme(brightness);
        final cs = theme.colorScheme;
        final chip = theme.chipTheme;
        expect(chip.shape, AppTokens.roundedShape);
        expect(chip.labelStyle?.fontSize, AppTokens.fontSM);
        final color = chip.labelStyle!.color!;
        expect(
          WidgetStateProperty.resolveAs<Color>(color, const {}),
          cs.onSurfaceVariant,
        );
        expect(
          WidgetStateProperty.resolveAs<Color>(color, const {
            WidgetState.disabled,
          }),
          cs.onSurface,
        );
        // כמו ברירת המחדל של M3 ל-FilterChip/ChoiceChip.
        expect(
          WidgetStateProperty.resolveAs<Color>(color, const {
            WidgetState.selected,
          }),
          cs.onSecondaryContainer,
        );
        expect(
          WidgetStateProperty.resolveAs<Color>(color, const {
            WidgetState.selected,
            WidgetState.disabled,
          }),
          cs.onSurface,
        );
      });

      testWidgets("צ'יפ נבחר ב-$brightness: תווית onSecondaryContainer", (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: Scaffold(
              body: Wrap(
                children: [
                  FilterChip(
                    label: const Text('נבחר'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  ChoiceChip(
                    label: const Text('בחירה'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('רגיל'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        final cs = appTheme(brightness).colorScheme;
        Color? labelColor(String text) =>
            DefaultTextStyle.of(tester.element(find.text(text))).style.color;
        expect(labelColor('נבחר'), cs.onSecondaryContainer);
        expect(labelColor('בחירה'), cs.onSecondaryContainer);
        expect(labelColor('רגיל'), cs.onSurfaceVariant);
      });
    }

    test('הטוקנים: רדיוס 8 ומרווחים 4/8/16/24/32', () {
      expect(AppTokens.radius, 8);
      expect(
        [
          AppTokens.spaceXS,
          AppTokens.spaceSM,
          AppTokens.spaceMD,
          AppTokens.spaceLG,
          AppTokens.spaceXL,
        ],
        [4, 8, 16, 24, 32],
      );
    });
  });

  group('AppSurfaces', () {
    late Map<Brightness, BuildContext> contexts;

    Future<void> pumpBoth(WidgetTester tester) async {
      contexts = {};
      await tester.pumpWidget(
        Column(
          children: [
            for (final brightness in Brightness.values)
              Theme(
                data: appTheme(brightness),
                child: Builder(
                  builder: (context) {
                    contexts[brightness] = context;
                    return const SizedBox();
                  },
                ),
              ),
          ],
        ),
      );
    }

    testWidgets('בהיר: רקע עיון surface, לוח מעורב, כרטיס surface', (
      tester,
    ) async {
      await pumpBoth(tester);
      final context = contexts[Brightness.light]!;
      final cs = Theme.of(context).colorScheme;
      expect(AppSurfaces.readerBackground(context), cs.surface);
      expect(
        AppSurfaces.panelBackground(context),
        Color.alphaBlend(
          cs.surfaceContainerHighest.withValues(alpha: 0.475),
          cs.surface,
        ),
      );
      expect(AppSurfaces.card(context), cs.surface);
      expect(AppSurfaces.topBarBackground(context), cs.surfaceContainerHigh);
      expect(AppSurfaces.navPanelBackground(context), cs.surfaceContainerHigh);
    });

    testWidgets('כהה: רקע עיון 242424, לוח surfaceContainerLow', (
      tester,
    ) async {
      await pumpBoth(tester);
      final context = contexts[Brightness.dark]!;
      final cs = Theme.of(context).colorScheme;
      expect(AppSurfaces.readerBackground(context), const Color(0xFF242424));
      expect(AppSurfaces.panelBackground(context), cs.surfaceContainerLow);
      expect(AppSurfaces.cardRowDivider(context), cs.surfaceContainerLow);
      expect(AppSurfaces.card(context), cs.surfaceContainer);
      expect(AppSurfaces.topBarBackground(context), cs.surfaceContainerHigh);
    });

    testWidgets('מצבי שורה (DD-06) וכפתור סרגל נבחר', (tester) async {
      await pumpBoth(tester);
      for (final context in contexts.values) {
        final cs = Theme.of(context).colorScheme;
        expect(AppSurfaces.selectedRow(cs), cs.secondaryContainer);
        expect(AppSurfaces.onSelectedRow(cs), cs.onSecondaryContainer);
        expect(AppSurfaces.focusedRow(cs), cs.primary.withValues(alpha: 0.08));
        final ring = AppSurfaces.focusRingDecoration(cs);
        expect(ring.border, Border.all(color: cs.primary, width: 2));
        expect(ring.borderRadius, AppTokens.borderRadiusAll);
        expect(AppSurfaces.hoverRow(cs), cs.onSurface.withValues(alpha: 0.08));
        expect(AppSurfaces.multiSelected(cs), cs.primaryContainer);
        expect(AppSurfaces.multiSelectedBorder(cs), cs.primary);
        expect(
          AppSurfaces.barButtonSelected(cs),
          cs.onSurface.withValues(alpha: 0.12),
        );
      }
    });
  });

  group('AppMenuMetrics', () {
    test('compactMenus מצופף רק את גובה הפריט והריפוד שלו', () {
      final regular = AppMenuMetrics.create(compactMenus: false);
      final compact = AppMenuMetrics.create(compactMenus: true);
      expect(regular.itemHeight, 36);
      expect(regular.itemPadding, const EdgeInsets.symmetric(horizontal: 12));
      expect(compact.itemHeight, 28);
      expect(compact.itemPadding, const EdgeInsets.symmetric(horizontal: 8));
      for (final m in [regular, compact]) {
        expect(m.menuPadding, const EdgeInsets.symmetric(vertical: 8));
        expect(m.visualDensity, VisualDensity.standard);
        expect(m.dividerHeight, 8);
        expect(m.fontSize, 14);
        expect(m.iconSize, 18);
        expect(m.menuMinWidth, 150);
        expect(m.itemFontWeight, FontWeight.w400);
      }
      expect(compact.compactMenus, isTrue);
      expect(regular.compactMenus, isFalse);
    });

    test('בדסקטופ התמה מעבירה את compactMenuMode להרחבה', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.defaultLight,
        Brightness.light,
      );
      final compact = AppThemeData.light(cs, compactMenuMode: true);
      final regular = AppThemeData.light(cs, compactMenuMode: false);
      expect(compact.extension<AppMenuMetrics>()?.compactMenus, isTrue);
      expect(regular.extension<AppMenuMetrics>()?.compactMenus, isFalse);
      expect(compact.extension<AppMenuMetrics>()?.itemHeight, 28);
      expect(regular.extension<AppMenuMetrics>()?.itemHeight, 36);
      expect(
        compact.menuButtonTheme.style?.minimumSize?.resolve({}),
        const Size(0, 28),
      );
      expect(compact.popupMenuTheme.textStyle?.fontSize, 14);
    });

    test('במובייל compactMenuMode מתעלם', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.defaultLight,
        Brightness.light,
      );
      final theme = AppThemeData.light(cs, compactMenuMode: true);
      expect(theme.extension<AppMenuMetrics>()?.compactMenus, isFalse);
    });
  });
}
