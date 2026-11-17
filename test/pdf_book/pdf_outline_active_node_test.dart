import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_outline_page_lookup.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:pdfrx/pdfrx.dart';

class _ReadyController extends PdfViewerController {
  @override
  bool get isReady => true;

  @override
  int? get pageNumber => 1;
}

PdfOutlineNode _node(String title, int? page, [List<PdfOutlineNode>? kids]) =>
    PdfOutlineNode(
      title: title,
      dest: page == null ? null : PdfDest(page, PdfDestCommand.fit, null),
      children: kids ?? const [],
    );

void main() {
  final outline = [
    _node('הקדמה', 1),
    _node('פרק א', 5, [_node('סעיף א', 5), _node('סעיף ב', 9)]),
    _node('פרק ב', 20),
  ];
  final lookup = PdfOutlinePageLookup(outline);

  test('עמוד באמצע סעיף — הסעיף שהתחיל לפניו מודגש', () {
    expect(lookup.pathAt(12).firstOrNull?.title, 'סעיף ב');
    expect(lookup.pathAt(3).firstOrNull?.title, 'הקדמה');
  });

  test('עמוד שבו מתחיל סעיף — הסעיף העמוק ביותר', () {
    expect(lookup.pathAt(5).firstOrNull?.title, 'סעיף א');
    expect(lookup.pathAt(25).firstOrNull?.title, 'פרק ב');
  });

  test('לפני הסעיף הראשון — אין סעיף פעיל', () {
    expect(PdfOutlinePageLookup([_node('פרק א', 4)]).pathAt(2), isEmpty);
  });

  test('סעיף בלי יעד לא עוצר את הסריקה של אחיו', () {
    final withHole = [
      _node('פרק א', 1),
      _node('כותרת בלי יעד', null),
      _node('פרק ב', 10),
    ];
    expect(PdfOutlinePageLookup(withHole).pathAt(12), [withHole.last]);
  });

  test('יעדים כפולים, לא ממוינים וחסרים שומרים על סדר הסריקה', () {
    final hidden = _node('צאצא של כותרת ללא יעד', 1);
    final previous = _node('סעיף ראשון', 2);
    final late = _node('סעיף עם יעד מאוחר', 5);
    final duplicate = _node('כותרת עם יעד כפול', 2);
    final deepest = _node('סעיף פנימי', 1);
    final section = _node('סעיף', 1, [deepest]);
    final chapter = _node('פרק', 1, [
      previous,
      _node('כותרת ללא יעד', null, [hidden]),
      late,
      duplicate,
      section,
    ]);
    final newerChapter = _node('פרק אחר', 10);
    final lookup = PdfOutlinePageLookup([chapter, newerChapter]);

    expect(lookup.pathAt(10), [newerChapter]);
    expect(lookup.pathAt(4), [previous, chapter]);
    expect(lookup.pathAt(5), [deepest, section, chapter]);
    expect(lookup.pathAt(1), [chapter]);
    expect(lookup.pathAt(0), isEmpty);

    final duplicateLookup = PdfOutlinePageLookup([previous, duplicate]);
    expect(duplicateLookup.pathAt(2), [duplicate]);
  });

  test('האינדקס מחזיר נתיבי צמתים בעץ רחב במעברים קדימה ואחורה', () {
    final chapters = [
      for (var i = 1; i <= 100; i++)
        _node('פרק $i', i * 100, [
          for (var j = 0; j < 100; j++) _node('סעיף $j', i * 100 + j),
        ]),
    ];
    final lookup = PdfOutlinePageLookup(chapters);
    for (final page in [10099, 510, 9803, 100, 10000]) {
      final chapter = chapters[(page ~/ 100) - 1];
      expect(lookup.pathAt(page), [chapter.children[page % 100], chapter]);
    }
  });

  testWidgets('סעיף פעיל מסומן כשהתוכן מגיע אחרי שהעמוד מוכן', (tester) async {
    final controller = _ReadyController();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    Widget view(List<PdfOutlineNode>? nodes) => MaterialApp(
      home: Scaffold(
        body: OutlineView(
          outline: nodes,
          controller: controller,
          focusNode: focusNode,
        ),
      ),
    );

    await tester.pumpWidget(view(null));
    await tester.pumpWidget(view([_node('הקדמה', 1)]));
    await tester.pumpAndSettle();

    Iterable<NavTreeTile> tiles() =>
        tester.widgetList<NavTreeTile>(find.byType(NavTreeTile));
    expect(tiles().singleWhere((tile) => tile.isSelected).title, 'הקדמה');

    await tester.pumpWidget(
      view([
        _node('שער', 1),
        _node('פרק', 1, [
          _node('סעיף', 1, [_node('פסקה', 1)]),
        ]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tiles().singleWhere((tile) => tile.isSelected).title, 'פסקה');
    expect(
      tiles().singleWhere((tile) => tile.title == 'סעיף').isExpanded,
      isTrue,
    );
  });
}
