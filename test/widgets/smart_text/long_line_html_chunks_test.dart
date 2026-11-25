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
      }
      final joined = texts.join();
      expect(joined.length, greaterThan(60000));
      expect(joined, chunks.first.lineText);
      _expectItemsInOrder(joined, 0, count);
      expect('מודגש באמצע'.allMatches(joined), hasLength(count ~/ 97 + 1));

      // העוגן הוא WidgetSpan עם GlobalKey בתחילת המקטע הראשון.
      expect(joined.indexOf('￼'), 0);
      expect('￼'.allMatches(joined), hasLength(1));

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

    final joined = _chunks(
      tester,
    ).map((chunk) => _plain(_paragraphOf(chunk))).join();
    _expectItemsInOrder(joined, 0, 4400);
    expect(
      '￼'.allMatches(joined),
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
    final expected = chunks.first.lineText.replaceAll('￼', '');

    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    expect(selection?.plainText, expected);
  });
}
