import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart'
    show AppMenuEntry;

import '../helpers/memory_settings_cache.dart';

/// ערכת "לבן" בבהיר (סקירה רביעית 4.11, q-white-selected): מילוי הבחירה
/// בהיר (E0 במקום D4), והנבחר מסומן גם בקו דק בצבע קו האזורים (9F). בשאר
/// הערכות שום שינוי.
ThemeData _theme(Color seed, Brightness brightness) => AppThemeData.light(
  AppThemeData.createColorScheme(seed, brightness),
  compactMenuMode: false,
  variant: AppThemeVariant.ofSeed(seed),
);

final _white = _theme(AppSeedColors.white, Brightness.light);

/// כל ערכה שאינה "לבן" בבהיר, עם הזרע שלה.
final _others = <String, (Color, Brightness)>{
  'רגיל בהיר': (AppSeedColors.defaultLight, Brightness.light),
  'רגיל כהה': (AppSeedColors.defaultDark, Brightness.dark),
  'לבן כהה': (AppSeedColors.white, Brightness.dark),
  'פרגמנט': (AppSeedColors.parchment, Brightness.light),
};

Color? _selectedBorder(ThemeData t) =>
    t.extension<AppSurfaceColors>()!.selectedBorder;

int _level(Color c) => (c.r * 255).round();

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey(theme),
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _segmentFrame() => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_SelectedSegmentFrame',
);

Widget _segmented() => SizedBox(
  width: 360,
  child: AppSegmentedControl<int>(
    options: const [
      SegmentOption(value: 0, label: 'עברי'),
      SegmentOption(value: 1, label: 'משולב'),
      SegmentOption(value: 2, label: 'לועזי'),
    ],
    currentValue: 1,
    onChanged: (_) {},
    expandToFillWidth: true,
  ),
);

Widget _card() => SizedBox(
  width: 200,
  height: 80,
  child: AppCard(selected: true, onTap: () {}, child: const Text('תנ"ך')),
);

