import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

// חוזה התצוגה של אותיות העוגן מקצה לקצה: הזרקה ← processText ← מסלול רינדור ← שכבת ההרמה.
// כל בדיקה נושאת את הקומיט שתיקן את השבר שהיא נועלת.

const _font = 'FrankRuhlCLM';
const _settings = RenderSettings(fontSize: 20, fontFamily: _font);
const _base = TextStyle(fontSize: 20, fontFamily: _font);
const _linkColor = Color(0xFF1565C0);
const _linkStyle = TextStyle(
  color: _linkColor,
  decoration: TextDecoration.underline,
);

Link _point(String path2, int start, {String label = 'א'}) => Link(
  heRef: '$path2 א, א',
  index1: 1,
  path2: path2,
  index2: 1,
  connectionType: 'commentary',
  anchorStart: start,
  anchorLabel: label,
);

Link _range(String path2, int start, int end) => Link(
  heRef: '$path2 א, א',
  index1: 1,
  path2: path2,
  index2: 1,
  connectionType: 'LINKER',
  anchorStart: start,
  anchorEnd: end,
);

String _inject(
  String raw,
  List<Link> links, {
  Map<String, int>? styles,
  int? lineIndex = 0,
  int? active,
}) => injectLinkAnchorMarkers(
  rawLine: raw,
  anchorLinks: links,
  styleIndexByCommentator: styles ?? anchorStyleIndexByCommentator(links),
  lineIndex: lineIndex,
  activeIndex: active,
);

