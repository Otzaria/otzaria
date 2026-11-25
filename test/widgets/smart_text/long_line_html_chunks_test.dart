import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// שורה בצורת ספר שהומר ממסמך (#5906): בלוק מיושר עם עוגן, שבירות, הדגשות.
const _marker = 'סמןייחודי';
const _settings = RenderSettings(fontSize: 16, lineHeight: 1.5);

// PNG שקוף 1x1.
const _img =
    '<img width="20" height="20" src="data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=">';

/// [count] פריטים ממוספרים מ-[from]; כל אחד מופיע בטקסט כ-`קטע<n> `.
String _items(int from, int count, {int? markerAt, String? inlineAt}) {
  final out = StringBuffer();
  for (var i = from; i < from + count; i++) {
    if (i == markerAt) out.write('$_marker ');
    if (inlineAt != null && i == from + count ~/ 2) out.write('$inlineAt ');
    out.write('קטע$i מילה ועוד ');
    if (i % 97 == 0) out.write('<b>מודגש באמצע</b> ');
    if (i % 23 == 0) out.write('סוף. ');
    if (i % 40 == 39) out.write('<br>');
  }
  return out.toString();
}

String _block(String content) =>
    '<div style="text-align: justify"><a id="anchor-5906"></a>$content</div>';

Widget _host(
  String html, {
  RenderSettings settings = _settings,
  ValueChanged<SelectedContent?>? onSelectionChanged,
}) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SelectionArea(
        onSelectionChanged: onSelectionChanged,
        child: ListView(
          children: [
            SizedBox(
              width: 600,
              child: SmartTextWidget(text: html, settings: settings),
            ),
          ],
        ),
      ),
    ),
  ),
);