RoundedRectangleBorder _cardShape(WidgetTester tester) {
  final material = tester.widget<Material>(
    find.ancestor(of: find.text('תנ"ך'), matching: find.byType(Material)).first,
  );
  return material.shape! as RoundedRectangleBorder;
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  test('"לבן" בבהיר: מילוי הבחירה E0, והקו 9F כמו קו האזורים', () {
    final cs = _white.colorScheme;
    expect(cs.secondaryContainer, const Color(0xFFE0E0E0));
    expect(AppSurfaces.selectedRow(cs), const Color(0xFFE0E0E0));
    // בהיר מ־D4 שהיה, וכהה מהריחוף (onSurface ‏8% מעל לבן, ED).
    final hover = Color.alphaBlend(AppSurfaces.hoverRow(cs), cs.surface);
    expect(
      _level(hover) - _level(cs.secondaryContainer),
      greaterThanOrEqualTo(12),
    );
    final line = _selectedBorder(_white)!;
    expect(line, _white.extension<AppSurfaceColors>()!.regionBorder);
    expect(_level(line), 0x9F);
    expect(line.a, 1.0);
    // בורר מקטעים: המסגרת והמפרידים בהירים מהקו של המקטע הנבחר.
    final side = _white.segmentedButtonTheme.style!.side!.resolve(
      const <WidgetState>{},
    )!;
    expect(side.color, cs.outlineVariant);
    expect(_level(cs.outlineVariant), greaterThan(_level(line)));
    expect(
      _white.segmentedButtonTheme.style!.side!.resolve(const {
        WidgetState.disabled,
      }),
      isNull,
    );
  });

  test('שאר הערכות: צבע הבחירה, הקו והבורר כמו קודם', () {
    for (final MapEntry(key: name, value: (seed, brightness))
        in _others.entries) {
      final t = _theme(seed, brightness);
      final monochrome = HSLColor.fromColor(seed).saturation < 0.1;
      final raw = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
        dynamicSchemeVariant: monochrome
            ? DynamicSchemeVariant.monochrome
            : DynamicSchemeVariant.tonalSpot,
      );
      expect(
        t.colorScheme.secondaryContainer,
        raw.secondaryContainer,
        reason: name,
      );
      expect(_selectedBorder(t), isNull, reason: name);
      expect(
        t.segmentedButtonTheme,
        const SegmentedButtonThemeData(),
        reason: name,
      );
    }
  });

  testWidgets('"לבן" בבהיר: כרטיס נבחר ומקטע נבחר במסגרת הבחירה', (
    tester,
  ) async {
    await _pump(tester, _white, _card());
    final shape = _cardShape(tester);
    expect(shape.side.color, _selectedBorder(_white));
    expect(shape.side.width, AppTokens.borderThin);

    await _pump(tester, _white, _segmented());
    expect(_segmentFrame(), findsOneWidget);
  });

  testWidgets(
    '"לבן" בבהיר: קו המקטע על מסגרת הבורר גם כשאזור המגע מרופד (טלפון)',
    (tester) async {
      // padded (טלפון וטאבלט): המקטע גבוה ב-8 מהמסגרת של הבורר, והקו נצמד
      // למסגרת ולא לקצה אזור המגע. shrinkWrap (מחשב): אין ריווח.
      for (final target in MaterialTapTargetSize.values) {
        await _pump(
          tester,
          _white.copyWith(materialTapTargetSize: target),
          SizedBox(
            width: 360,
            child: AppSegmentedControl<int>(
              options: const [
                SegmentOption(value: 0, label: 'בהיר'),
                SegmentOption(value: 1, label: 'מערכת'),
              ],
              currentValue: 0,
              onChanged: (_) {},
              height: 40,
              expandToFillWidth: true,
            ),
          ),
        );
        final inset =
            (tester.widget(_segmentFrame()) as dynamic).verticalInset as double;
        final segment = tester.getSize(
          find
              .ancestor(
                of: find.text('בהיר'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(segment.height - 2 * inset, 40, reason: '$target');
        expect(
          inset,
          target == MaterialTapTargetSize.padded ? 4 : 0,
          reason: '$target',
        );
      }
    },
  );

  testWidgets('שאר הערכות: כרטיס נבחר במסגרת outlineVariant ובלי קו למקטע', (
    tester,
  ) async {
    for (final MapEntry(key: name, value: (seed, brightness))
        in _others.entries) {
      final t = _theme(seed, brightness);
      await _pump(tester, t, _card());
      expect(
        _cardShape(tester).side.color,
        t.colorScheme.outlineVariant,
        reason: name,
      );
      await _pump(tester, t, _segmented());
      expect(_segmentFrame(), findsNothing, reason: name);
    }
  });

  testWidgets('תפריט נפתח: הפריט הנבחר בקו למעלה ולמטה, רק ב"לבן" בבהיר', (
    tester,
  ) async {
    Future<Border?> selectedItemBorder(ThemeData t) async {
      final key = GlobalKey();
      await _pump(
        tester,
        t,
        SizedBox(
          width: 260,
          child: AppDropdownField<int>(
            key: key,
            value: 2,
            entries: const [
              AppMenuEntry(value: 1, label: 'תנ"ך'),
              AppMenuEntry(value: 2, label: 'משנה'),
              AppMenuEntry(value: 3, label: 'הלכה'),
            ],
            onSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      final item = find.widgetWithText(PopupMenuItem<int>, 'משנה');
      final boxes = find.ancestor(
        of: item,
        matching: find.byType(DecoratedBox),
      );
      final colored = find.ancestor(
        of: item,
        matching: find.byType(ColoredBox),
      );
      Border? border;
      for (final e in boxes.evaluate()) {
        final d = (e.widget as DecoratedBox).decoration;
        if (d is BoxDecoration && d.color == t.highlightColor) {
          border = d.border as Border?;
        }
      }
      if (border == null) {
        // בלי קו: הרקע של הנבחר בלבד, כמו שהיה.
        expect(
          colored.evaluate().any(
            (e) => (e.widget as ColoredBox).color == t.highlightColor,
          ),
          isTrue,
        );
      }
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      return border;
    }

    final border = (await selectedItemBorder(_white))!;
    expect(border.top.color, _selectedBorder(_white));
    expect(border.bottom.color, _selectedBorder(_white));
    expect(border.top.width, AppTokens.borderThin);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);

    for (final MapEntry(key: name, value: (seed, brightness))
        in _others.entries) {
      expect(
        await selectedItemBorder(_theme(seed, brightness)),
        isNull,
        reason: name,
      );
    }
  });
}
