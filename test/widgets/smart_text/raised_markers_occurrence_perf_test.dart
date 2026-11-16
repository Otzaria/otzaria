import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';

/// ספירת ייחוס: האלגוריתם הישן — סריקה מראש הטקסט הגלוי לכל סימון.
List<int> _referenceOccurrences(String visible, List<(int, String)> markers) {
  return [
    for (final (end, text) in markers)
      () {
        final before = visible.substring(0, end);
        var count = 0;
        var from = 0;
        while (true) {
          final idx = before.indexOf(text, from);
          if (idx < 0) break;
          count++;
          from = idx + text.length;
        }
        return count + 1;
      }(),
  ];
}

String _marker(String text) => '<span class="$kRaisedSupClass">$text</span>';

void main() {
  setUp(RaisedMarkers.clearCacheForTesting);

  test('מספרי המופע זהים לספירה מראש הטקסט, כולל חפיפה וחציית גבול סימן', () {
    final body = StringBuffer();
    final visible = StringBuffer();
    final markers = <(int, String)>[];
    const texts = ['אא', 'א', 'אבא', 'ב'];
    for (var i = 0; i < 300; i++) {
      final text = texts[(i * 7 + i ~/ 3) % texts.length];
      final filler = i % 3 == 0 ? 'א' : (i % 3 == 1 ? 'אב' : 'ב ');
      body.write(filler);
      visible.write(filler);
      body.write(_marker(text));
      markers.add((visible.length, text));
      visible.write(text);
    }
    final expected = _referenceOccurrences(visible.toString(), markers);

    final actual = RaisedMarkers.extract(body.toString());

    expect(actual.map((m) => m.text), markers.map((m) => m.$2));
    expect(actual.map((m) => m.occurrence), expected);
  });

  test('שורה ארוכה עם מאות סימנים נחלצת בזמן קצר', () {
    final body = StringBuffer();
    for (var i = 0; i < 1600; i++) {
      body.write('ויאמר אלהים ' * 20);
      body.write(_marker('א'));
    }
    final html = body.toString();

    final stopwatch = Stopwatch()..start();
    final markers = RaisedMarkers.extract(html);
    stopwatch.stop();

    expect(markers.length, 1600);
    expect(markers.last.occurrence, greaterThan(1600));
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });

  testWidgets('מיקומי הסימונים ברשימה מלאה זהים לאיתור של כל סימון לבדו', (
    tester,
  ) async {
    const texts = ['א', 'אא', 'אבא', 'ב'];
    final counters = {for (final t in texts) t: 0};
    final markers = <RaisedMarker>[];
    for (var i = 0; i < 60; i++) {
      final text = texts[(i * 5 + i ~/ 4) % texts.length];
      // כולל חזרה לאחור ומופע שאינו קיים בטקסט.
      final occurrence = i % 7 == 0
          ? 1
          : (i % 11 == 0
                ? counters[text]! + 3
                : counters[text] = counters[text]! + 1);
      markers.add(
        RaisedMarker(
          text: text,
          occurrence: occurrence,
          scale: 1,
          italic: false,
        ),
      );
    }

    Future<List<RaisedMarkerPlacement>> placementsOf(
      List<RaisedMarker> markers,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: RaisedMarkerOverlay(
            markers: markers,
            baseStyle: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
            child: Column(
              children: [
                Text('אאא ב אבאבא ' * 6),
                Text('בא אא אבא ' * 6),
              ],
            ),
          ),
        ),
      );
      return tester
          .renderObject<RenderRaisedMarkerOverlay>(
            find.byType(RaisedMarkerOverlay),
          )
          .debugPlacements();
    }

    String describe(RaisedMarkerPlacement p) =>
        '${p.text}#${p.marker.occurrence}@${p.anchorRect}';

    final expected = [
      for (final marker in markers) ...await placementsOf([marker]),
    ].map(describe).toList();
    final actual = (await placementsOf(markers)).map(describe).toList();

    expect(expected.length, greaterThan(40));
    expect(actual, expected);
  });
}
