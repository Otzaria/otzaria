import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:pdfrx/pdfrx.dart';

class _PageController extends PdfViewerController {
  int page = 1;
  final _listeners = <VoidCallback>[];

  @override
  bool get isReady => true;

  @override
  int? get pageNumber => page;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void showPage(int newPage) {
    page = newPage;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

PdfOutlineNode _node(String title, int page) => PdfOutlineNode(
  title: title,
  dest: PdfDest(page, PdfDestCommand.fit, null),
  children: const [],
);

void main() {
  // כמו מסכת בתלמוד: צומת שורש אחד ודף לכל צומת בן.
  final outline = [
    PdfOutlineNode(
      title: 'מסכת',
      dest: PdfDest(1, PdfDestCommand.fit, null),
      children: [for (var p = 1; p <= 40; p++) _node('דף $p', p)],
    ),
  ];

  Future<_PageController> pumpOutline(WidgetTester tester) async {
    final controller = _PageController();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutlineView(
            outline: outline,
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  List<NavTreeTile> tiles(WidgetTester tester) =>
      tester.widgetList<NavTreeTile>(find.byType(NavTreeTile)).toList();

  String selectedTitle(WidgetTester tester) =>
      tiles(tester).singleWhere((tile) => tile.isSelected).title;

  testWidgets('מעבר עמוד בונה מחדש רק את השורות שהסימון שלהן השתנה', (
    tester,
  ) async {
    final controller = await pumpOutline(tester);
    final before = tiles(tester);

    controller.showPage(2);
    await tester.pump();

    final after = tiles(tester);
    expect(after.length, before.length);
    final rebuilt = [
      for (var i = 0; i < after.length; i++)
        if (!identical(before[i], after[i])) after[i].title,
    ];
    expect(rebuilt, unorderedEquals(['דף 1', 'דף 2']));
  });

  testWidgets('הסימון עובר עם העמוד, גם בגלילה ידנית של הרשימה', (
    tester,
  ) async {
    final controller = await pumpOutline(tester);
    expect(selectedTitle(tester), 'דף 1');

    controller.showPage(7);
    await tester.pumpAndSettle();
    expect(selectedTitle(tester), 'דף 7');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SingleChildScrollView)),
    );
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    controller.showPage(12);
    await tester.pump();
    expect(selectedTitle(tester), 'דף 12');
    await gesture.up();
    await tester.pumpAndSettle();

    controller.showPage(3);
    await tester.pumpAndSettle();
    expect(selectedTitle(tester), 'דף 3');
  });
}
