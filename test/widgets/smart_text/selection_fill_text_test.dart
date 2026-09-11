import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// מטריקות ה-ascent/descent האמיתיות של הגופן הן כל הסיפור כאן, וגופן הבדיקה
/// של flutter_test אינו מייצג אותן.
Future<void> _loadFont() async {
  final bytes = await File('fonts/FrankRuehlCLM-Medium.ttf').readAsBytes();
  await (FontLoader(
    'FrankRuhlCLM',
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

const _settings = RenderSettings(
  fontSize: 18,
  fontFamily: 'FrankRuhlCLM',
  lineHeight: 1.5,
);

const _baseStyle = TextStyle(
  fontFamily: 'FrankRuhlCLM',
  fontSize: 18,
  height: 1.5,
);

/// טקסט ארוך דיו כדי להישבר לכמה שורות תצוגה ברוחב הנתון.
const _longText =
    'אתה חונן לאדם דעת ומלמד לאנוש בינה וחננו מאתך דעה בינה והשכל '
    'ברוך אתה יי חונן הדעת השיבנו אבינו לתורתך וקרבנו מלכנו לעבודתך';

Widget _wrap(Widget child, {bool selectable = true}) {
  final body = SizedBox(width: 260, child: child);
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: selectable ? SelectionArea(child: body) : body,
      ),
    ),
  );
}

/// תיבות הבחירה כפי שציור הבחירה בפריימוורק מבקש אותן — בלי `boxHeightStyle`.
List<ui.TextBox> _paintedBoxes(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  return paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
}

void _expectNoVerticalGaps(RenderParagraph paragraph, {double tolerance = 0}) {
  final boxes = _paintedBoxes(paragraph);
  expect(
    boxes.length,
    greaterThan(1),
    reason: 'צריך כמה שורות תצוגה כדי למדוד',
  );
  final tops = boxes.map((b) => b.top).toSet().toList()..sort();
  final bottoms = boxes.map((b) => b.bottom).toSet().toList()..sort();
  // תחתית כל שורה היא ראש השורה הבאה — בלי פס לא-צבוע ביניהן.
  for (var i = 0; i < tops.length - 1; i++) {
    expect(
      bottoms[i],
      closeTo(tops[i + 1], tolerance),
      reason: 'פער בין שורה $i לשורה ${i + 1}',
    );
  }
}

void main() {
  setUpAll(_loadFont);

  group('הדגשת הבחירה ממלאת את גובה השורה', () {
    testWidgets('המסלול המהיר של SmartTextWidget', (tester) async {
      await tester.pumpWidget(
        _wrap(const SmartTextWidget(text: _longText, settings: _settings)),
      );

      expect(find.byType(SelectionFillRichText), findsOneWidget);
      _expectNoVerticalGaps(
        tester.renderObject<RenderParagraph>(
          find.byType(SelectionFillRichText),
        ),
      );
    });

    testWidgets('מסלול ה-HtmlWidget', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '$_longText <span class="link-anchor">א</span>',
            settings: _settings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HtmlWidget), findsOneWidget);
      final paragraph = tester
          .renderObjectList<RenderParagraph>(find.byType(SelectionFillRichText))
          .firstWhere((p) => p.text.toPlainText().contains('חונן'));
      _expectNoVerticalGaps(paragraph);
    });

    testWidgets('פסקה במצב קריאה רציפה', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ContinuousReadingParagraph(
            lines: const [
              ContinuousReadingParagraphLine(
                lineIndex: 0,
                text: _longText,
                htmlText: _longText,
                style: _baseStyle,
              ),
            ],
            baseStyle: _baseStyle,
            onLineTap: (_) {},
          ),
        ),
      );

      expect(find.byType(SelectionFillRichText), findsOneWidget);
      _expectNoVerticalGaps(
        tester.renderObject<RenderParagraph>(
          find.byType(SelectionFillRichText),
        ),
      );
    });

    // `<big>` במרווח צפוף אינו מקובע (ראו exactLineHeightStrut), ולכן השורה
    // שבה הוא יושב גבוהה משכנותיה ונשאר הפרש עיגול תת-פיקסלי — לא פס נראה.
    testWidgets('שורה עם <big> נשארת רציפה לשורות סביבה', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<big><strong>גמ׳</strong></big> $_longText',
            settings: RenderSettings(
              fontSize: 18,
              fontFamily: 'FrankRuhlCLM',
              lineHeight: 1.1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      _expectNoVerticalGaps(
        tester
            .renderObjectList<RenderParagraph>(
              find.byType(SelectionFillRichText),
            )
            .firstWhere((p) => p.text.toPlainText().contains('חונן')),
        tolerance: 0.5,
      );
    });

    testWidgets('בלי בחירה בעץ נשאר RichText רגיל', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(text: _longText, settings: _settings),
          selectable: false,
        ),
      );

      expect(find.byType(SelectionFillRichText), findsNothing);
      expect(find.byType(RichText), findsWidgets);
    });

    // בלי התיקון, תיבת הבחירה היא בגובה הגליף בלבד ונשאר פס לא-צבוע.
    testWidgets('RichText רגיל אכן משאיר פער — הבדיקה מודדת משהו', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Text(_longText, style: _baseStyle),
        ),
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText).first,
      );
      final boxes = _paintedBoxes(paragraph);
      final tops = boxes.map((b) => b.top).toSet().toList()..sort();
      final bottoms = boxes.map((b) => b.bottom).toSet().toList()..sort();
      expect(bottoms.first, lessThan(tops[1]));
    });
  });
}
