import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/selection/commentary_copy_guard.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

Link link(
  int first, {
  int? last,
  int? id = 1,
  int? category,
  BookSource source = BookSource.official,
}) => Link(
  heRef: 'ref',
  index1: 1,
  path2: 'מפרש.txt',
  index2: first,
  index2End: last,
  targetBookId: id,
  targetCategoryId: category,
  targetSource: source,
  connectionType: 'COMMENTARY',
);

void main() {
  const settings = RenderSettings();
  const protected = BookProtection(level: 2);
  const limit = BookProtection.copySegmentLimit;
  const overLimit = limit + 1;
  Future<({BookProtection protection, int segmentCount})> guard(
    List<Link> links, {
    bool selectAll = true,
    CommentarySourceSelection? Function(Link)? selection,
    Future<List<String>> Function(Link)? read,
    Future<BookProtection> Function(Link)? protection,
  }) => buildCommentaryCopyGuard(
    links,
    selectAll: selectAll,
    selectionOf: selection ?? (_) => null,
    renderSettings: settings,
    sourceResolver: read,
    protectionResolver: protection ?? (_) async => protected,
  );

  test('קטע מוגן אחד ושישה חופשיים מותרים', () async {
    final result = await guard(
      [for (var i = 1; i <= 7; i++) link(i, id: i)],
      protection: (item) async =>
          item.targetBookId == 1 ? protected : BookProtection.none,
    );
    expect(result.segmentCount, 1);
    expect(result.protection.allowsCopyOf(result.segmentCount), isTrue);
  });

  test('שורות מעל המגבלה באותו ספר נאסרות גם בכמה קישורים', () async {
    final result = await guard([
      link(1, last: 3),
      link(4, last: overLimit, category: 7),
    ]);
    expect(result.segmentCount, overLimit);
    expect(result.protection.allowsCopyOf(result.segmentCount), isFalse);
  });

  test('טווחים חופפים באותו ספר נספרים פעם אחת', () async {
    expect((await guard([link(1, last: 4), link(3, last: 5)])).segmentCount, 5);
  });

  test('זהות ושם חופפים במסדים שונים מקבלים מכסות נפרדות', () async {
    final result = await guard([
      link(1, last: limit),
      link(limit + 1, last: 2 * limit, source: BookSource.attached('extra')),
    ]);
    expect(result.segmentCount, limit);
    expect(result.protection.allowsCopyOf(result.segmentCount), isTrue);
  });

  test('בחירה חלקית בשני פריטי טווח סופרת שורה אחת בכל אחד', () async {
    final result = await guard(
      [link(1, last: 10), link(11, last: 20)],
      selectAll: false,
      read: (item) async => [
        for (var i = item.index2; i <= item.index2End!; i++) '<p>שורה $i</p>',
      ],
      selection: (item) {
        final text = [
          for (var i = item.index2; i <= item.index2End!; i++) 'שורה $i',
        ].join(' ');
        final last = 'שורה ${item.index2End}';
        return (text: text, start: text.length, end: text.length - last.length);
      },
    );
    expect(result.segmentCount, 2);
  });

  test('בחירה הפוכה וטקסט שטוח מעל המגבלה לא עוקפים את ההגבלה', () async {
    var reads = 0;
    final text = [for (var i = 1; i <= overLimit; i++) 'שורה $i'].join(' ');
    final result = await guard(
      [link(1, last: overLimit)],
      selectAll: false,
      selection: (_) => (text: text, start: text.length, end: 0),
      read: (_) async {
        reads++;
        return [for (var i = 1; i <= overLimit; i++) 'שורה $i'];
      },
    );
    expect(reads, 0);
    expect(result.segmentCount, overLimit);
    expect(result.protection.allowsCopyOf(result.segmentCount), isFalse);
  });

  test('אי התאמה למקור אינה מתירה בחירת טווח ארוך', () async {
    final result = await guard(
      [link(1, last: overLimit)],
      selectAll: false,
      selection: (_) => (text: 'טקסט שטוח', start: 0, end: 10),
      read: (_) async => [],
    );
    expect(result.segmentCount, overLimit);
  });

  test('כשל קריאת מקור משאיר את טווח הספר המוגן מוגבל', () async {
    final result = await guard(
      [link(1, last: overLimit)],
      selectAll: false,
      selection: (_) => (text: 'מקור ארוך', start: 0, end: 4),
      read: (_) async => throw StateError('source unavailable'),
    );
    expect(result.segmentCount, overLimit);
    expect(result.protection.allowsCopyOf(result.segmentCount), isFalse);
  });

  testWidgets('המאזין מודד גוף נבחר ומוציא כותרת וביאור לעז חופשי', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: Column(
              key: key,
              children: const [
                Text('כותרת שאינה קטע מקור'),
                CommentarySelectionTracker(child: Text('גוף ראשון\nגוף שני')),
                Text('ביאור לעז חופשי'),
              ],
            ),
          ),
        ),
      ),
    );
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    await tester.pump();
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    final selection = CommentarySelectionTracker.selectionIn(key)!;
    expect(selection.text, 'גוף ראשון\nגוף שני');
    expect((selection.end - selection.start).abs(), selection.text.length);
    region.clearSelection();
    await tester.pump();
    expect(CommentarySelectionTracker.selectionIn(key), isNull);
  });
  testWidgets('בחירה חלקית בשני גופי מפרשים סופרת קטע מקור אחד בכל גוף', (
    tester,
  ) async {
    final keys = [GlobalKey(), GlobalKey()];
    final source = [
      [for (var i = 1; i <= 10; i++) 'קטע ראשון $i'],
      [for (var i = 11; i <= 20; i++) 'קטע שני $i'],
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: Column(
              children: [
                for (var i = 0; i < 2; i++)
                  Column(
                    key: keys[i],
                    children: [
                      const Text('כותרת שאינה קטע מקור'),
                      CommentarySelectionTracker(
                        child: Column(
                          children: [for (final line in source[i]) Text(line)],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      expect(
        CommentarySelectionTracker.selectionIn(keys[i])!.text,
        source[i].join(),
      );
    }
    region.clearSelection();
    await tester.pump();
    List<SelectionContainer> bodyContainers(GlobalKey key) => tester
        .widgetList<SelectionContainer>(
          find.descendant(
            of: find.descendant(
              of: find.byKey(key),
              matching: find.byType(CommentarySelectionTracker),
            ),
            matching: find.byType(SelectionContainer),
          ),
        )
        .toList();
    for (var i = 0; i < 2; i++) {
      final containers = bodyContainers(keys[i]);
      containers.first.delegate!.dispatchSelectionEvent(
        const SelectAllSelectionEvent(),
      );
      final paragraphs = containers.skip(1).toList();
      for (var j = 0; j < paragraphs.length; j++) {
        if (j != (i == 0 ? 9 : 0)) {
          paragraphs[j].delegate!.dispatchSelectionEvent(
            const ClearSelectionEvent(),
          );
        }
      }
    }
    await tester.pump();
    final selections = [
      for (final key in keys) CommentarySelectionTracker.selectionIn(key)!,
    ];
    expect(selections[0].start, source[0].take(9).join().length);
    expect(selections[0].end, source[0].join().length);
    expect(selections[1].start, 0);
    expect(selections[1].end, source[1].first.length);
    final items = [link(1, last: 10), link(11, last: 20)];
    for (var i = 0; i < 2; i++) {
      expect(
        selectedCommentarySourceSegments(items[i], selections[i], source[i]),
        {i == 0 ? 10 : 11},
      );
    }
    final result = await guard(
      items,
      selectAll: false,
      selection: (item) => selections[items.indexOf(item)],
      read: (item) async => source[items.indexOf(item)],
    );
    expect(result.segmentCount, 2);
  });
}
