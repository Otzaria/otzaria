import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/theme/app_colors.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../support/search_engine_test_init.dart';

const _text = 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
const _word = 'פירוש';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  for (final brightness in Brightness.values) {
    for (final renderer in ['fast', 'html', 'continuous']) {
      for (final highlight in ['current', 'other', 'linked']) {
        testWidgets(
          'בחירה וניגודיות: $brightness/$renderer/$highlight (#2198)',
          (
            tester,
          ) async {
            await tester.runAsync(() async {
              final loader = FontLoader('NotoRashiHebrew')
                ..addFont(
                  Future.value(
                    ByteData.sublistView(
                      await File(
                        'fonts/NotoRashiHebrew-VariableFont_wght.ttf',
                      ).readAsBytes(),
                    ),
                  ),
                );
              await loader.load();
            });
            final dark = brightness == Brightness.dark;
            final scheme = AppThemeData.createColorScheme(
              dark ? AppSeedColors.defaultDark : AppSeedColors.defaultLight,
              brightness,
            );
            final theme = dark
                ? AppThemeData.dark(scheme, compactMenuMode: false).copyWith(
                    scaffoldBackgroundColor: AppColors.darkScaffold,
                  )
                : AppThemeData.light(scheme, compactMenuMode: false);
            final current = highlight == 'current' ? 0 : -1;
            final linked = highlight == 'linked';
            final settings = RenderSettings(
              fontFamily: 'NotoRashiHebrew',
              fontSize: 22,
              fontWeight: FontWeight.normal,
              searchText: _word,
              currentSearchIndex: current,
              highlightYellowBackground: linked,
              partialWordHighlight: true,
            );
            final style = TextStyle(
              fontFamily: 'NotoRashiHebrew',
              fontSize: 22,
              fontWeight: FontWeight.normal,
              color: theme.colorScheme.onSurface,
            );
            final child = renderer == 'continuous'
                ? ContinuousReadingParagraph(
                    lines: [
                      ContinuousReadingParagraphLine(
                        lineIndex: 0,
                        text: _text,
                        htmlText: text_utils.highLight(
                          _text,
                          _word,
                          currentIndex: current,
                          yellowBackground: linked,
                          partialWordMatch: true,
                        ),
                        style: style,
                      ),
                    ],
                    baseStyle: style,
                    onLineTap: (_) {},
                  )
                : SmartTextWidget(
                    // תג לא נתמך מכריח מעבר דרך HtmlWidget.
                    text: renderer == 'html'
                        ? '<span style="letter-spacing: 0">$_text</span>'
                        : _text,
                    settings: settings,
                  );
            final key = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topRight,
                      child: RepaintBoundary(
                        key: key,
                        child: SizedBox(
                          width: 600,
                          height: 110,
                          child: ColoredBox(
                            color: theme.scaffoldBackgroundColor,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: SelectionArea(child: child),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final paragraph = tester.renderObject<RenderParagraph>(
              find.byWidgetPredicate((w) => w is RichText),
            );
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(key),
            );
            final start = paragraph.text.toPlainText().indexOf(_word);
            expect(start, greaterThanOrEqualTo(0));
            final box = paragraph
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: start,
                    extentOffset: start + _word.length,
                  ),
                )
                .first
                .toRect();
            // בפינת התיבה אין גליף, כך שהפיקסל מודד רקע בלבד.
            final probe = paragraph.localToGlobal(
              box.topLeft + const Offset(1, 1),
              ancestor: boundary,
            );
            Future<Color> pixel() async {
              final color = await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                final offset =
                    (probe.dy.round() * image.width + probe.dx.round()) * 4;
                final result = Color.fromARGB(
                  bytes.getUint8(offset + 3),
                  bytes.getUint8(offset),
                  bytes.getUint8(offset + 1),
                  bytes.getUint8(offset + 2),
                );
                image.dispose();
                return result;
              });
              return color!;
            }

            final foreground = highlight == 'current'
                ? const Color(0xFF0000FF)
                : linked
                ? const Color(0xFF000000)
                : const Color(0xFFFF0000);
            final matchedSpans = <TextSpan>[];
            void visit(InlineSpan span) {
              if (span is TextSpan) {
                if (span.text?.contains(_word) ?? false) matchedSpans.add(span);
                for (final child in span.children ?? <InlineSpan>[]) {
                  visit(child);
                }
              }
            }

            visit(paragraph.text);
            expect(matchedSpans, isNotEmpty);
            expect(matchedSpans.last.style?.color, foreground);
            final unselected = await pixel();
            tester
                .state<SelectionAreaState>(find.byType(SelectionArea))
                .selectableRegion
                .selectAll();
            await tester.pumpAndSettle();
            expect(paragraph.selections, isNotEmpty);
            final selected = await pixel();
            final change = math.max(
              (selected.r - unselected.r).abs(),
              math.max(
                (selected.g - unselected.g).abs(),
                (selected.b - unselected.b).abs(),
              ),
            );
            expect(
              change * 255,
              greaterThanOrEqualTo(8),
              reason: 'הבחירה צריכה להיות נראית',
            );
            if (highlight != 'other') {
              for (final background in [unselected, selected]) {
                final luminances = [
                  foreground.computeLuminance(),
                  background.computeLuminance(),
                ];
                final contrast =
                    (luminances.reduce(math.max) + .05) /
                    (luminances.reduce(math.min) + .05);
                expect(
                  contrast,
                  greaterThanOrEqualTo(4.5),
                  reason: 'טקסט 22px רגיל חייב להישאר קריא',
                );
              }
            }
          },
          skip: !engineReady,
        );
      }
    }
  }
}
