import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

import '../helpers/memory_settings_cache.dart';

/// ערכת "לבן" (#2850): קו דק, אפור בינוני, בין אזורי החלון, ובשאר הערכות
/// שום שינוי.
ThemeData _theme(Color seed) => AppThemeData.light(
  AppThemeData.createColorScheme(seed, Brightness.light),
  compactMenuMode: false,
  variant: AppThemeVariant.ofSeed(seed),
);

final _white = _theme(AppSeedColors.white);
final _regular = _theme(AppSeedColors.defaultLight);

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget child,
) async {
  // מפתח לכל ערכה: בלעדיו MaterialApp מנפיש את המעבר בין הערכות.
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey(theme),
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color _line(ThemeData theme) =>
    theme.extension<AppSurfaceColors>()!.regionBorder!;

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  test('הסרגלים והדיאלוגים לבנים כמעט, והקו אפור בינוני', () {
    final cs = _white.colorScheme;
    int level(Color c) => (c.r * 255).round();
    expect(level(cs.surfaceContainerHigh), greaterThanOrEqualTo(0xFC));
    expect(level(cs.surfaceContainerHigh), lessThan(0xFF));
    expect(level(cs.surfaceContainerHighest), greaterThanOrEqualTo(0xF5));
    // 9F9F9F, ולא כמעט שחור (סקירת 4.11, סבב שלישי): גלוי מול FC, אבל לא
    // בולט.
    expect(level(_line(_white)), 0x9F);
  });

  test('תפריטים ו־tooltip: מסגרת בקו האזורים ב"לבן" בלבד', () {
    ShapeBorder? menuShape(ThemeData t) =>
        t.menuTheme.style!.shape!.resolve(const <WidgetState>{});
    ShapeBorder? dropdownShape(ThemeData t) =>
        t.dropdownMenuTheme.menuStyle!.shape!.resolve(const <WidgetState>{});
    Border tooltipBorder(ThemeData t) =>
        (t.tooltipTheme.decoration! as BoxDecoration).border! as Border;

    for (final shape in [
      _white.popupMenuTheme.shape,
      menuShape(_white),
      dropdownShape(_white),
    ]) {
      final rounded = shape! as RoundedRectangleBorder;
      expect(rounded.side.color, _line(_white));
      expect(rounded.side.width, AppTokens.borderThin);
      expect(rounded.borderRadius, AppTokens.borderRadiusAll);
    }
    expect(tooltipBorder(_white).top.color, _line(_white));
    expect(tooltipBorder(_white).top.width, AppTokens.borderThin);

    for (final shape in [
      _regular.popupMenuTheme.shape,
      menuShape(_regular),
      dropdownShape(_regular),
    ]) {
      expect(shape, AppTokens.roundedShape);
    }
    expect(
      tooltipBorder(_regular).top.color,
      _regular.colorScheme.outlineVariant,
    );
  });

  test('דיאלוג: מסגרת כהה דקה ב"לבן" בלבד', () {
    final white = _white.dialogTheme.shape! as RoundedRectangleBorder;
    expect(white.side.color, _line(_white));
    expect(white.side.width, AppTokens.borderThin);
    expect(white.borderRadius, AppTokens.borderRadiusAll);
    expect(_regular.dialogTheme.shape, AppTokens.roundedShape);
  });

  testWidgets('כותרת דיאלוג: הקו התחתון בקו האזורים ב"לבן"', (tester) async {
    Future<Color> headerLine(ThemeData theme) async {
      await _pump(tester, theme, const AppDialogHeader(title: 'כותרת'));
      final box = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(AppDialogHeader),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      return (box.border! as Border).bottom.color;
    }

    expect(await headerLine(_white), _line(_white));
    expect(await headerLine(_regular), _regular.colorScheme.outlineVariant);
  });

  testWidgets('סרגל עליון: קו תחתון ב"לבן", ובלי מסגרת בשאר', (
    tester,
  ) async {
    Future<ShapeBorder?> barShape(ThemeData theme) async {
      await _pump(tester, theme, const AppTopBar(center: Text('ספר')));
      return tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AppTopBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .shape;
    }

    final white = await barShape(_white) as Border;
    expect(white.bottom.color, _line(_white));
    expect(white.top, BorderSide.none);
    expect(await barShape(_regular), isNull);
  });

  testWidgets('חלוניות: מסגרת לכולן, והפעילה בטבעת בלי לשנות פריסה', (
    tester,
  ) async {
    Future<List<BoxDecoration>> decorations(
      ThemeData theme, {
      required bool isActive,
    }) async {
      await _pump(
        tester,
        theme,
        SizedBox(
          width: 300,
          height: 200,
          child: PaneCard(
            isActive: isActive,
            isSplit: true,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(PaneCard),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .map((c) => c.decoration! as BoxDecoration)
          .toList();
    }

    Rect content() => tester.getRect(find.byType(ClipRRect));

    final active = await decorations(_white, isActive: true);
    final activeRect = content();
    expect((active.first.border! as Border).top.color, _line(_white));
    expect(
      (active.last.border! as Border).top.color,
      _white.colorScheme.primary,
    );
    final inactive = await decorations(_white, isActive: false);
    expect((inactive.first.border! as Border).top.color, _line(_white));
    expect((inactive.last.border! as Border).top.color, Colors.transparent);
    expect(content(), activeRect, reason: 'הפעילה אינה משנה את הריפוד');

    final regular = await decorations(_regular, isActive: true);
    expect(regular, hasLength(1), reason: 'בשאר הערכות אין טבעת');
    expect(
      (regular.single.border! as Border).top.color,
      AppSurfaces.paneCardBorder(_regular.colorScheme, isActive: true),
    );
  });

  testWidgets('חלונית צד צמודה: קו בקצה הפנימי ופינה ישרה ב"לבן"', (
    tester,
  ) async {
    late Rect pane;
    late Rect main;
    Future<ShapeBorder?> paneShape(ThemeData theme) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        theme,
        AdaptiveSidePane(
          isOpen: true,
          attachToTopEdge: true,
          onClose: () {},
          mainContent: const SizedBox.expand(key: ValueKey('main')),
          paneContent: const Text('תוכן עניינים'),
        ),
      );
      final material = find
          .ancestor(
            of: find.text('תוכן עניינים'),
            matching: find.byType(Material),
          )
          .first;
      pane = tester.getRect(material);
      main = tester.getRect(find.byKey(const ValueKey('main')));
      return tester.widget<Material>(material).shape;
    }

    bool hasFillet() => find
        .descendant(
          of: find.byType(AdaptiveSidePane),
          matching: find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_ConcaveCornerPainter',
          ),
        )
        .evaluate()
        .isNotEmpty;

    // הקו בצד שפונה לתוכן, ורק בו.
    final white = await paneShape(_white) as Border;
    final paneOnRight = pane.center.dx > main.center.dx;
    final inner = paneOnRight ? white.left : white.right;
    final outer = paneOnRight ? white.right : white.left;
    expect(inner.color, _line(_white));
    expect(inner.width, AppTokens.borderThin);
    expect(outer, BorderSide.none);
    expect(white.top, BorderSide.none);
    expect(hasFillet(), isFalse);

    expect(await paneShape(_regular), isNull);
    expect(hasFillet(), isTrue);
  });

  testWidgets('חלונית צד צפה (לא צמודה): מסגרת בקו האזורים ב"לבן"', (
    tester,
  ) async {
    Future<ShapeBorder?> paneShape(
      ThemeData theme, {
      required bool floatingPanel,
    }) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        theme,
        AdaptiveSidePane(
          isOpen: true,
          wrapPaneInFloatingPanel: floatingPanel,
          onClose: () {},
          mainContent: const SizedBox.expand(),
          paneContent: const Text('תצוגה מקדימה'),
        ),
      );
      return tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.text('תצוגה מקדימה'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .shape;
    }

    for (final floatingPanel in [false, true]) {
      final white =
          await paneShape(_white, floatingPanel: floatingPanel)
              as RoundedRectangleBorder;
      expect(white.side.color, _line(_white), reason: '$floatingPanel');
      expect(white.side.width, AppTokens.borderThin);
      expect(white.borderRadius, AppTokens.borderRadiusAll);
    }
    // בשאר הערכות: התצוגה המקדימה בלי מסגרת, ו־FloatingPanel ב־outlineVariant.
    expect(
      await paneShape(_regular, floatingPanel: false),
      AppTokens.roundedShape,
    );
    final regularFp =
        await paneShape(_regular, floatingPanel: true)
            as RoundedRectangleBorder;
    expect(regularFp.side.color, _regular.colorScheme.outlineVariant);
  });
}
