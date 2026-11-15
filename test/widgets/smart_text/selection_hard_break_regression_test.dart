import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

void main() {
  setUpAll(() async {
    final data = await File('fonts/FrankRuehlCLM-Medium.ttf').readAsBytes();
    await (FontLoader(
      'FrankRuhlCLM',
    )..addFont(Future.value(ByteData.sublistView(data)))).load();
  });
  testWidgets('סמן בשבירת שורה תואם לשורה זהה גם ברווחים ובטקסט מעורב', (
    tester,
  ) async {
    const samples = [
      'בראשית ברא את השמים ואת הארץ',
      'Hello world שלום עולם',
      'שלום עולם Hello world',
      'Hello world',
      'בראשית ברא   ',
      'בראשית ברא 123',
      'בראשית ברא 😀 את',
      'בראשית ברא 👨‍👩‍👧‍👦 את',
      'א ffi שלום',
      'אבג\tדהו',
      'אבג\r',
      'אבג\t',
      'אבג\u000b',
      'אבג\u000c',
      'אבג\u001c',
      'אבג\u001d',
      'אבג\u001e',
      'אבג\u001f',
      'אבג\u0085',
      'אבג\u00a0',
      'אבג\u1680',
      'אבג\u2000',
      'אבג\u2001',
      'אבג\u2002',
      'אבג\u2003',
      'אבג\u2004',
      'אבג\u2005',
      'אבג\u2006',
      'אבג\u2007',
      'אבג\u2008',
      'אבג\u2009',
      'אבג\u200a',
      'אבג\u202f',
      'אבג\u205f',
      'אבג\u3000',
      'אבג\ufeff',
      'בְּרֵאשִׁית בָּרָא abc def 123 אֵת לְךָ',
      'אתה חונן לאדם דעת ומלמד לאנוש בינה וחננו מאתך דעה בינה והשכל ברוך אתה יי חונן הדעת השיבנו אבינו לתורתך וקרבנו מלכנו לעבודתך',
    ];
    final failures = <String>[];
    for (final dimensions in [
      (width: 260.0, fontSize: 18.0),
      (width: 500.0, fontSize: 40.0),
    ]) {
      for (final align in TextAlign.values) {
        for (final sample in samples) {
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SelectionArea(
                    child: SizedBox(
                      width: dimensions.width,
                      child: SelectionFillText.rich(
                        TextSpan(text: '$sample\n$sample'),
                        style: TextStyle(
                          fontFamily: 'FrankRuhlCLM',
                          fontSize: dimensions.fontSize,
                          height: 1.5,
                        ),
                        textAlign: align,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final p = tester.renderObject<RenderParagraph>(
            find.byType(SelectionFillRichText),
          );
          final n = sample.length;
          const caret = Rect.fromLTWH(0, 0, 2, 20);
          final top = p.getOffsetForCaret(TextPosition(offset: n), caret).dy;
          for (var i = 0; i < n; i++) {
            for (final affinity in TextAffinity.values) {
              final a = p.getOffsetForCaret(
                TextPosition(offset: i, affinity: affinity),
                caret,
              );
              final b = p.getOffsetForCaret(
                TextPosition(offset: i + n + 1, affinity: affinity),
                caret,
              );
              if (a.dy != top) {
                continue;
              }
              if ((a.dx - b.dx).abs() > .1) {
                failures.add(
                  '${dimensions.fontSize} $align ${sample.codeUnits} i=$i $affinity: ${a.dx} vs ${b.dx}',
                );
              }
            }
          }
        }
      }
    }
    expect(failures, isEmpty);
  });

  for (final html in [false, true]) {
    testWidgets('רווחי שורה שומרים את מדידות Flutter: HTML=$html', (
      tester,
    ) async {
      for (final whitespace
          in html
              ? [' ', '   ']
              : [
                  ' ',
                  '   ',
                  '\t',
                  '\r',
                  '\u2002',
                  '\u2003',
                  '\u2009',
                  '\u3000',
                ]) {
        final sample = 'בראשית ברא$whitespace';
        final plain = html ? 'בראשית ברא \nבראשית ברא' : '$sample\n$sample';
        for (final align
            in html ? [TextAlign.justify, TextAlign.start] : TextAlign.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SelectionArea(
                    child: SizedBox(
                      width: 500,
                      child: html
                          ? SmartTextWidget(
                              text: '<div>$sample<br>בראשית ברא</div>',
                              settings: RenderSettings(
                                justifyText: align == TextAlign.justify,
                                fontFamily: 'FrankRuhlCLM',
                                fontSize: 40,
                                lineHeight: 1.5,
                              ),
                            )
                          : SelectionFillText.rich(
                              TextSpan(text: plain),
                              style: const TextStyle(
                                fontFamily: 'FrankRuhlCLM',
                                fontSize: 40,
                                height: 1.5,
                              ),
                              textAlign: align,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final paragraph = tester
              .renderObjectList<RenderParagraph>(
                find.byType(SelectionFillRichText),
              )
              .single;
          expect(paragraph.text.toPlainText(), plain);
          final baseline =
              TextPainter(
                text: paragraph.text,
                textDirection: paragraph.textDirection,
                textAlign: paragraph.textAlign,
                strutStyle: paragraph.strutStyle,
              )..layout(
                minWidth: paragraph.size.width,
                maxWidth: paragraph.size.width,
              );
          addTearDown(baseline.dispose);
          const caret = Rect.fromLTWH(0, 0, 2, 20);
          for (var i = 0; i <= plain.length; i++) {
            for (final affinity in TextAffinity.values) {
              final position = TextPosition(offset: i, affinity: affinity);
              expect(
                paragraph.getOffsetForCaret(position, caret),
                baseline.getOffsetForCaret(position, caret),
                reason:
                    'HTML=$html $align whitespace=${whitespace.codeUnits} offset=$i $affinity',
              );
            }
          }
          final selection = TextSelection(
            baseOffset: 0,
            extentOffset: plain.length,
          );
          final expectedGlyphs = baseline.getBoxesForSelection(selection);
          expect(glyphBoxesForSelection(paragraph, selection), expectedGlyphs);
          final expectedFill = baseline.getBoxesForSelection(
            selection,
            boxHeightStyle: ui.BoxHeightStyle.max,
          );
          final actualFill = paragraph.getBoxesForSelection(selection);
          expect(actualFill.length, expectedFill.length);
          for (var i = 0; i < actualFill.length; i++) {
            final expected = expectedFill[i];
            expect(
              actualFill[i].left,
              expected.left.clamp(0, paragraph.size.width),
            );
            expect(
              actualFill[i].right,
              expected.right.clamp(0, paragraph.size.width),
            );
          }
          final rows = expectedGlyphs
              .map((box) => box.toRect().center.dy)
              .toSet();
          for (final y in rows) {
            for (var x = 0.0; x <= paragraph.size.width; x += 3) {
              final point = Offset(x, y);
              expect(
                paragraph.getPositionForOffset(point),
                baseline.getPositionForOffset(point),
              );
            }
          }
        }
      }
    });
  }
}
