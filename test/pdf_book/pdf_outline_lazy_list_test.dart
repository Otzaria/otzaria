import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:pdfrx/pdfrx.dart';

class _PageController extends PdfViewerController {
  _PageController(this.page);

  int page;
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

PdfOutlineNode _node(
  String title,
  int page, [
  List<PdfOutlineNode> children = const [],
]) => PdfOutlineNode(
  title: title,
  dest: PdfDest(page, PdfDestCommand.fit, null),
  children: children,
);

/// ארבעה חלקים עם 250 סימנים בכל אחד — 1004 צמתים, כולם גלויים כברירת מחדל.
List<PdfOutlineNode> _bigOutline() => [
  for (var part = 0; part < 4; part++)
    _node('חלק $part', part * 250 + 1, [
      for (var i = 0; i < 250; i++) _node('סימן $part-$i', part * 250 + i + 1),
    ]),
];

void main() {
  late List<PdfOutlineNode> outline;
  setUp(() => outline = _bigOutline());

  Future<_PageController> pumpOutline(
    WidgetTester tester, {
    int page = 1,
    bool disableAnimations = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _PageController(page);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: OutlineView(
              outline: outline,
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Finder row(String title) => find.byWidgetPredicate(
    (widget) => widget is NavTreeTile && widget.title == title,
  );

  ScrollController scrollController(WidgetTester tester) =>
      tester.widget<Scrollable>(find.byType(Scrollable).first).controller!;

  ({bool start, bool end}) groupFlags(WidgetTester tester, String title) {
    final card = tester
        .element(row(title))
        .findAncestorWidgetOfExactType<NavTreeGroupCard>()!;
    return (start: card.isGroupStart, end: card.isGroupEnd);
  }

  bool isOnScreen(WidgetTester tester, String title) {
    final rect = tester.getRect(row(title));
    return rect.top >= 0 && rect.bottom <= 600;
  }

  testWidgets('עץ של אלף צמתים בונה רק את השורות שבתצוגה', (tester) async {
    await pumpOutline(tester);
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(60));
    expect(row('חלק 0'), findsOneWidget);
    expect(row('סימן 3-249'), findsNothing);
  });

  testWidgets('מעבר לעמוד רחוק גולל את הסעיף הפעיל למרכז ומסמן אותו', (
    tester,
  ) async {
    final controller = await pumpOutline(tester);
    expect(row('סימן 2-100'), findsNothing);

    controller.showPage(2 * 250 + 101);
    await tester.pumpAndSettle();

    final tile = tester.widget<NavTreeTile>(row('סימן 2-100'));
    expect(tile.isSelected, isTrue);
    expect(tester.getCenter(row('סימן 2-100')).dy, closeTo(300, 1));
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(60));
  });

  testWidgets('פתיחה בעמוד רחוק גוללת אל הסעיף הפעיל', (tester) async {
    await pumpOutline(tester, page: 3 * 250 + 200);
    expect(isOnScreen(tester, 'סימן 3-199'), isTrue);
    expect(tester.widget<NavTreeTile>(row('סימן 3-199')).isSelected, isTrue);
  });

  testWidgets('סעיף עמוק תחת ענף סגור נפתח ונגלל לתצוגה', (tester) async {
    // ענף שאינו ילד ראשון סגור כברירת מחדל; היעד ברמה 2 שבתוכו.
    outline = [
      for (var part = 0; part < 4; part++)
        _node('חלק $part', part * 1000 + 1, [
          for (var i = 0; i < 100; i++)
            _node('פרק $part-$i', part * 1000 + i * 10 + 1, [
              for (var j = 0; j < 5; j++)
                _node('סעיף $part-$i-$j', part * 1000 + i * 10 + j + 2),
            ]),
        ]),
    ];
    final controller = await pumpOutline(tester);
    expect(row('סעיף 2-60-3'), findsNothing);

    controller.showPage(2 * 1000 + 60 * 10 + 3 + 2);
    await tester.pumpAndSettle();

    expect(tester.widget<NavTreeTile>(row('סעיף 2-60-3')).isSelected, isTrue);
    expect(tester.getCenter(row('סעיף 2-60-3')).dy, closeTo(300, 1));
    expect(tester.widget<NavTreeTile>(row('פרק 2-60')).isExpanded, isTrue);
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(60));
  });

  testWidgets('סינון מציג את ההתאמות בעצלות, גם בסוף הרשימה', (tester) async {
    await pumpOutline(tester);
    await tester.tap(find.byType(NavPanelSearchToggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'סימן');
    await tester.pumpAndSettle();

    expect(row('סימן 0-0'), findsOneWidget);
    expect(row('חלק 0'), findsNothing);
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(60));

    await tester.enterText(find.byType(TextField), 'סימן 3-24');
    await tester.pumpAndSettle();
    expect(row('סימן 3-24'), findsOneWidget);
    expect(row('סימן 3-249'), findsOneWidget);
    expect(row('סימן 2-24'), findsNothing);
  });

  testWidgets('חץ למטה ממשיך מעבר לתחתית התצוגה וגולל אחריו', (tester) async {
    await pumpOutline(tester);
    final inkWell = find.descendant(
      of: row('סימן 0-0'),
      matching: find.byType(InkWell),
    );
    Focus.of(
      tester.element(
        find.descendant(of: inkWell, matching: find.byType(Container)).first,
      ),
    ).requestFocus();
    await tester.pump();

    String focusedTitle() => tester.binding.focusManager.primaryFocus!.context!
        .findAncestorWidgetOfExactType<NavTreeTile>()!
        .title;
    expect(focusedTitle(), 'סימן 0-0');

    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(focusedTitle(), 'סימן 0-40');
    expect(isOnScreen(tester, 'סימן 0-40'), isTrue);

    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(focusedTitle(), 'סימן 0-0');
    expect(isOnScreen(tester, 'סימן 0-0'), isTrue);
  });

  testWidgets('כיווץ והרחבה מעדכנים את השורות ואת מסגרת הקבוצה', (
    tester,
  ) async {
    outline = [
      _node('א', 1, [
        _node('א1', 2, [_node('א1א', 3)]),
        _node('א2', 4, [_node('א2א', 5)]),
      ]),
      _node('ב', 10, [_node('ב1', 11)]),
    ];
    await pumpOutline(tester);
    // ברירת המחדל: השורשים ושרשרת הילד הראשון פתוחים.
    expect(row('א1א'), findsOneWidget);
    expect(row('א2א'), findsNothing);
    expect(groupFlags(tester, 'א'), (start: true, end: false));
    expect(groupFlags(tester, 'ב1'), (start: false, end: true));
    expect(groupFlags(tester, 'ב'), (start: false, end: false));

    tester.widget<NavTreeTile>(row('ב')).onToggleExpand!();
    await tester.pump();
    expect(row('ב1'), findsNothing);
    expect(groupFlags(tester, 'ב'), (start: false, end: true));

    tester.widget<NavTreeTile>(row('א2')).onToggleExpand!();
    await tester.pump();
    expect(row('א2א'), findsOneWidget);
    expect(tester.widget<NavTreeTile>(row('א2')).isExpanded, isTrue);

    tester.widget<NavTreeTile>(row('א')).onToggleExpand!();
    await tester.pump();
    expect(row('א1'), findsNothing);
    expect(row('א2א'), findsNothing);
    expect(groupFlags(tester, 'א'), (start: true, end: false));
  });

  testWidgets('סינון עם צומת שמופיע פעמיים אינו נכשל', (tester) async {
    outline = [
      _node('פרק', 1, [_node('פרק משנה', 2)]),
    ];
    await pumpOutline(tester);
    await tester.tap(find.byType(NavPanelSearchToggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'פרק');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(row('פרק'), findsOneWidget);
    expect(row('פרק משנה'), findsNWidgets(2));
  });

  testWidgets('הסעיף האחרון ממורכז ככל האפשר בלי גלילת יתר', (tester) async {
    await pumpOutline(tester, page: 4 * 250);
    final position = scrollController(tester).position;
    expect(tester.widget<NavTreeTile>(row('סימן 3-249')).isSelected, isTrue);
    expect(isOnScreen(tester, 'סימן 3-249'), isTrue);
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
  });

  testWidgets('עץ קצר אינו נגלל', (tester) async {
    outline = [
      _node('א', 1, [_node('א1', 2), _node('א2', 3)]),
    ];
    await pumpOutline(tester, page: 3);
    expect(tester.widget<NavTreeTile>(row('א2')).isSelected, isTrue);
    expect(scrollController(tester).offset, 0);
  });

  testWidgets('בהפחתת אנימציות הגלילה קופצת מיד', (tester) async {
    final controller = await pumpOutline(tester, disableAnimations: true);
    controller.showPage(2 * 250 + 101);
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(row('סימן 2-100')).dy, closeTo(300, 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('סגירה באמצע גלילה מונפשת אינה זורקת', (tester) async {
    final controller = await pumpOutline(tester);
    controller.showPage(2 * 250 + 101);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('החלפת העץ מציגה את השורות החדשות וגוללת אליהן', (tester) async {
    final controller = await pumpOutline(tester);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final replacement = [
      for (var i = 0; i < 300; i++) _node('דף $i', i + 1),
    ];
    controller.page = 200;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutlineView(
            outline: replacement,
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(row('חלק 0'), findsNothing);
    expect(tester.widget<NavTreeTile>(row('דף 199')).isSelected, isTrue);
    expect(tester.getCenter(row('דף 199')).dy, closeTo(300, 1));
  });
}
