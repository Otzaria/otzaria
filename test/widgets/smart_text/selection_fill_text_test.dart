import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
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

  for (final selectable in [false, true]) {
    for (final boldText in [false, true]) {
      testWidgets('טיפוגרפיית Text.rich נשמרת: '
          'בחירה=$selectable, boldText=$boldText', (tester) async {
        const span = TextSpan(
          text: 'טקסט ',
          children: [
            TextSpan(text: 'נוסף', style: TextStyle(letterSpacing: 0.5)),
          ],
        );
        const style = TextStyle(fontSize: 18, overflow: TextOverflow.ellipsis);
        const strut = StrutStyle(fontSize: 18, height: 1.3);
        const baselineKey = ValueKey('baseline');
        const actualKey = ValueKey('actual');
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                final media = MediaQuery.of(
                  context,
                ).copyWith(boldText: boldText);
                final body = Column(
                  children: [
                    Text.rich(
                      span,
                      key: baselineKey,
                      style: style,
                      strutStyle: strut,
                    ),
                    const SelectionFillText.rich(
                      span,
                      key: actualKey,
                      style: style,
                      strutStyle: strut,
                    ),
                  ],
                );
                return MediaQuery(
                  data: media,
                  child: Scaffold(
                    body: selectable ? SelectionArea(child: body) : body,
                  ),
                );
              },
            ),
          ),
        );

        RenderParagraph paragraphFor(Key key) => tester.renderObject(
          find
              .descendant(
                of: find.byKey(key),
                matching: find.byWidgetPredicate(
                  (widget) => widget is RichText,
                ),
              )
              .first,
        );
        final baseline = paragraphFor(baselineKey);
        final actual = paragraphFor(actualKey);
        expect(actual.text.style, baseline.text.style);
        expect(
          actual.text.style!.fontWeight,
          boldText ? FontWeight.bold : isNot(FontWeight.bold),
        );
        expect(actual.overflow, baseline.overflow);
        expect(actual.strutStyle, baseline.strutStyle);
      });
    }
  }

  testWidgets('override של גובה וריווח אותיות/מילים נשמר גם בבחירה', (
    tester,
  ) async {
    const span = TextSpan(
      text: 'מילה ',
      children: [TextSpan(text: 'נוספת', style: TextStyle(fontSize: 20))],
    );
    const strut = StrutStyle(fontSize: 18, height: 1.2);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final media = MediaQuery.of(context).applyTextStyleOverrides(
              lineHeightScaleFactorOverride: 1.5,
              letterSpacingOverride: 2,
              wordSpacingOverride: 3,
              paragraphSpacingOverride: null,
            );
            return MediaQuery(
              data: media,
              child: Scaffold(
                body: SelectionArea(
                  child: Column(
                    children: [
                      const Text.rich(
                        span,
                        key: ValueKey('baseline'),
                        strutStyle: strut,
                      ),
                      const SelectionFillText.rich(
                        span,
                        key: ValueKey('actual'),
                        strutStyle: strut,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    RenderParagraph paragraphFor(String key) => tester.renderObject(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byWidgetPredicate((widget) => widget is RichText),
          )
          .first,
    );
    final baseline = paragraphFor('baseline');
    final actual = paragraphFor('actual');
    final baselineSpan = baseline.text as TextSpan;
    final actualSpan = actual.text as TextSpan;
    expect(actualSpan.style, baselineSpan.style);
    expect(
      (actualSpan.children!.first as TextSpan).style,
      (baselineSpan.children!.first as TextSpan).style,
    );
    expect(actual.strutStyle, baseline.strutStyle);
  });

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

    for (final viaHtml in [false, true]) {
      testWidgets(
        viaHtml ? 'מסלול ה-HtmlWidget' : 'שורה עם עוגן במסלול הספאנים',
        (tester) async {
          SmartTextWidget.debugForceHtmlWidget = viaHtml;
          addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
          await tester.pumpWidget(
            _wrap(
              const SmartTextWidget(
                text: '$_longText <span class="link-anchor">א</span>',
                settings: _settings,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byType(HtmlWidget),
            viaHtml ? findsOneWidget : findsNothing,
          );
          final paragraph = tester
              .renderObjectList<RenderParagraph>(
                find.byType(SelectionFillRichText),
              )
              .firstWhere((p) => p.text.toPlainText().contains('חונן'));
          _expectNoVerticalGaps(paragraph);
        },
      );
    }

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

  // issue #3102: פריט רשימה שמור שנגלל מהתצוגה מחובר לעץ, אבל הרשימה לא פורסת
  // אותו — ופסקה חדשה בו נרשמת לבחירה בלי שנפרסה.
  testWidgets('פסקה שנבנתה בפריט רשימה שמור מחוץ לתצוגה לא מפילה את הבחירה', (
    tester,
  ) async {
    final scroll = ScrollController();
    final lines = GlobalKey<_GrowingLinesState>();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: ListView(
            controller: scroll,
            children: [
              _KeptAlive(child: _GrowingLines(key: lines)),
              const SizedBox(height: 5000),
            ],
          ),
        ),
      ),
    );

    scroll.jumpTo(3000);
    await tester.pump();
    lines.currentState!.add('שורה שנוספה מחוץ לתצוגה');
    lines.currentState!.add('ועוד אחת');
    await tester.pump();
    expect(tester.takeException(), isNull);

    scroll.jumpTo(0);
    await tester.pump();
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();
    expect(selected, contains('שורה שנוספה מחוץ לתצוגה'));
  });

  // issue #1402: מי שממקם ציור ביחס לאותיות (סימונים מורמים, הדגשות תוספים)
  // חייב לקבל תיבות בגובה הגליף גם כשהבחירה ממופה לגובה השורה.
  testWidgets('glyphBoxesForSelection מחזיר תיבות tight גם בטקסט בר-בחירה', (
    tester,
  ) async {
    Future<(List<ui.TextBox>, List<ui.TextBox>)> boxes({
      required bool selectable,
    }) async {
      await tester.pumpWidget(
        _wrap(
          const SelectionFillText.rich(
            TextSpan(text: _longText),
            style: _baseStyle,
          ),
          selectable: selectable,
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate((w) => w is RichText),
      );
      const selection = TextSelection(baseOffset: 0, extentOffset: 20);
      return (
        glyphBoxesForSelection(paragraph, selection),
        paragraph.getBoxesForSelection(selection),
      );
    }

    final (plainGlyph, plainPainted) = await boxes(selectable: false);
    final (selectableGlyph, selectablePainted) = await boxes(selectable: true);

    expect(selectableGlyph, plainGlyph);
    expect(plainGlyph, plainPainted);
    expect(
      selectablePainted.first.bottom - selectablePainted.first.top,
      greaterThan(plainGlyph.first.bottom - plainGlyph.first.top),
      reason: 'ציור הבחירה עצמו עדיין ממלא את גובה השורה',
    );
  });
}

class _KeptAlive extends StatefulWidget {
  const _KeptAlive({required this.child});

  final Widget child;

  @override
  State<_KeptAlive> createState() => _KeptAliveState();
}

class _KeptAliveState extends State<_KeptAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _GrowingLines extends StatefulWidget {
  const _GrowingLines({super.key});

  @override
  State<_GrowingLines> createState() => _GrowingLinesState();
}

class _GrowingLinesState extends State<_GrowingLines> {
  final _lines = <String>['שורה ראשונה'];

  void add(String line) => setState(() => _lines.add(line));

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final line in _lines)
        SelectionFillText.rich(TextSpan(text: line), style: _baseStyle),
    ],
  );
}
