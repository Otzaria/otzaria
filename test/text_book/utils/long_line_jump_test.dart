import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

const _marker = 'QQMARKQQ';
const _settings = RenderSettings(fontSize: 16, lineHeight: 1.5);

/// טקסט סינתטי: מילים עם ניקוד וטעמים, מקף, RLM/LRM, בידוד LRI..PDI עם רווחים,
/// זוגות surrogate, ומקרי קצה של רווח שאחריו סימן צירוף.
String _nastyText(int chars, {int seed = 3, double? markerAt}) {
  const letters = 'אבגדהוזחטיכלמנסעפצקרשת';
  const marks = ['ְ', 'ִ', 'ָ', 'ּ', '֑', '֥'];
  final r = Random(seed);
  final out = StringBuffer();
  var markerDone = markerAt == null;
  var n = 0;
  while (out.length < chars) {
    if (!markerDone && out.length >= markerAt! * chars) {
      out.write('$_marker ');
      markerDone = true;
    }
    n++;
    for (var i = 0, k = 2 + r.nextInt(5); i < k; i++) {
      out.write(letters[r.nextInt(letters.length)]);
      if (r.nextBool()) out.write(marks[r.nextInt(marks.length)]);
      if (r.nextInt(4) == 0) out.write(marks[r.nextInt(marks.length)]);
    }
    switch (n % 11) {
      case 0:
        out.write('־');
      case 1:
        out.write('\u200F ');
      case 2:
        out.write(' \u200E');
      case 3:
        out.write(' \u2066abc def ghi\u2069 ');
      case 4:
        out.write(' \u{1F600} ');
      case 5:
        // רווח ואחריו סימן צירוף "יתום" — חיתוך כאן מפריד את הסימן מהרווח.
        out.write(' ָ');
      case 6:
        out.write('. ');
      default:
        out.write(' ');
    }
  }
  return out.toString();
}

void main() {
  for (final pumpStep in [16, 100]) {
    testWidgets(
      'קפיצה להתאמה עמוקה בשורה ארוכה מגיעה לעוגן, גם אחרי שינוי גופן '
      '(צעד $pumpStep ms)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final longLine = _nastyText(320000, markerAt: 0.85);
        final lines = [
          for (var i = 0; i < 10; i++) 'שורה קצרה $i',
          longLine,
          for (var i = 0; i < 10; i++) 'שורה קצרה אחרי $i',
        ];
        final segments = buildReadingSegments(lines, continuous: false);
        final itemScrollController = ItemScrollController();
        final positionsListener = ItemPositionsListener.create();
        Future<void> pumpList(RenderSettings settings) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 600,
                child: ScrollablePositionedList.builder(
                  itemScrollController: itemScrollController,
                  itemPositionsListener: positionsListener,
                  itemCount: lines.length,
                  itemBuilder: (context, index) =>
                      SmartTextWidget(text: lines[index], settings: settings),
                ),
              ),
            ),
          ),
        );
        final fraction = longLine.indexOf(_marker) / longLine.length;

        Future<void> jumpAndExpectMarkerVisible() async {
          var finished = false;
          final future = scrollToSourceLine(
            scrollController: itemScrollController,
            positionsListener: positionsListener,
            segments: segments,
            lineIndex: 10,
            alignment: kSearchResultAnchorAlignment,
            intraLineFraction: fraction,
            duration: const Duration(milliseconds: 300),
          ).then((_) => finished = true);
          for (var i = 0; i < 400 && !finished; i++) {
            await tester.pump(Duration(milliseconds: pumpStep));
          }
          await future;
          await tester.pumpAndSettle();
          final markerFinder = find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains(_marker),
            skipOffstage: false,
          );
          expect(markerFinder, findsOneWidget);
          final p = tester.renderObject<RenderParagraph>(markerFinder);
          final local = p.text.toPlainText().indexOf(_marker);
          final rect = p
              .getBoxesForSelection(
                TextSelection(baseOffset: local, extentOffset: local + 1),
              )
              .first
              .toRect()
              .shift(p.localToGlobal(Offset.zero));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(600));
        }

        await pumpList(_settings);
        await tester.pumpAndSettle();
        await jumpAndExpectMarkerVisible();

        // גופן אחר בונה את השורה מחדש מהמקטע הראשון — כמו שחזור המקום אחרי פריסה.
        await pumpList(_settings.copyWith(fontSize: 20));
        await jumpAndExpectMarkerVisible();
      },
    );
  }

  testWidgets('ניווט שבוטל בזמן הבנייה אינו חוזר ליעד כשהשורה הושלמה', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final line = _nastyText(320000);
    final segments = buildReadingSegments([line], continuous: false);
    final item = ItemScrollController();
    final pixels = ScrollController();
    addTearDown(pixels.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedList.builder(
            itemScrollController: item,
            scrollController: pixels,
            itemCount: 1,
            itemBuilder: (_, index) =>
                SmartTextWidget(text: line, settings: _settings),
          ),
        ),
      ),
    );
    var current = true;
    var finished = false;
    final navigation = scrollToSourceLine(
      scrollController: item,
      positionsListener: null,
      segments: segments,
      lineIndex: 0,
      intraLineFraction: 0.85,
      duration: Duration.zero,
      isCurrent: () => current,
    ).then((_) => finished = true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(LongLineChunks), findsOneWidget);
    expect(finished, isFalse);

    current = false;
    item.listController!.cancelPositioning();
    pixels.jumpTo(pixels.offset + 30);
    final userPixels = pixels.offset;
    await tester.pump(const Duration(milliseconds: 16));
    expect(finished, isTrue);
    await navigation;
    await tester.pumpAndSettle();
    expect(pixels.offset, closeTo(userPixels, 0.01));
  });

  testWidgets('שורה ארוכה ברשימה אחרת אינה מעכבת ניווט רגיל', (tester) async {
    final regular = ItemScrollController();
    final segments = buildReadingSegments(
      List.generate(100, (i) => 'שורה קצרה $i'),
      continuous: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    SmartTextWidget(
                      text: _nastyText(640000),
                      settings: _settings,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ScrollablePositionedList.builder(
                  itemScrollController: regular,
                  itemCount: 100,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 40, child: Text('שורה קצרה $i')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var finished = false;
    final navigation = scrollToSourceLine(
      scrollController: regular,
      positionsListener: null,
      segments: segments,
      lineIndex: 20,
      duration: Duration.zero,
    ).then((_) => finished = true);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      finished,
      isTrue,
      reason: 'ניווט רגיל צריך להסתיים בזמן שהרשימה האחרת עדיין נבנית',
    );
    await tester.pumpAndSettle();
    await navigation;
  });
}
