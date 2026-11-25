import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/widgets/selection/item_selection_container.dart';
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

    test('ספאן מעוצב ארוך נחתך רק כשאין בחלון רווח רגיל, וכל חלק מעוצב', () {
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

      expect(split.chunks.map((c) => c.toPlainText()).join(), split.text);
      // בחלון הראשון יש רווח רגיל, ולכן הוא נבחר.
      expect(split.starts[1], lessThan(20000));
      final styledLeaves = [
        for (final chunk in split.chunks)
          for (final leaf in chunk.children!.cast<TextSpan>())
            if (leaf.style != null) leaf,
      ];
      expect(styledLeaves.length, greaterThan(1));
      for (final leaf in styledLeaves) {
        expect(leaf.style, same(styled));
      }
      expect(styledLeaves.map((leaf) => leaf.text).join(), bold);
    });

    test('רווח רגיל בחלון עדיף על רווח בתוך ספאן מעוצב', () {
      final span = TextSpan(
        children: [
          TextSpan(text: 'מילה ' * 3000),
          TextSpan(
            text: 'מודגש ' * 500,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: 'מילה ' * 12000),
        ],
      );
      expect(splitLongLine(span)!.starts[1], 18000);
    });

    test('ספאן שנחתך שומר כל שדה של TextSpan במקטעים', () {
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      void onEnter(PointerEnterEvent _) {}
      void onExit(PointerExitEvent _) {}
      const style = TextStyle(color: Color(0xFF123456));
      const locale = Locale('he', 'IL');
      final special = TextSpan(
        text: 'קישור ' * 8000,
        style: style,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
        onEnter: onEnter,
        onExit: onExit,
        semanticsIdentifier: 'id-5906',
        locale: locale,
        spellOut: true,
      );
      final split = splitLongLine(
        TextSpan(
          children: [
            TextSpan(text: 'מילה ' * 4000),
            special,
          ],
        ),
      )!;

      final pieces = [
        for (final chunk in split.chunks)
          for (final child in chunk.children!.cast<TextSpan>())
            if (child.recognizer != null) child,
      ];
      expect(pieces.length, greaterThan(1));
      expect(pieces.map((piece) => piece.text).join(), special.text);
      for (final piece in pieces) {
        expect(piece.style, same(style));
        expect(piece.recognizer, same(recognizer));
        expect(piece.mouseCursor, SystemMouseCursors.click);
        expect(piece.onEnter, same(onEnter));
        expect(piece.onExit, same(onExit));
        expect(piece.semanticsIdentifier, 'id-5906');
        expect(piece.locale, locale);
        expect(piece.spellOut, isTrue);
      }
      // בחלון הראשון יש רווח מחוץ לקישור, ולכן הוא נבחר.
      expect(split.starts[1], lessThanOrEqualTo(20000));
    });

    test('עץ מקונן נחתך עם שרשרת האבות, ו-WidgetSpan נשאר שלם ויחיד', () {
      const outer = TextStyle(fontSize: 18);
      const inner = TextStyle(fontWeight: FontWeight.bold);
      const widget = WidgetSpan(child: SizedBox(width: 4, height: 4));
      final span = TextSpan(
        style: outer,
        children: [
          TextSpan(
            style: inner,
            children: [
              TextSpan(text: 'מילה ' * 5000),
              widget,
              TextSpan(text: 'מילה ' * 5000),
            ],
          ),
        ],
      );
      final split = splitLongLine(span)!;

      expect(split.chunks.length, greaterThan(2));
      expect(split.text, span.toPlainText(includeSemanticsLabels: false));
      expect(
        split.chunks
            .map((c) => c.toPlainText(includeSemanticsLabels: false))
            .join(),
        split.text,
      );
      var widgets = 0;
      for (final chunk in split.chunks) {
        expect(chunk.style, same(outer));
        expect((chunk.children!.single as TextSpan).style, same(inner));
        chunk.visitChildren((child) {
          if (identical(child, widget)) widgets++;
          return true;
        });
      }
      expect(widgets, 1);
    });

    test('אין חיתוך בתוך ספאן עם תווית נגישות', () {
      final split = splitLongLine(
        TextSpan(
          children: [
            TextSpan(text: 'מילה ' * 4000),
            TextSpan(text: 'מסומן ' * 7000, semanticsLabel: 'תווית'),
            TextSpan(text: 'מילה ' * 4000),
          ],
        ),
      )!;

      for (final start in split.starts.skip(1)) {
        expect(start, isNot(inExclusiveRange(20000, 62000)));
      }
      final labeled = [
        for (final chunk in split.chunks)
          for (final child in chunk.children!.cast<TextSpan>())
            if (child.semanticsLabel != null) child,
      ];
      expect(labeled, hasLength(1));
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

  testWidgets('שורה מודגשת כולה מפוצלת במסלול המהיר', (tester) async {
    final words = 'מודגש ' * 8000;
    await tester.pumpWidget(
      _host(SmartTextWidget(text: '<b>$words</b>', settings: _settings)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HtmlWidget), findsNothing);
    expect(find.byType(LongLineChunks), findsOneWidget);
    final paragraphs = _paragraphs(tester);
    expect(paragraphs.length, greaterThan(1));
    expect(_textOf(tester).trim(), words.trim());
    for (final paragraph in paragraphs) {
      TextStyle? leafStyle;
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) leafStyle = span.style;
        return leafStyle == null;
      });
      expect(leafStyle?.fontWeight, FontWeight.bold);
    }
  });

  testWidgets('כותרת ארוכה מפוצלת ושומרת את סגנון הכותרת', (tester) async {
    final words = 'כותרת ארוכה ' * 3500;
    await tester.pumpWidget(
      _host(SmartTextWidget(text: '<h2>$words</h2>', settings: _settings)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HtmlWidget), findsNothing);
    expect(find.byType(LongLineChunks), findsOneWidget);
    final paragraphs = _paragraphs(tester);
    expect(paragraphs.length, greaterThan(1));
    expect(_textOf(tester).trim(), words.trim());
    for (final paragraph in paragraphs) {
      expect(paragraph.text.style?.fontSize, greaterThan(_settings.fontSize));
    }
  });

  testWidgets('קישור שנחתך בין מקטעים פועל בשני חלקיו', (tester) async {
    final taps = <int>[];
    final line =
        '${'מילה ' * 3000}<a href="otzaria://note?line=7">'
        '${'קישור ' * 6000}</a> ${'מילה ' * 3000}';
    await tester.pumpWidget(
      _host(
        SmartTextWidget(text: line, settings: _settings, onNoteTap: taps.add),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HtmlWidget), findsNothing);
    final paragraphs = _paragraphs(tester);
    expect(paragraphs.length, greaterThan(2));
    Future<Offset> linkWord(RenderParagraph paragraph, {required bool last}) {
      final text = paragraph.text.toPlainText();
      final index = last ? text.lastIndexOf('קישור') : text.indexOf('קישור');
      expect(index, greaterThanOrEqualTo(0));
      return _reveal(tester, paragraph, index + 2);
    }

    final first = paragraphs.indexWhere(
      (p) => p.text.toPlainText().contains('קישור'),
    );
    await tester.tapAt(await linkWord(paragraphs[first], last: true));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(await linkWord(paragraphs[first + 1], last: false));
    await tester.pump(const Duration(milliseconds: 500));

    expect(taps, [7, 7]);
  });

  testWidgets('לחיצה משולשת בשורה בלי שבירות בוחרת את כל המקטעים', (
    tester,
  ) async {
    SelectedContent? selection;
    await tester.pumpWidget(
      _host(
        SmartTextWidget(text: _syntheticLine(60000), settings: _settings),
        onSelectionChanged: (content) => selection = content,
      ),
    );
    await tester.pumpAndSettle();
    final paragraphs = _paragraphs(tester);
    expect(paragraphs.length, greaterThan(2));

    await _click(tester, await _reveal(tester, paragraphs[1], 200), 3);

    expect(selection?.plainText, _textOf(tester));
  });

  for (final inItem in [false, true]) {
    testWidgets(
      'לחיצה משולשת בוחרת את הפסקה שחוצה מקטעים, ורק אותה'
      '${inItem ? ' (פריט קורא)' : ''}',
      (tester) async {
        SelectedContent? selection;
        final line = [
          for (final (name, count) in [
            ('ראשונה', 3000),
            ('שנייה', 4000),
            ('שלישית', 1000),
          ])
            '${'פסקה $name ' * count}סוף',
        ].join('<br>');
        final text = SmartTextWidget(text: line, settings: _settings);
        await tester.pumpWidget(
          _host(
            inItem ? ItemSelectionContainer(child: text) : text,
            onSelectionChanged: (content) => selection = content,
          ),
        );
        await tester.pumpAndSettle();
        final paragraphs = _paragraphs(tester);
        final lineText = longLineChunkOf(paragraphs.first)!.lineText;
        final second = lineText.split('\n')[1];
        // מקטע שכולו בתוך הפסקה השנייה, שמתחילה במקטע קודם.
        final inside = paragraphs.indexWhere((paragraph) {
          final start = longLineChunkOf(paragraph)!.start;
          final end = start + paragraph.text.toPlainText().length;
          return lineText.substring(0, start).contains('\n') &&
              !lineText.substring(start, end).contains('\n');
        });
        expect(inside, greaterThan(1));

        await _click(tester, await _reveal(tester, paragraphs[inside], 100), 3);

        expect(selection?.plainText, '$second\n');
      },
    );
  }
}

/// גולל את התו ב-[offset] אל המסך ומחזיר את מרכזו.
Future<Offset> _reveal(
  WidgetTester tester,
  RenderParagraph paragraph,
  int offset,
) async {
  Offset center() => paragraph.localToGlobal(
    paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        )
        .first
        .toRect()
        .center,
  );
  final position = tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;
  position.jumpTo(position.pixels + center().dy - 300);
  await tester.pump();
  return center();
}

Future<void> _click(WidgetTester tester, Offset position, int count) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
  );
  for (var i = 0; i < count; i++) {
    if (i > 0) await gesture.down(position);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.removePointer();
  await tester.pump(const Duration(milliseconds: 500));
}