Future<void> _pumpSmart(
  WidgetTester tester,
  String html, {
  ThemeData? theme,
  RenderSettings settings = _settings,
  double width = 600,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: width,
              child: SmartTextWidget(
                text: html,
                settings: settings,
                onAnchorTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpContinuous(
  WidgetTester tester,
  List<String> rawLines, {
  ThemeData? theme,
  double width = 600,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: width,
              child: ContinuousReadingParagraph(
                lines: [
                  for (var i = 0; i < rawLines.length; i++)
                    ContinuousReadingParagraphLine(
                      lineIndex: i,
                      text: TextRendererService.stripHtml(rawLines[i]),
                      htmlText: TextRendererService.processText(
                        rawLines[i],
                        _settings,
                      ),
                      style: _base,
                    ),
                ],
                baseStyle: _base,
                onLineTap: (_) {},
                onTapUrl: (_) async => true,
                linkStyle: _linkStyle,
                anchorActiveBackground: const Color(0xFFFFE082),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<RaisedMarkerPlacement> _placements(WidgetTester tester) => tester
    .renderObject<RenderRaisedMarkerOverlay>(find.byType(RaisedMarkerOverlay))
    .debugPlacements();

TextStyle _continuousStyle(String raw, String needle) {
  final spans = buildInlineHtmlSpans(
    TextRendererService.processText(raw, _settings),
    _base,
    onTapUrl: (_) async => true,
    linkStyle: _linkStyle,
  );
  TextStyle? found;
  void visit(InlineSpan span, TextStyle inherited) {
    if (found != null || span is! TextSpan) return;
    final style = span.style == null ? inherited : inherited.merge(span.style);
    if (span.text?.contains(needle) ?? false) {
      found = style;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  for (final span in spans) {
    visit(span, _base);
  }
  return found!;
}

TextStyle _widgetStyle(WidgetTester tester, String needle) {
  TextStyle? found;
  void visit(InlineSpan span, TextStyle inherited) {
    if (found != null || span is! TextSpan) return;
    final style = span.style == null ? inherited : inherited.merge(span.style);
    if (span.text?.contains(needle) ?? false) {
      found = style;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(richText.text, const TextStyle());
    if (found != null) break;
  }
  return found!;
}

RenderParagraph _firstParagraph(WidgetTester tester) {
  RenderParagraph? paragraph;
  void visit(RenderObject object) {
    if (object is RenderParagraph) {
      paragraph ??= object;
      return;
    }
    object.visitChildren(visit);
  }

  visit(tester.renderObject(find.byType(RaisedMarkerOverlay)));
  return paragraph!;
}

Future<void> _loadFont(String family, String file) async {
  final bytes = File('fonts/$file').readAsBytesSync();
  await (FontLoader(
    family,
  )..addFont(Future.value(bytes.buffer.asByteData()))).load();
}

void main() {
  const line = 'בראשית ברא אלהים את השמים ואת הארץ';

  setUp(RaisedMarkers.clearCacheForTesting);

  group('אותיות העוגן — חוזה התצוגה (issue #2075)', () {
    testWidgets(
      '92444a9: שני ציונים בפסקת RTL — טקסט טהור בסדר הלוגי, בלי WidgetSpan (issue #2075)',
      (tester) async {
        await _pumpSmart(
          tester,
          _inject(line, [
            _point('מפרש ראשון', 7, label: 'א'),
            _point('מפרש שני', 17, label: 'ב'),
          ]),
        );

        for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
          rich.text.visitChildren((span) {
            expect(span, isNot(isA<PlaceholderSpan>()));
            return true;
          });
        }
        final placements = _placements(tester);
        expect(placements, hasLength(2));
        expect(placements[0].text, contains('א'));
        expect(placements[1].text, contains('ב'));
        expect(
          placements[0].anchorRect.center.dx,
          greaterThan(placements[1].anchorRect.center.dx),
        );
      },
    );

    testWidgets(
      '33dc380: ציטוט לינקר בגופן הטקסט הסובב ובלי וריאנט, בשני המסלולים (issue #2075)',
      (tester) async {
        final raw = _inject(line, [
          _range('בבלי ברכות', 11, 16),
          _range('ירושלמי שבת', 20, 25),
        ]);
        expect('class="link-anchor-range"'.allMatches(raw), hasLength(2));
        expect(raw, isNot(contains('link-anchor-range link-anchor-')));

        await _pumpSmart(tester, raw);
        final around = _widgetStyle(tester, 'בראשית');
        for (final needle in ['אלהים', 'השמים']) {
          for (final style in [
            _widgetStyle(tester, needle),
            _continuousStyle(raw, needle),
          ]) {
            expect(style.fontFamily, around.fontFamily, reason: needle);
            expect(style.fontStyle ?? FontStyle.normal, FontStyle.normal);
            expect(style.fontWeight ?? FontWeight.normal, FontWeight.normal);
          }
        }
      },
    );

    testWidgets(
      '00922dd: ציטוט לינקר בלי קו תחתון ובצבע הנושא, בשני המסלולים (issue #2075)',
      (tester) async {
        final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        );
        final raw = _inject(line, [_range('בבלי ברכות', 11, 16)]);
        await _pumpSmart(tester, raw, theme: theme);

        final html = _widgetStyle(tester, 'אלהים');
        final continuous = _continuousStyle(raw, 'אלהים');
        for (final style in [html, continuous]) {
          expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
        }
        expect(html.color, theme.colorScheme.primary);
        expect(continuous.color, _linkColor);
      },
    );

    testWidgets(
      'd2d50be: כל וריאנט מוצג זהה במסך עיון ובקריאה רציפה, בגודל 0.7 (issue #2075)',
      (tester) async {
        for (var index = 0; index < kLinkAnchorVariants.length; index++) {
          final raw = _inject(
            line,
            [_point('מפרש', 7)],
            styles: {'מפרש': index},
          );
          await _pumpSmart(tester, raw);
          final letter = wrapLinkAnchorLetter('א', index);
          final html = _widgetStyle(tester, letter);
          final continuous = _continuousStyle(raw, letter);
          final reason = 'וריאנט $index';

          expect(continuous.fontFamily, html.fontFamily, reason: reason);
          expect(
            continuous.fontWeight ?? FontWeight.normal,
            html.fontWeight ?? FontWeight.normal,
            reason: reason,
          );
          expect(
            continuous.fontStyle ?? FontStyle.normal,
            html.fontStyle ?? FontStyle.normal,
            reason: reason,
          );
          expect(
            continuous.decoration ?? TextDecoration.none,
            html.decoration ?? TextDecoration.none,
            reason: reason,
          );
          for (final style in [html, continuous]) {
            expect(
              style.fontSize,
              closeTo(20 * kLinkAnchorMarkerScale, 0.01),
              reason: reason,
            );
          }
        }
      },
    );

    testWidgets(
      '2dc70b6: בכותרת ציטוט הלינקר מדולג וציון המפרש נשאר מורם (issue #2075)',
      (tester) async {
        final raw = _inject('<h2>פרק ראשון בענין</h2>', [
          _range('בבלי ברכות', 0, 3),
          _point('מפרש', 5),
        ]);
        expect(raw, isNot(contains('link-anchor-range')));

        await _pumpSmart(tester, raw);
        expect(_placements(tester), hasLength(1));
      },
    );

    test(
      '1fbf446 + 6a5fcd7: אות הציון בחלונית זהה לאות שבגוף הטקסט, ו-♦ מוצג כ-◆ (issue #2075)',
      () {
        final markerContent = RegExp(
          r'<a class="link-anchor[^"]*"[^>]*>(.*?)</a>',
        );
        for (var i = 0; i < 40; i++) {
          final link = _point('מפרש $i', 3, label: i == 0 ? '♦' : 'יב');
          final body = markerContent.firstMatch(_inject(line, [link]))![1];
          expect(body, anchorMarkerText(link), reason: link.path2);
          expect(body, isNot(contains('♦')));
        }
      },
    );

    test(
      'c60053e: כל צורת ציון שנצבעת שקופה נקלטת לציור — אף אות לא נעלמת (issue #2075)',
      () {
        for (var index = 0; index < kLinkAnchorVariants.length; index++) {
          for (final active in [false, true]) {
            for (final lineIndex in [null, 0]) {
              final processed = TextRendererService.processText(
                _inject(
                  line,
                  [_point('מפרש', 7)],
                  styles: {'מפרש': index},
                  lineIndex: lineIndex,
                  active: active ? 0 : null,
                ),
                _settings,
              );
              final reason = 'וריאנט $index, פעיל $active, שורה $lineIndex';
              final marker = RaisedMarkers.extract(processed).single;
              expect(
                marker.text,
                wrapLinkAnchorLetter('א', index),
                reason: reason,
              );
              expect(marker.variantIndex, index, reason: reason);
              expect(marker.active, active, reason: reason);
              expect(marker.scale, kLinkAnchorMarkerScale, reason: reason);
              expect(marker.clickable && marker.useLinkColor, isTrue);
            }
          }
        }
      },
    );

    testWidgets(
      '155853f: ישות HTML ואות זהה בגוף הטקסט לפני הציון — הציור יושב על הציון עצמו (issue #2075)',
      (tester) async {
        const raw = 'ראה &quot;(א)&quot; שם ועוד';
        await _pumpSmart(
          tester,
          _inject(raw, [_point('מפרש', 15)], styles: {'מפרש': 0}),
        );

        final placement = _placements(tester).single;
        final paragraph = _firstParagraph(tester);
        final bodyStart = paragraph.text.toPlainText().indexOf('(א)');
        final bodyRect = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: bodyStart, extentOffset: bodyStart + 3),
            )
            .first
            .toRect();
        expect(placement.anchorRect.center.dx, lessThan(bodyRect.left));
      },
    );

    testWidgets(
      '008145f: הציון אינו מוקטן פעמיים, והציור בגודל הגליף גם בתוך small/big (issue #2075)',
      (tester) async {
        final cases = {
          line: kLinkAnchorMarkerScale,
          '(פסקה בתוך סוגריים)': kLinkAnchorMarkerScale * kHtmlSmallerFontScale,
          '<big>טקסט מוגדל כאן</big>':
              kLinkAnchorMarkerScale * kHtmlLargerFontScale,
        };
        for (final MapEntry(key: raw, value: scale) in cases.entries) {
          final injected = _inject(raw, [_point('מפרש', 5)]);
          final processed = TextRendererService.processText(
            injected,
            _settings,
          );
          expect(
            RegExp(r'class="link-anchor[^>]*><small').hasMatch(processed),
            isFalse,
            reason: raw,
          );
          final marker = RaisedMarkers.extract(processed).single;
          expect(marker.scale, closeTo(scale, 0.0001), reason: raw);

          await _pumpSmart(tester, injected);
          expect(
            _widgetStyle(tester, marker.text).fontSize,
            closeTo(20 * marker.scale, 0.01),
            reason: raw,
          );
        }
      },
    );

    testWidgets(
      'fc1fcae: ציון פעיל אינו משנה את רוחב המקום בשורה, בשני המסלולים (issue #2075)',
      (tester) async {
        final links = [_point('מפרש', 7)];
        Future<double> width(int? active, {required bool continuous}) async {
          final raw = _inject(line, links, active: active);
          if (continuous) {
            await _pumpContinuous(tester, [raw]);
          } else {
            await _pumpSmart(tester, raw);
          }
          return _placements(tester).single.anchorRect.width;
        }

        for (final continuous in [false, true]) {
          expect(
            await width(0, continuous: continuous),
            await width(null, continuous: continuous),
            reason: continuous ? 'קריאה רציפה' : 'מסך עיון',
          );
        }
      },
    );

    testWidgets(
      'fc1fcae: הציור מורם 0.40 מגודלו מעל קו הבסיס, באותה מידה בכל גופן (issue #2075)',
      (tester) async {
        const fonts = {
          'FrankRuhlCLM': 'FrankRuehlCLM-Medium.ttf',
          'NotoSerifHebrew': 'NotoSerifHebrew-VariableFont_wdth,wght.ttf',
          'TaameyDavidCLM': 'TaameyDavidCLM-Medium.ttf',
          'KeterYG': 'KeterYG-Medium.ttf',
        };
        for (final MapEntry(key: family, value: file) in fonts.entries) {
          await _loadFont(family, file);
          await _pumpSmart(
            tester,
            _inject(
              'שורה ראשונה<br>$line',
              [
                _point('מפרש', 20),
              ],
              styles: {'מפרש': 5},
            ),
            settings: RenderSettings(fontSize: 24, fontFamily: family),
          );
          final placement = _placements(tester).single;
          final size = 24 * kLinkAnchorMarkerScale;
          final painter = TextPainter(
            text: TextSpan(
              text: placement.text,
              style: TextStyle(fontFamily: family, fontSize: size, height: 1),
            ),
            textDirection: TextDirection.rtl,
          )..layout();
          final glyphBottom = sameLineAnchorRect(
            painter.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: placement.text.length),
            ),
          )!.bottom;
          painter.dispose();
          expect(
            placement.anchorRect.bottom -
                (placement.paintRect.top + glyphBottom),
            closeTo(kRaisedMarkerRaiseFactor * size, 0.5),
            reason: family,
          );
        }
      },
    );

    testWidgets(
      'צבעי הציור נגזרים מערכת הנושא, בבהיר ובכהה, בשני המסלולים (issue #2075)',
      (tester) async {
        for (final brightness in Brightness.values) {
          final theme = ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: brightness,
            ),
          );
          final scheme = theme.colorScheme;
          final raw = _inject(line, [_point('מפרש', 7)]);

          await _pumpSmart(tester, raw, theme: theme);
          var overlay = tester.widget<RaisedMarkerOverlay>(
            find.byType(RaisedMarkerOverlay),
          );
          expect(overlay.linkColor, scheme.primary);
          expect(overlay.activeBackground, scheme.primaryContainer);
          expect(overlay.activeForeground, scheme.onPrimaryContainer);

          await _pumpContinuous(tester, [raw], theme: theme);
          overlay = tester.widget<RaisedMarkerOverlay>(
            find.byType(RaisedMarkerOverlay),
          );
          expect(overlay.linkColor, _linkColor);
          expect(overlay.activeForeground, scheme.onPrimaryContainer);
        }
      },
    );

    testWidgets(
      'הגדלת גופן: גודל הציור וההרמה גדלים ביחס ישר (issue #2075)',
      (tester) async {
        Future<RaisedMarkerPlacement> at(double size) async {
          await _pumpSmart(
            tester,
            _inject('שורה ראשונה<br>$line', [_point('מפרש', 20)]),
            settings: RenderSettings(fontSize: size, fontFamily: _font),
            width: 1600,
          );
          return _placements(tester).single;
        }

        final small = await at(20);
        final large = await at(40);
        expect(
          large.paintRect.height / small.paintRect.height,
          closeTo(2, 0.1),
        );
        double raise(RaisedMarkerPlacement p) =>
            p.anchorRect.bottom - p.paintRect.bottom;
        expect(raise(large) / raise(small), closeTo(2, 0.15));
      },
    );

    testWidgets(
      'טעמים מחליפים את גופן השורה — הציור נמדד באותו גופן (issue #2075)',
      (tester) async {
        const raw = 'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים';
        await _pumpSmart(
          tester,
          _inject(raw, [_point('מפרש', 6)]),
          settings: const RenderSettings(fontSize: 20, fontFamily: 'Rubik'),
        );
        final overlay = tester.widget<RaisedMarkerOverlay>(
          find.byType(RaisedMarkerOverlay),
        );
        expect(
          overlay.baseStyle.fontFamily,
          AppFonts.taamimSafeFontFamily('Rubik', raw),
        );
        expect(overlay.baseStyle.fontFamily, isNot('Rubik'));
      },
    );

    test(
      'שורה עם ציון לעולם אינה עוברת במסלול המהיר — שם הגליף לא היה שקוף (issue #2075)',
      () {
        for (final lineIndex in [null, 0]) {
          final processed = TextRendererService.processText(
            _inject(line, [_point('מפרש', 7)], lineIndex: lineIndex),
            _settings,
          );
          expect(SimpleInlineHtml.tryParse(processed, _base), isNull);
        }
      },
    );

    testWidgets(
      'c60053e: קריאה רציפה — אותו ציון בשתי שורות של פסקה מצויר פעמיים, כל אחד במקומו (issue #2075)',
      (tester) async {
        final links = [_point('מפרש', 7)];
        await _pumpContinuous(tester, [
          _inject(line, links),
          _inject(line, links),
        ], width: 1600);

        final placements = _placements(tester);
        expect(placements, hasLength(2));
        expect(placements[0].text, placements[1].text);
        expect(
          placements[0].anchorRect.center.dx,
          greaterThan(placements[1].anchorRect.center.dx),
        );
      },
    );
  });
}
