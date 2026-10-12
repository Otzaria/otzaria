import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/printing/shaped_text/shaped_text_layout.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// מילה בצורת מקף (אד-ני, ש-די, אלו-ה, אהי-ה) לעולם אינה נחתכת בין שתי שורות —
/// לא בתצוגה ולא בהדפסה. מקף ASCII לבדו מתיר שבירה אחריו (UAX#14), ולכן אחריו
/// בא מחבר מילים; הבדיקה סורקת רוחבים רבים ובודקת שהמילה כולה על שורה אחת.
void main() {
  const fontFamily = 'FrankRuhlCLM';
  const fontPath = 'fonts/FrankRuehlCLM-Medium.ttf';
  const substitute = RenderSettings(
    substituteDivineNames: true,
    formatParentheses: false,
    fontFamily: fontFamily,
    fontSize: 20,
  );

  const plainWords = [
    (word: 'אדני', kind: DivineNameKind.adnut),
    (word: 'שדי', kind: DivineNameKind.shaddai),
    (word: 'אלוה', kind: DivineNameKind.eloah),
    (word: 'אהיה', kind: DivineNameKind.ehyeh),
  ];
  const pointedWords = [
    (word: 'אֲדֹנָי', kind: DivineNameKind.adnut),
    (word: 'שַׁדַּי', kind: DivineNameKind.shaddai),
    (word: 'אֱלוֹהַּ', kind: DivineNameKind.eloah),
    (word: 'אֶהְיֶה', kind: DivineNameKind.ehyeh),
  ];

  /// שורה ארוכה עם כל הצורות, כ-HTML מסומן (לפני הרינדור).
  String markedLine(List<({String word, int kind})> words) {
    final text = StringBuffer();
    final spans = DivineNameSpansBuilder();
    for (var repeat = 0; repeat < 12; repeat++) {
      for (final entry in words) {
        text.write('ויאמר ');
        spans.add(0, text.length, text.length + entry.word.length, entry.kind);
        text.write('${entry.word} שלום ');
      }
    }
    return injectDivineNameMarkers(text.toString(), spans.build(), 0);
  }

  String shownLine(List<({String word, int kind})> words) =>
      TextRendererService.processText(markedLine(words), substitute);

  /// מיקומי המילים עם מקף בטקסט: [start, end).
  List<(int, int)> hyphenatedWords(String text) => [
    for (final match in RegExp(r'\S*-\S*').allMatches(text))
      (match.start, match.end),
  ];

  /// כמה פעמים מילה עם מקף נחתכה בין שורות, בכל הרוחבים.
  int splitCount(
    List<TextBox> Function(TextSelection) boxesFor,
    List<(int, int)> words,
  ) {
    var splits = 0;
    for (final (start, end) in words) {
      final boxes = boxesFor(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      final tops = boxes.map((b) => b.top.round()).toSet();
      if (tops.length > 1) splits++;
    }
    return splits;
  }

  int sweepTextPainter(String text) {
    final words = hyphenatedWords(text);
    expect(words, isNotEmpty);
    var splits = 0;
    for (var width = 160.0; width <= 900; width += 2) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontFamily: fontFamily, fontSize: 20),
        ),
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: width);
      splits += splitCount(painter.getBoxesForSelection, words);
      painter.dispose();
    }
    return splits;
  }

  setUpAll(() async {
    final bytes = File(fontPath).readAsBytesSync();
    final loader = FontLoader(fontFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  group('תצוגה (מנוע הטקסט של Flutter)', () {
    test('בקרה: מקף ASCII לבדו נשבר — הבדיקה אכן מזהה שבירה', () {
      final bare = withoutDivineNameJoiners(shownLine(plainWords));
      expect(sweepTextPainter(bare), greaterThan(0));
    });

    test('בלי ניקוד — המילה לעולם לא נחתכת', () {
      final text = shownLine(plainWords);
      expect(text, contains(kDivineNameHyphen));
      expect(sweepTextPainter(text), 0);
    });

    test('עם ניקוד — המילה לעולם לא נחתכת', () {
      expect(sweepTextPainter(shownLine(pointedWords)), 0);
    });

    test('מחבר המילים אינו תופס רוחב', () {
      double widthOf(String text) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(fontFamily: fontFamily, fontSize: 20),
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      expect(widthOf('אד$kDivineNameHyphenני'), widthOf('אד-ני'));
    });

    testWidgets('הנתיב האמיתי (SmartTextWidget) — עם ובלי ניקוד', (
      tester,
    ) async {
      for (final words in [plainWords, pointedWords]) {
        final marked = markedLine(words);
        for (var width = 200.0; width <= 700; width += 8) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: width,
                    child: SmartTextWidget(text: marked, settings: substitute),
                  ),
                ),
              ),
            ),
          );
          final paragraphs = tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))
              .where((p) => p.text.toPlainText().contains('-'))
              .toList();
          expect(paragraphs, isNotEmpty);
          for (final paragraph in paragraphs) {
            final text = paragraph.text.toPlainText();
            expect(
              splitCount(paragraph.getBoxesForSelection, hyphenatedWords(text)),
              0,
              reason: 'רוחב $width',
            );
          }
        }
      }
    });
  });

  group(
    'הדפסה (פריסת השורות של ה-PDF)',
    () {
      test('שורה נשברת רק ברווחים, והמילה עם המקף נשארת שלמה', () {
        final shaper = ShaperFont.register(File(fontPath).readAsBytesSync());
        addTearDown(shaper.dispose);
        final layout = ShapedTextLayout(fonts: [shaper], fontSize: 14);

        for (final words in [plainWords, pointedWords]) {
          final text = shownLine(words);
          final expected = text
              .split(RegExp(r'\s+'))
              .where((w) => w.contains('-'))
              .toList();
          for (var width = 60.0; width <= 400; width += 2) {
            final block = layout.layout(text, maxWidth: width);
            final printed = [
              for (final line in block.lines)
                for (final segment in line.segments)
                  if (segment.run.text.contains('-')) segment.run.text,
            ];
            expect(printed, unorderedEquals(expected), reason: 'רוחב $width');
          }
        }
      });

      test('מחבר המילים מודפס בלי ריבוע ובלי רוחב', () {
        final shaper = ShaperFont.register(File(fontPath).readAsBytesSync());
        addTearDown(shaper.dispose);
        final joined = shaper.shape(
          'אד$kDivineNameHyphenני',
          rtl: true,
          script: 'hebr',
        );
        final bare = shaper.shape('אד-ני', rtl: true, script: 'hebr');
        for (var index = 0; index < joined.glyphCount; index++) {
          expect(joined.glyphId(index), isNot(0));
        }
        expect(joined.advanceAt(14), closeTo(bare.advanceAt(14), 0.001));
      });
    },
  );
}