List<RenderLongLineChunk> _chunks(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLongLineChunk>().toList();

RenderParagraph _paragraphOf(RenderLongLineChunk chunk) {
  RenderParagraph? found;
  void visit(RenderObject node) {
    if (found != null) return;
    if (node is RenderParagraph) {
      found = node;
    } else {
      node.visitChildren(visit);
    }
  }

  chunk.visitChildren(visit);
  return found!;
}

String _plain(RenderParagraph paragraph) =>
    paragraph.text.toPlainText(includeSemanticsLabels: false);

/// טקסט המקטעים עם השבירות שהושמטו ביניהם.
String _joined(List<RenderLongLineChunk> chunks) => [
  for (final chunk in chunks) chunk.skipped + _plain(_paragraphOf(chunk)),
].join();

/// כל פריט מופיע פעם אחת ובסדר.
void _expectItemsInOrder(String text, int from, int count) {
  var at = 0;
  for (var i = from; i < from + count; i++) {
    final index = text.indexOf('קטע$i ', at);
    expect(index, greaterThanOrEqualTo(0), reason: 'קטע$i חסר או לא בסדר');
    at = index + 1;
  }
}

void main() {
  testWidgets(
    'שורת HTML ארוכה (#5906) נפרסת במקטעים: פריים ראשון מקטע אחד, כל הטקסט, '
    'ההדגשה והעוגן נשמרים',
    (tester) async {
      const count = 3600;
      final html = _block(_items(0, count, markerAt: 2500));
      await tester.pumpWidget(
        _host(html, settings: _settings.copyWith(searchText: _marker)),
      );

      expect(find.byType(HtmlWidget), findsOneWidget);
      expect(find.byType(LongLineChunks), findsOneWidget);
      // רק מקטע אחד נפרס בפריים הראשון.
      expect(_chunks(tester), hasLength(1));
      expect(
        tester.allRenderObjects.whereType<RenderParagraph>().where(
          (p) => _plain(p).length > 1000,
        ),
        hasLength(1),
      );

      await tester.pumpAndSettle();
      final chunks = _chunks(tester);
      expect(chunks.length, greaterThan(2));
      final texts = [for (final chunk in chunks) _plain(_paragraphOf(chunk))];
      for (final text in texts) {
        expect(text.length, lessThan(kLongLineChunkChars * 2));
        expect(text, isNot(startsWith('\n')));
        expect(text, isNot(endsWith('\n')));
      }
      final joined = _joined(chunks);
      expect(joined.length, greaterThan(60000));
      expect(joined, chunks.first.lineText);
      // כל חיתוך כאן בשבירה קשיחה, ששוחזרה בין המקטעים.
      for (final chunk in chunks.skip(1)) {
        expect(chunk.skipped, '\n');
      }
      _expectItemsInOrder(joined, 0, count);
      expect('מודגש באמצע'.allMatches(joined), hasLength(count ~/ 97 + 1));

      // העוגן הוא WidgetSpan עם GlobalKey בתחילת המקטע הראשון.
      expect(joined.indexOf('\uFFFC'), 0);
      expect('\uFFFC'.allMatches(joined), hasLength(1));

      final withMarker = chunks.indexWhere(
        (c) => _plain(_paragraphOf(c)).contains(_marker),
      );
      expect(withMarker, greaterThan(0));
      final markerParagraph = _paragraphOf(chunks[withMarker]);
      TextStyle? markerStyle;
      markerParagraph.text.visitChildren((span) {
        if (span is TextSpan && span.text == _marker) markerStyle = span.style;
        return markerStyle == null;
      });
      expect(markerStyle?.color, isNotNull);
      expect(markerStyle!.color, isNot(markerParagraph.text.style?.color));
    },
  );

  testWidgets('תמונה ו-details בתוך שורת HTML ארוכה נשמרים', (tester) async {
    final html = _block(
      '${_items(0, 2200, inlineAt: _img)}'
      '<details><summary>תקציר</summary>תוכן נסתר</details>'
      '${_items(2200, 2200)}',
    );
    await tester.pumpWidget(_host(html));
    await tester.pumpAndSettle();

    expect(find.byType(HtmlWidget), findsOneWidget);
    expect(find.byType(LongLineChunks), findsNWidgets(2));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(HtmlDetails), findsOneWidget);
    expect(
      tester.allRenderObjects.whereType<RenderParagraph>().where(
        (p) => _plain(p).contains('תקציר'),
      ),
      hasLength(1),
    );

    final joined = _joined(_chunks(tester));
    _expectItemsInOrder(joined, 0, 4400);
    expect(
      '\uFFFC'.allMatches(joined),
      hasLength(2),
      reason: 'עוגן ותמונה',
    );
  });

  for (final (name, html) in [
    ('pre', '<pre>${'שורה בלי שבירה ' * 4000}</pre>'),
    (
      'מגבלת שורות',
      '<div style="max-lines: 2; text-overflow: ellipsis">'
          '${_items(0, 3000)}</div>',
    ),
    ('nowrap', '<div style="white-space: nowrap">${_items(0, 3000)}</div>'),
    ('טבלה', '<table><tr><td>${_items(0, 3000)}</td></tr></table>'),
    ('רשימה', '<ul><li>${_items(0, 3000)}</li></ul>'),
  ]) {
    testWidgets('$name אינו מפוצל למקטעים', (tester) async {
      await tester.pumpWidget(_host(html));
      await tester.pumpAndSettle();

      expect(find.byType(HtmlWidget), findsOneWidget);
      expect(find.byType(LongLineChunks), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('בחירת הכול בשורת HTML מפוצלת מעתיקה את כל הטקסט בסדר', (
    tester,
  ) async {
    SelectedContent? selection;
    await tester.pumpWidget(
      _host(
        _block(_items(0, 3000)),
        onSelectionChanged: (content) => selection = content,
      ),
    );
    await tester.pumpAndSettle();
    final chunks = _chunks(tester);
    expect(chunks.length, greaterThan(2));
    final expected = chunks.first.lineText.replaceAll('\uFFFC', '');

    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    expect(selection?.plainText, expected);
  });

  testWidgets('הדגשה חדשה בשורת HTML מוחלפת מקטע אחד בכל פריים, בלי הסתרה', (
    tester,
  ) async {
    final html = _block(_items(0, 6000, markerAt: 3000));
    final settings = ValueNotifier(_settings);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SelectionArea(
              child: ListView(
                children: [
                  SizedBox(
                    width: 600,
                    child: ValueListenableBuilder(
                      valueListenable: settings,
                      builder: (context, value, _) =>
                          SmartTextWidget(text: html, settings: value),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // פסקה שה-RichText שלה נבנה מחדש עשויה להיפרס מחדש; האחרות לא.
    List<Widget> texts() => tester
        .widgetList(
          find.descendant(
            of: find.byType(LongLineChunks),
            matching: find.byWidgetPredicate((widget) => widget is RichText),
          ),
        )
        .toList();
    var before = texts();
    final count = before.length;
    expect(count, greaterThan(4));

    settings.value = _settings.copyWith(searchText: _marker);
    var frames = 0;
    var changedTotal = 0;
    while (changedTotal < count && frames < count * 3) {
      await tester.pump();
      frames++;
      final now = texts();
      expect(now, hasLength(count), reason: 'אין מקטע מוסתר באמצע');
      var changed = 0;
      for (var i = 0; i < count; i++) {
        if (!identical(now[i], before[i])) changed++;
      }
      expect(changed, lessThanOrEqualTo(kLongLineChunksPerFrame));
      changedTotal += changed;
      before = now;
    }
    expect(changedTotal, count);
    expect(
      _joined(_chunks(tester)),
      contains(_marker),
    );
  });

  testWidgets('קישור #id לעוגן במקטע שעוד לא נבנה ממתין לבנייה וגולל אליו', (
    tester,
  ) async {
    final html =
        '<div style="text-align: justify"><a href="#late">לסוף</a> '
        '${_items(0, 6000)}<a id="late"></a>סוף השורה</div>';
    await tester.pumpWidget(_host(html));
    expect(_chunks(tester), hasLength(1));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, 0);

    final link = _chunks(tester).first;
    final paragraph = _paragraphOf(link);
    final box = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 1, extentOffset: 3),
        )
        .first
        .toRect();
    await tester.tapAt(paragraph.localToGlobal(box.center));
    await tester.pumpAndSettle();

    expect(_chunks(tester).length, greaterThan(4));
    expect(scrollable.position.pixels, greaterThan(1000));
  });

  testWidgets('חיתוך בשבירה אחרי רווח אינו מוסיף שורה ריקה לאף מקטע', (
    tester,
  ) async {
    // fwfh משאיר רווח לפני <br>, ולכן " \n" נפוץ בגבול.
    final html =
        '<div style="text-align: justify">${'מילה ' * 3200}<br>'
        '${'מילה ' * 5000}</div>';
    await tester.pumpWidget(_host(html));
    await tester.pumpAndSettle();
    final chunks = _chunks(tester);
    expect(chunks.length, greaterThanOrEqualTo(2));
    expect(chunks[1].skipped, '\n');
    final first = _paragraphOf(chunks[0]);
    final second = _paragraphOf(chunks[1]);
    expect(_plain(second), isNot(startsWith('\n')));
    expect(_plain(first), isNot(endsWith('\n')));

    final whole = TextPainter(
      text: TextSpan(
        children: [
          first.text,
          TextSpan(text: '\n', style: first.text.style),
          second.text,
        ],
      ),
      textDirection: first.textDirection,
      textAlign: first.textAlign,
      strutStyle: first.strutStyle,
      textScaler: first.textScaler,
    )..layout(maxWidth: first.size.width);
    addTearDown(whole.dispose);
    expect(
      first.size.height + second.size.height,
      moreOrLessEquals(whole.height),
    );
  });
}
