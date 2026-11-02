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
        expect(theme.dialogTheme.barrierColor, AppColors.dialogBarrier);
        expect(theme.cardTheme.shape, AppTokens.roundedShape);
        expect(
          theme.inputDecorationTheme.border,
          const OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
        );
        for (final style in [
          theme.filledButtonTheme.style,
          theme.textButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.iconButtonTheme.style,
        ]) {
          expect(style?.shape?.resolve({}), AppTokens.roundedShape);
        }
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

    test('אין chipTheme מותאם', () {
      expect(appTheme(Brightness.light).chipTheme, const ChipThemeData());
    });

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

    testWidgets('כהה: רקע עיון 242424, לוח שחור, כרטיס surfaceContainer', (
      tester,
    ) async {
      await pumpBoth(tester);
      final context = contexts[Brightness.dark]!;
      final cs = Theme.of(context).colorScheme;
      expect(AppSurfaces.readerBackground(context), const Color(0xFF242424));
      expect(AppSurfaces.panelBackground(context), Colors.black);
      expect(AppSurfaces.card(context), cs.surfaceContainer);
      expect(AppSurfaces.topBarBackground(context), cs.surfaceContainerHigh);
    });

    testWidgets('שכבות שקופות: בחירה, כפתור סרגל ופריט נבחר', (tester) async {
      await pumpBoth(tester);
      for (final context in contexts.values) {
        final cs = Theme.of(context).colorScheme;
        expect(
          AppSurfaces.cardSelectionOverlay(context),
          cs.secondaryContainer.withValues(alpha: 0.3),
        );
        expect(
          AppSurfaces.barButtonSelected(cs),
          cs.onSurface.withValues(alpha: 0.12),
        );
        expect(
          AppSurfaces.selectedItem(cs),
          cs.primaryContainer.withValues(alpha: 0.3),
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
