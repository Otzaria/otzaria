import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// אימות end-to-end שספאנים מודגשים מקבלים FontVariation('wght') בגופן משתנה
/// — ורק בו — בכל שלושת נתיבי ההזרקה: מסלול מהיר, fwfh, וקריאה רציפה.
void main() {
  group('בולד אמיתי — מסלול מהיר (SimpleInlineHtml → Text.rich)', () {
    testWidgets(
      'גופן משתנה (Rubik) → הספאן המודגש מכיל FontVariation wght 700',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const SmartTextWidget(
              text: '<b>מודגש</b> רגיל',
              settings: RenderSettings(fontSize: 20, fontFamily: 'Rubik'),
            ),
          ),
        );

        expect(
          find.byType(HtmlWidget),
          findsNothing,
          reason: 'שורה עם <b> בלבד חייבת להישאר במסלול המהיר',
        );
        final rich = tester.widget<RichText>(find.byType(RichText));
        final bold = _spansContaining(rich.text, 'מודגש');
        expect(bold, isNotEmpty);
        final boldStyle = bold.single.style!;
        expect(boldStyle.fontWeight, FontWeight.bold);
        expect(boldStyle.fontVariations, const [FontVariation('wght', 700)]);

        final plain = _spansContaining(rich.text, 'רגיל');
        expect(plain, isNotEmpty);
        for (final s in plain) {
          expect(s.style?.fontVariations, isNull);
        }
      },
    );

    testWidgets(
      'גופן לא-משתנה (FrankRuhlCLM) → fontWeight.bold נשמר, בלי fontVariations',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const SmartTextWidget(
              text: '<b>מודגש</b> רגיל',
              settings: RenderSettings(
                fontSize: 20,
                fontFamily: 'FrankRuhlCLM',
              ),
            ),
          ),
        );

        expect(find.byType(HtmlWidget), findsNothing);
        final rich = tester.widget<RichText>(find.byType(RichText));
        final bold = _spansContaining(rich.text, 'מודגש');
        expect(bold, isNotEmpty);
        final boldStyle = bold.single.style!;
        expect(boldStyle.fontWeight, FontWeight.bold);
        expect(
          boldStyle.fontVariations,
          isNull,
          reason: 'גופן סטטי — בחירת ה-face של Flutter מטפלת בבולד',
        );
      },
    );
  });

  group('בולד אמיתי — מסלול fwfh (HtmlWidget + WidgetFactory)', () {
    testWidgets(
      'span עם class מפיל ל-fwfh; הספאן המודגש קיבל FontVariation wght 700',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const SmartTextWidget(
              text: '<b>מודגש</b> <span class="hl">רגיל</span>',
              settings: RenderSettings(fontSize: 20, fontFamily: 'Rubik'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(HtmlWidget),
          findsOneWidget,
          reason: 'span עם class חייב ליפול למסלול fwfh המלא',
        );

        final richTexts = tester.widgetList<RichText>(find.byType(RichText));
        final allBold = <TextSpan>[];
        for (final rt in richTexts) {
          allBold.addAll(_spansContaining(rt.text, 'מודגש'));
        }
        expect(allBold, isNotEmpty);
        final withVariation = allBold.where(
          (s) =>
              s.style?.fontVariations != null &&
              s.style!.fontVariations!.contains(
                const FontVariation('wght', 700),
              ),
        );
        expect(
          withVariation,
          isNotEmpty,
          reason: 'ה-WidgetFactory אמור להזריק FontVariation לספאן המודגש',
        );
        expect(withVariation.first.style!.fontWeight, FontWeight.bold);
      },
    );

    testWidgets(
      'גופן סטטי (FrankRuhlCLM) במסלול fwfh → אין FontVariation מוזרק',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const SmartTextWidget(
              text: '<b>מודגש</b> <span class="hl">רגיל</span>',
              settings: RenderSettings(
                fontSize: 20,
                fontFamily: 'FrankRuhlCLM',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HtmlWidget), findsOneWidget);
        final richTexts = tester.widgetList<RichText>(find.byType(RichText));
        for (final rt in richTexts) {
          for (final s in _spansContaining(rt.text, 'מודגש')) {
            expect(
              s.style?.fontVariations,
              isNull,
              reason: 'גופן סטטי לא אמור לקבל FontVariation גם ב-fwfh',
            );
          }
        }
      },
    );
  });

  group('בולד אמיתי — ContinuousReadingParagraph', () {
    testWidgets(
      '<b> עם גופן משתנה → הספאן המודגש מכיל FontVariation wght 700',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const SizedBox(
              width: 500,
              child: ContinuousReadingParagraph(
                lines: [
                  ContinuousReadingParagraphLine(
                    lineIndex: 0,
                    text: 'מודגש רגיל',
                    htmlText: '<b>מודגש</b> רגיל',
                    style: TextStyle(fontSize: 20, fontFamily: 'Rubik'),
                  ),
                ],
                baseStyle: TextStyle(fontSize: 20, fontFamily: 'Rubik'),
                onLineTap: _noopLineTap,
              ),
            ),
          ),
        );

        final rich = tester.widget<RichText>(find.byType(RichText));
        final bold = _spansContaining(rich.text, 'מודגש');
        expect(bold, isNotEmpty);
        final withVariation = bold.where(
          (s) =>
              s.style?.fontVariations != null &&
              s.style!.fontVariations!.contains(
                const FontVariation('wght', 700),
              ),
        );
        expect(withVariation, isNotEmpty);
        expect(withVariation.first.style!.fontWeight, FontWeight.bold);
      },
    );

    testWidgets('<b> עם גופן סטטי → fontWeight.bold בלי fontVariations', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 500,
            child: ContinuousReadingParagraph(
              lines: [
                ContinuousReadingParagraphLine(
                  lineIndex: 0,
                  text: 'מודגש רגיל',
                  htmlText: '<b>מודגש</b> רגיל',
                  style: TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM'),
                ),
              ],
              baseStyle: TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM'),
              onLineTap: _noopLineTap,
            ),
          ),
        ),
      );

      final rich = tester.widget<RichText>(find.byType(RichText));
      final bold = _spansContaining(rich.text, 'מודגש');
      expect(bold, isNotEmpty);
      final boldWithWeight = bold.where(
        (s) => s.style?.fontWeight == FontWeight.bold,
      );
      expect(boldWithWeight, isNotEmpty);
      for (final s in boldWithWeight) {
        expect(s.style?.fontVariations, isNull);
      }
    });
  });
}

Widget _wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

/// מחזיר את כל תת-הספאנים שהטקסט שלהם מכיל [needle].
List<TextSpan> _spansContaining(InlineSpan root, String needle) {
  final matches = <TextSpan>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      final t = span.text;
      if (t != null && t.contains(needle)) matches.add(span);
      for (final c in span.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(root);
  return matches;
}

void _noopLineTap(int _) {}
