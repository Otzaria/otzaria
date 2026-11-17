import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// שורה סינתטית: מילים אקראיות, משפטים, הדגשות ושתי מילות סימון.
const _marker = 'סמןייחודי';

String _syntheticLine(int chars, {List<double> markersAt = const []}) {
  const letters = 'אבגדהוזחטיכלמנסעפצקרשת';
  final random = Random(7);
  final out = StringBuffer();
  final marks = [for (final at in markersAt) (at * chars).round()];
  var words = 0;
  while (out.length < chars) {
    if (marks.isNotEmpty && out.length >= marks.first) {
      marks.removeAt(0);
      out.write('$_marker ');
    }
    for (var i = 0, n = 2 + random.nextInt(6); i < n; i++) {
      out.write(letters[random.nextInt(letters.length)]);
    }
    words++;
    if (words % 97 == 0) out.write(' <b>מודגש בתוך השורה</b>');
    out.write(words % 23 == 0 ? '. ' : ' ');
  }
  return out.toString();
}

const _settings = RenderSettings(fontSize: 16, lineHeight: 1.5);

Widget _host(
  Widget child, {
  ValueChanged<SelectedContent?>? onSelectionChanged,
}) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SelectionArea(
        onSelectionChanged: onSelectionChanged,
        child: ListView(
          children: [SizedBox(width: 600, child: child)],
        ),
      ),
    ),
  ),
);

