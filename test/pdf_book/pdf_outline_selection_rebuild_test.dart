import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:pdfrx/pdfrx.dart';

class _PageController extends PdfViewerController {
  int page = 1;
  final _listeners = <VoidCallback>[];
  final goToPageRequests = <int>[];

  @override
  bool get isReady => true;

  @override
  int? get pageNumber => page;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Future<void> goToPage({
    required int pageNumber,
    PdfPageAnchor? anchor,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    goToPageRequests.add(pageNumber);
    showPage(pageNumber);
  }

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

  Future<_PageController> pumpOutline(
    WidgetTester tester, {
    _PageController? controller,
    List<PdfOutlineNode>? nodes,
    Future<void> Function(int)? onNavigateToPage,
  }) async {
    final pageController = controller ?? _PageController();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutlineView(
            outline: nodes ?? outline,
            controller: pageController,
            focusNode: focusNode,
            onNavigateToPage: onNavigateToPage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pageController;
  }

  List<NavTreeTile> tiles(WidgetTester tester) =>
      tester.widgetList<NavTreeTile>(find.byType(NavTreeTile)).toList();

  String selectedTitle(WidgetTester tester) =>
      tiles(tester).singleWhere((tile) => tile.isSelected).title;

  Finder row(String title) => find.byWidgetPredicate(
    (widget) => widget is NavTreeTile && widget.title == title,
  );

  List<String> rebuiltTitles(WidgetTester tester, List<NavTreeTile> before) {
    final after = tiles(tester);
    expect(after.length, before.length);
    return [
      for (var i = 0; i < after.length; i++)
        if (!identical(before[i], after[i])) after[i].title,
    ];
  }

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

  testWidgets('לחיצה על סימניה בעץ גדול בונה מחדש רק שתי שורות', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _PageController();
    final requests = <int>[];
    await pumpOutline(
      tester,
      controller: controller,
      nodes: [
        PdfOutlineNode(
          title: 'מסכת',
          dest: PdfDest(1, PdfDestCommand.fit, null),
          children: [for (var p = 1; p <= 242; p++) _node('דף $p', p)],
        ),
      ],
      onNavigateToPage: (page) async {
        requests.add(page);
        controller.showPage(page);
      },
    );
    final before = tiles(tester);
    expect(before, hasLength(243));

    await tester.tap(row('דף 2'));
    await tester.pump();

    expect(requests, [2]);
    expect(controller.goToPageRequests, isEmpty);
    expect(selectedTitle(tester), 'דף 2');
    expect(rebuiltTitles(tester, before), unorderedEquals(['דף 1', 'דף 2']));
    await tester.pumpAndSettle();
  });

  for (final duringDrag in [false, true]) {
    testWidgets(
      'לחיצה חוזרת על העמוד הנוכחי ממרכזת אותו ${duringDrag ? "בזמן" : "אחרי"} גלילה ידנית',
      (tester) async {
        final controller = _PageController()..page = 20;
        final requests = <int>[];
        await pumpOutline(
          tester,
          controller: controller,
          onNavigateToPage: (page) async {
            requests.add(page);
            controller.showPage(page);
          },
        );
        final scrollView = find.byType(SingleChildScrollView);
        final scrollController = tester
            .widget<SingleChildScrollView>(scrollView)
            .controller!;
        final centeredOffset = scrollController.offset;
        expect(centeredOffset, greaterThan(0));
        expect(
          tester.getCenter(row('דף 20')).dy,
          closeTo(tester.getCenter(scrollView).dy, 1),
        );

        final gesture = await tester.startGesture(tester.getCenter(scrollView));
        await gesture.moveBy(const Offset(0, -24));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump();
        if (!duringDrag) {
          await gesture.up();
          await tester.pumpAndSettle();
        }
        expect(scrollController.offset, greaterThan(centeredOffset + 50));
        final before = tiles(tester);

        if (duringDrag) {
          // Keep the drag active while invoking the production row action.
          tester.widget<NavTreeTile>(row('דף 20')).onTap!();
        } else {
          await tester.tap(row('דף 20'));
        }
        await tester.pumpAndSettle();

        expect(requests, [20]);
        expect(controller.goToPageRequests, isEmpty);
        expect(selectedTitle(tester), 'דף 20');
        expect(scrollController.offset, closeTo(centeredOffset, 1));
        expect(rebuiltTitles(tester, before), isEmpty);
        if (duringDrag) {
          await gesture.up();
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('ניווט מושהה ממתין לעדכון הקונטרולר בלי לבנות את העץ', (
    tester,
  ) async {
    final controller = _PageController();
    final completion = Completer<void>();
    final requests = <int>[];
    await pumpOutline(
      tester,
      controller: controller,
      onNavigateToPage: (page) async {
        requests.add(page);
        await completion.future;
        controller.showPage(page);
      },
    );
    final before = tiles(tester);

    await tester.tap(row('דף 2'));
    await tester.pump();
    expect(requests, [2]);
    expect(controller.goToPageRequests, isEmpty);
    expect(selectedTitle(tester), 'דף 1');
    expect(rebuiltTitles(tester, before), isEmpty);

    completion.complete();
    await tester.pumpAndSettle();
    expect(requests, [2]);
    expect(controller.goToPageRequests, isEmpty);
    expect(selectedTitle(tester), 'דף 2');
    expect(rebuiltTitles(tester, before), unorderedEquals(['דף 1', 'דף 2']));
  });

  testWidgets('ללא callback לחיצה מנווטת פעם אחת דרך הקונטרולר', (
    tester,
  ) async {
    final controller = await pumpOutline(tester);
    final before = tiles(tester);

    await tester.tap(row('דף 2'));
    await tester.pumpAndSettle();

    expect(controller.goToPageRequests, [2]);
    expect(selectedTitle(tester), 'דף 2');
    expect(rebuiltTitles(tester, before), unorderedEquals(['דף 1', 'דף 2']));
  });

  testWidgets('סימניה ללא יעד אינה מנווטת או בונה מחדש את העץ', (tester) async {
    final requests = <int>[];
    final controller = await pumpOutline(
      tester,
      nodes: [
        PdfOutlineNode(title: 'ללא יעד', dest: null, children: const []),
        ...outline,
      ],
      onNavigateToPage: (page) async => requests.add(page),
    );
    final before = tiles(tester);

    await tester.tap(row('ללא יעד'));
    await tester.pumpAndSettle();

    expect(requests, isEmpty);
    expect(controller.goToPageRequests, isEmpty);
    expect(selectedTitle(tester), 'דף 1');
    expect(rebuiltTitles(tester, before), isEmpty);
  });

  testWidgets('החלפת קונטרולר מסירה את המאזין מהקונטרולר הקודם', (
    tester,
  ) async {
    final original = await pumpOutline(tester);
    final replacement = await pumpOutline(
      tester,
      controller: _PageController(),
    );
    expect(original._listeners, isEmpty);
    expect(replacement._listeners, hasLength(1));

    original.showPage(3);
    await tester.pump();
    expect(selectedTitle(tester), 'דף 1');
    replacement.showPage(4);
    await tester.pumpAndSettle();
    expect(selectedTitle(tester), 'דף 4');
  });

  testWidgets('סגירה לפני גלילה מתוזמנת מסירה את המאזין בבטחה', (tester) async {
    final controller = await pumpOutline(tester);
    controller.showPage(2);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller._listeners, isEmpty);
    controller.showPage(3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
