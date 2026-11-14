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
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _PageController(page);
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

  Finder row(String title) => find.byWidgetPredicate(
    (widget) => widget is NavTreeTile && widget.title == title,
  );

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
}
