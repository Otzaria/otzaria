import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _previewKey = ValueKey('preview');
const _readerKey = ValueKey('reader');
const _style = TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM');

Widget _app(Widget child, {ThemeData? theme, double scale = 1}) => MaterialApp(
  theme:
      theme ??
      AppThemeData.light(
        compactMenuMode: false,
        AppThemeData.createColorScheme(Colors.deepPurple, Brightness.light),
      ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

RenderRaisedMarkerOverlay _overlay(WidgetTester tester, Key key) =>
    tester.renderObject<RenderRaisedMarkerOverlay>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(RaisedMarkerOverlay),
      ),
    );

List<TextStyle> _styles(InlineSpan span, TextStyle inherited, String text) {
  if (span is! TextSpan) return const [];
  final style = inherited.merge(span.style);
  return [
    if ((span.text ?? '').contains(text)) style,
    for (final child in span.children ?? const <InlineSpan>[])
      ..._styles(child, style, text),
  ];
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    for (final family in ['Rubik', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
    }
    final books = FontLoader('FrankRuhlCLM');
    for (final weight in ['Medium', 'Bold']) {
      books.addFont(rootBundle.load('fonts/FrankRuehlCLM-$weight.ttf'));
    }
    await books.load();
  });

  for (final raw in [
    'ראשון<sup>1</sup><sup>2</sup> סוף',
    '<big>ראשון<sup>1</sup><sup>2</sup> סוף</big>',
    '<b>ראשון<sup style="color: gray">1</sup><sup style="color: gray">2</sup> סוף</b>',
  ]) {
    testWidgets('תצוגת המקור שומרת סדר סימונים כמו הקורא: $raw', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              SmartTextWidget(
                key: _readerKey,
                text: raw,
                settings: const RenderSettings(
                  fontSize: 20,
                  fontFamily: 'FrankRuhlCLM',
                  formatParentheses: false,
                ),
              ),
              CorrectionHtml(
                key: _previewKey,
                html: markTargetInHtml(raw, 0, raw.length),
                style: _style,
                direction: TextDirection.rtl,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reader = _overlay(tester, _readerKey).debugPlacements();
      final overlay = _overlay(tester, _previewKey);
      final preview = overlay.debugPlacements();
      expect(reader, hasLength(2));
      expect(preview, hasLength(2));
      expect(
        reader[0].anchorRect.center.dx,
        greaterThan(reader[1].anchorRect.center.dx),
      );
      expect(
        preview[0].anchorRect.center.dx,
        greaterThan(preview[1].anchorRect.center.dx),
      );
      final style = _styles(
        overlay.debugPaintedSpan(preview.first),
        const TextStyle(),
        '1',
      ).single;
      expect(style.fontFamily, 'FrankRuhlCLM');
      expect(style.fontWeight, FontWeight.bold);
      expect(
        (style.background?.color ?? style.backgroundColor)?.toARGB32(),
        Theme.of(
          tester.element(find.byKey(_previewKey)),
        ).colorScheme.secondaryContainer.toARGB32(),
      );
      expect(
        preview.first.paintRect.height,
        closeTo(reader.first.paintRect.height, 0.1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('מחיקה ותוספת בתוך sup שומרות צבע, רקע וקו בציור המורם', (
    tester,
  ) async {
    final html = correctionDiffHtml(
      before: '1',
      after: '2',
      contextBefore: 'ראשון<sup>',
      contextAfter: '</sup> סוף',
    );
    expect(html, isNotNull);
    await tester.pumpWidget(
      _app(
        CorrectionHtml(
          key: _previewKey,
          html: html!,
          style: _style,
          direction: TextDirection.rtl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final overlay = _overlay(tester, _previewKey);
    final painted = overlay.debugPaintedSpan(overlay.debugPlacements().single);
    final removed = _styles(painted, const TextStyle(), '1').single;
    final added = _styles(painted, const TextStyle(), '2').single;
    final colors = Theme.of(
      tester.element(find.byKey(_previewKey)),
    ).colorScheme;
    expect(removed.color?.toARGB32(), colors.onErrorContainer.toARGB32());
    expect(
      (removed.background?.color ?? removed.backgroundColor)?.toARGB32(),
      colors.errorContainer.toARGB32(),
    );
    expect(removed.decoration, TextDecoration.lineThrough);
    expect(added.color?.toARGB32(), colors.onPrimaryContainer.toARGB32());
    expect(
      (added.background?.color ?? added.backgroundColor)?.toARGB32(),
      colors.primaryContainer.toARGB32(),
    );
    expect(added.fontWeight, FontWeight.bold);
  });

  testWidgets('קישורים בתצוגת התיקון נשארים לקריאה בלבד', (tester) async {
    await tester.pumpWidget(
      _app(
        const CorrectionHtml(
          html: '<a href="https://example.com">קישור</a>',
          style: _style,
          direction: TextDirection.rtl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(await html.onTapUrl!('https://example.com'), isTrue);
  });

  testWidgets('תצוגת דיווח שמור נשארת קוד מקור כברירת מחדל', (tester) async {
    await tester.pumpWidget(
      _app(
        const TextCorrectionDiffView(
          before: '<sup>1</sup>',
          after: '<sup>2</sup>',
          style: _style,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CorrectionHtml), findsNothing);
    expect(find.byType(HtmlWidget), findsNothing);
    expect(find.textContaining('<sup>', findRichText: true), findsOneWidget);
  });

  for (final mode in ['light', 'dark', 'white']) {
    for (final width in [360.0, 1200.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('תצוגת העורך ב־RTL: $mode רוחב$width טקסט$scale', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final colors = AppThemeData.createColorScheme(
            mode == 'white' ? AppSeedColors.white : AppSeedColors.defaultLight,
            mode == 'dark' ? Brightness.dark : Brightness.light,
          );
          final theme = mode == 'dark'
              ? AppThemeData.dark(colors, compactMenuMode: false)
              : AppThemeData.light(
                  colors,
                  compactMenuMode: false,
                  variant: mode == 'white'
                      ? AppThemeVariant.white
                      : AppThemeVariant.standard,
                );
          const source = '<big>ראשון<sup>1</sup><sup>2</sup> סוף</big>';
          final original = buildCorrectionTemplate(source, 'ראשון');
          await tester.pumpWidget(
            _app(
              Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: TextCorrectionEditor(
                    original: original,
                    fontSize: 20,
                    onChanged: (_) {},
                  ),
                ),
              ),
              theme: theme,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CorrectionHtml), findsOneWidget);
          expect(find.byType(RaisedMarkerOverlay), findsOneWidget);
          expect(find.text('כמו בספר'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('קוד מקור'));
          await tester.pumpAndSettle();
          expect(find.byType(CorrectionHtml), findsNothing);
          expect(
            find.textContaining('<sup>', findRichText: true),
            findsOneWidget,
          );
          expect(original.originalLine, source);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