List<RenderParagraph> _paragraphs(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(
      find.byWidgetPredicate((widget) => widget is RichText),
    )
    .toList();

String _textOf(WidgetTester tester) =>
    _paragraphs(tester).map((p) => p.text.toPlainText()).join();

void main() {
  group('splitLongLine', () {
    test('שורה קצרה אינה מפוצלת', () {
      expect(splitLongLine(const TextSpan(text: 'שורה קצרה')), isNull);
    });

    test('המקטעים מחוברים לטקסט המקורי ונחתכים רק ברווח שאינו מעוצב', () {
      final leaves = <TextSpan>[];
      for (var i = 0; i < 400; i++) {
        leaves
          ..add(TextSpan(text: '${'מילה ' * 20}סוף משפט. '))
          ..add(
            const TextSpan(
              text: 'מודגש ארוך עם רווחים',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          )
          ..add(const TextSpan(text: '\n'));
      }
      final span = TextSpan(children: leaves);
      final split = splitLongLine(span)!;

      expect(split.chunks.length, greaterThan(2));
      expect(
        split.chunks.map((c) => c.toPlainText()).join(),
        span.toPlainText(),
      );
      expect(split.text, span.toPlainText());
      for (var i = 0; i < split.chunks.length; i++) {
        final chunk = split.chunks[i];
        expect(
          split.starts[i],
          split.chunks
              .take(i)
              .fold<int>(0, (n, c) => n + c.toPlainText().length),
        );
        if (i < split.chunks.length - 1) {
          expect(chunk.toPlainText(), endsWith(' '));
          // החיתוך בטקסט רגיל, ולכן הספאן האחרון של המקטע אינו מעוצב.
          expect((chunk.children!.last as TextSpan).style, isNull);
        }
        for (final leaf in chunk.children!.cast<TextSpan>()) {
          if (leaf.style != null) expect(leaf.text, 'מודגש ארוך עם רווחים');
        }
      }
    });

    List<String> texts(LongLineSplit split) => [
      for (final chunk in split.chunks) chunk.toPlainText(),
    ];

    test('בלי סופי משפט החיתוך הוא אחרי הרווח, לא לפניו', () {
      final span = TextSpan(text: 'מילה ' * 15000);
      final parts = texts(splitLongLine(span)!);

      expect(parts.length, greaterThan(2));
      expect(parts.join(), span.toPlainText());
      for (final part in parts.take(parts.length - 1)) {
        expect(part, endsWith(' '));
      }
      for (final part in parts.skip(1)) {
        expect(part, isNot(startsWith(' ')));
      }
    });

    test('ספאן מעוצב ארוך אינו נחתך', () {
      const styled = TextStyle(fontWeight: FontWeight.bold);
      final bold = 'מודגש ' * 6000;
      final span = TextSpan(
        children: [
          TextSpan(text: 'מילה ' * 4000),
          TextSpan(text: bold, style: styled),
          TextSpan(text: 'מילה ' * 4000),
        ],
      );
      final split = splitLongLine(span)!;

      expect(split.chunks.length, greaterThan(1));
      final styledLeaves = [
        for (final chunk in split.chunks)
          for (final leaf in chunk.children!.cast<TextSpan>())
            if (leaf.style != null) leaf,
      ];
      expect(styledLeaves, hasLength(1));
      expect(styledLeaves.single.text, bold);
    });

    test('אין חיתוך בתוך בידוד או הטבעה כיווניים', () {
      // LRI ו-RLO פתוחים לאורך יותר ממקטע שלם; רק אחרי PDI ו-PDF מותר לחתוך.
      final isolated = '\u2066${'abc ' * 6000}\u2069';
      final embedded = '\u202E${'abc ' * 6000}\u202C';
      final span = TextSpan(
        text:
            '${'מילה ' * 3000}$isolated ${'מילה ' * 3000}$embedded '
            '${'מילה ' * 3000}',
      );
      final split = splitLongLine(span)!;
      final text = split.text;

      expect(split.chunks.length, greaterThan(1));
      for (final start in split.starts.skip(1)) {
        var depth = 0;
        for (final c in text.substring(0, start).codeUnits) {
          if ((c >= 0x2066 && c <= 0x2068) ||
              (c >= 0x202A && c <= 0x202E && c != 0x202C)) {
            depth++;
          } else if ((c == 0x2069 || c == 0x202C) && depth > 0) {
            depth--;
          }
        }
        expect(depth, 0, reason: 'cut at $start');
      }
    });

    test('מקטע אינו מתחיל בסימן צירוף', () {
      // כמעט כל רווח מוביל לניקוד "יתום"; החיתוך חייב לדלג עליו.
      final span = TextSpan(text: '${'אב ָ' * 50}גד ' * 400);
      final parts = texts(splitLongLine(span)!);
      final mark = RegExp(r'^\p{M}', unicode: true);

      expect(parts.length, greaterThan(1));
      expect(parts.join(), span.toPlainText());
      for (final part in parts.skip(1)) {
        expect(mark.hasMatch(part), isFalse);
      }
    });

    test('סוף משפט מזוהה רק לפי ארבעת סימני הפיסוק באותו ספאן', () {
      final prefix = '${'א' * (kLongLineChunkChars - 1)} ';
      final tail = 'ב' * kLongLineChunkChars;
      for (final (marker, sentence) in [
        ('.', true),
        (':', true),
        ('?', true),
        ('!', true),
        ('א', false),
        ('\uD800', false),
        ('\uDC00', false),
        ('😀', false),
      ]) {
        final text = '$prefixא$marker $tail';
        final split = splitLongLine(TextSpan(text: text))!;
        expect(
          split.starts,
          [0, sentence ? prefix.length + 2 + marker.length : prefix.length],
        );
        expect(split.chunks.map((chunk) => chunk.toPlainText()).join(), text);
      }
      final split = splitLongLine(
        TextSpan(
          children: [
            TextSpan(text: '$prefixא.'),
            TextSpan(text: ' $tail'),
          ],
        ),
      )!;
      expect(split.starts, [0, prefix.length]);
    });

    test('מועמדי משפט שנפסלו אינם נבדקים שוב בחיפוש הרווח החלופי', () {
      final prefix = 'א' * (kLongLineChunkChars - 2);
      final rejected = '. \u05B0' * 1000;
      final text = '$prefix$rejected סוף ${'א' * kLongLineChunkChars}';
      debugMarkChecks = 0;
      final split = splitLongLine(TextSpan(text: text))!;

      expect(debugMarkChecks, 1001);
      expect(split.starts, [0, prefix.length + rejected.length + 1]);
      expect(split.chunks.map((chunk) => chunk.toPlainText()).join(), text);
    });

    test('בדיקת סימן צירוף רצה רק בחלונות הבחירה ולא בכל רווח', () {
      final text = List.filled(60000, 'מילה\u05B0 \u05B1מילה').join(' ');
      final spaces = ' '.allMatches(text).length;
      debugMarkChecks = 0;
      final split = splitLongLine(TextSpan(text: text))!;

      expect(debugMarkChecks, lessThan(spaces ~/ 20));
      final mark = RegExp(r'^\p{M}', unicode: true);
      for (final start in split.starts.skip(1)) {
        expect(mark.hasMatch(text.substring(start)), isFalse);
        expect(text[start - 1], ' ');
      }
    });
  });

  test('שורה ארוכה מאוד היא בלוק גם במצב רציף', () {
    expect(isReaderBlockLine('א' * (kLongLineMinChars + 1)), isTrue);
    expect(isReaderBlockLine('שורה רגילה'), isFalse);
  });

  testWidgets('שורה ארוכה נפרסת במקטעים, כמה בכל פריים, עד הטקסט המלא', (
    tester,
  ) async {
    final line = _syntheticLine(120000);
    await tester.pumpWidget(
      _host(SmartTextWidget(text: line, settings: _settings)),
    );

    final first = _paragraphs(tester);
    expect(first.length, kLongLineChunksPerFrame);
    for (final paragraph in first) {
      expect(
        paragraph.text.toPlainText().length,
        lessThan(kLongLineChunkChars * 2),
      );
    }

    await tester.pumpAndSettle();
    final all = _paragraphs(tester);
    expect(all.length, greaterThan(kLongLineChunksPerFrame));
    final plain = _textOf(tester);
    expect(plain.length, greaterThan(100000));
    expect(plain, isNot(contains('<')));
    expect(plain, contains('מודגש בתוך השורה'));
  });

  testWidgets('שורה ארוכה שירדה מהעץ באמצע הבנייה אינה מעכבת ניווט', (
    tester,
  ) async {
    // בלי פריים נוסף: המתנה שנשארה פתוחה הייתה מעכבת כל קפיצה בכל ספר.
    Future<bool> builtWithoutFrame() async {
      var done = false;
      unawaited(longLinesBuilt().then((_) => done = true));
      await tester.idle();
      return done;
    }

    await tester.pumpWidget(
      _host(SmartTextWidget(text: _syntheticLine(120000), settings: _settings)),
    );
    expect(await builtWithoutFrame(), isFalse);
    await tester.pumpWidget(_host(const SizedBox()));
    expect(await builtWithoutFrame(), isTrue);
  });

  testWidgets('ביטול ניווט מפסיק המתנה גם כשהשורה עדיין נבנית', (tester) async {
    await tester.pumpWidget(
      _host(SmartTextWidget(text: _syntheticLine(120000), settings: _settings)),
    );
    var current = true;
    var finished = false;
    final waiting = longLinesBuilt(isCurrent: () => current).then((waited) {
      finished = true;
      return waited;
    });
    await tester.idle();
    expect(finished, isFalse);
    current = false;
    await tester.pump();
    expect(finished, isTrue);
    expect(await waiting, isTrue);
    expect(_textOf(tester).length, lessThan(100000));
    await tester.pumpWidget(_host(const SizedBox()));
    expect(await longLinesBuilt(), isFalse);
  });

  testWidgets('בחירת הכול מעתיקה את טקסט השורה כולו, בלי תוספות בין מקטעים', (
    tester,
  ) async {
    final line = _syntheticLine(60000);
    SelectedContent? selection;
    await tester.pumpWidget(
      _host(
        SmartTextWidget(text: line, settings: _settings),
        onSelectionChanged: (content) => selection = content,
      ),
    );
    await tester.pumpAndSettle();
    final expected = _textOf(tester);

    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    expect(selection?.plainText, expected);
  });

  testWidgets('הדגשת חיפוש מסומנת גם במקטע שאינו הראשון', (tester) async {
    final line = _syntheticLine(60000, markersAt: const [0.7]);
    await tester.pumpWidget(
      _host(
        SmartTextWidget(
          text: line,
          settings: _settings.copyWith(searchText: _marker),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paragraphs = _paragraphs(tester);
    final withMarker = paragraphs.indexWhere(
      (p) => p.text.toPlainText().contains(_marker),
    );
    expect(withMarker, greaterThan(0));
    TextStyle? markerStyle;
    paragraphs[withMarker].text.visitChildren((span) {
      if (span is TextSpan && span.text == _marker) markerStyle = span.style;
      return markerStyle == null;
    });
    expect(markerStyle?.color ?? markerStyle?.background?.color, isNotNull);
  });

  testWidgets('אופסט הלחיצה ומופע הבחירה יחסיים לשורה כולה, לא למקטע', (
    tester,
  ) async {
    final line = _syntheticLine(60000, markersAt: const [0.05, 0.8]);
    final key = GlobalKey();
    await tester.pumpWidget(
      _host(SmartTextWidget(key: key, text: line, settings: _settings)),
    );
    await tester.pumpAndSettle();

    final paragraphs = _paragraphs(tester);
    final lineText = _textOf(tester);
    final second = lineText.lastIndexOf(_marker);
    expect(second, greaterThan(lineText.indexOf(_marker)));

    var chunkStart = 0;
    late RenderParagraph target;
    for (final paragraph in paragraphs) {
      final length = paragraph.text.toPlainText().length;
      if (second < chunkStart + length) {
        target = paragraph;
        break;
      }
      chunkStart += length;
    }
    expect(chunkStart, greaterThan(0));

    final local = second - chunkStart;
    final box = target
        .getBoxesForSelection(
          TextSelection(baseOffset: local + 2, extentOffset: local + 3),
        )
        .first
        .toRect();
    final global = target.localToGlobal(box.center);
    final root = tester.renderObject(find.byKey(key));

    final column = renderedTextOffsetAtPosition(
      root: root,
      globalPosition: global,
    );
    expect(column, inInclusiveRange(second + 2, second + 3));

    final start = renderedSelectionStartAtPosition(
      root: root,
      globalPosition: global,
      selectedSegment: _marker,
    );
    expect(start, second);

    expect(
      clickIsOnRenderedSelection(
        root: root,
        globalPosition: global,
        selectedSegment: _marker,
        edge: SelectionSegmentEdge.substring,
        segmentStartHint: second,
      ),
      isTrue,
    );
    expect(
      clickIsOnTextOccurrence(
        root: root,
        globalPosition: global,
        text: _marker,
        occurrenceIndex: 1,
        occurrenceCount: 2,
      ),
      isTrue,
    );
    expect(
      clickIsOnTextOccurrence(
        root: root,
        globalPosition: global,
        text: _marker,
        occurrenceIndex: 0,
        occurrenceCount: 2,
      ),
      isFalse,
    );
    // בחירה שכולה במקטע הראשון: לחיצה במקטע מאוחר היא מחוץ לבחירה.
    expect(
      clickIsOnRenderedSelection(
        root: root,
        globalPosition: global,
        selectedSegment: lineText.substring(0, 20),
        edge: SelectionSegmentEdge.prefix,
      ),
      isFalse,
    );
  });
}
