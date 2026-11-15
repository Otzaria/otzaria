import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:positioned_sliver_list/positioned_sliver_list.dart';

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
  late StateSetter rebuildOutline;
  late FocusNode beforeFocus;
  late FocusNode afterFocus;
  late NavPanelSearchHost searchHost;
  var paneOpen = true;
  setUp(() {
    outline = _bigOutline();
    paneOpen = true;
  });

  Future<_PageController> pumpOutline(
    WidgetTester tester, {
    int page = 1,
    bool disableAnimations = false,
    bool withNeighbors = false,
    bool withHost = false,
    Future<void> Function(int)? onNavigate,
    double width = 800,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _PageController(page);
    final focusNode = FocusNode();
    beforeFocus = FocusNode(debugLabel: 'before outline');
    afterFocus = FocusNode(debugLabel: 'after outline');
    searchHost = NavPanelSearchHost();
    if (withHost && withNeighbors) {
      // מאפשר לבדיקה לצאת אל השכנים במקום להקיף את חלונית הניווט.
      searchHost.paneFocusScope.traversalEdgeBehavior =
          TraversalEdgeBehavior.parentScope;
    }
    addTearDown(focusNode.dispose);
    addTearDown(beforeFocus.dispose);
    addTearDown(afterFocus.dispose);
    addTearDown(searchHost.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 600),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuildOutline = setState;
                Widget child = OutlineView(
                  outline: outline,
                  controller: controller,
                  focusNode: focusNode,
                  isPaneOpen: paneOpen,
                  onNavigateToPage: onNavigate,
                );
                if (withHost) {
                  child = NavPanelSearchScope(host: searchHost, child: child);
                }
                if (withNeighbors) {
                  child = Column(
                    children: [
                      Focus(
                        focusNode: beforeFocus,
                        child: const SizedBox(height: 24),
                      ),
                      Expanded(child: child),
                      Focus(
                        focusNode: afterFocus,
                        child: const SizedBox(height: 24),
                      ),
                    ],
                  );
                }
                return child;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Finder row(String title, {bool skipOffstage = true}) =>
      find.byWidgetPredicate(
        (widget) => widget is NavTreeTile && widget.title == title,
        skipOffstage: skipOffstage,
      );

  ScrollController scrollController(WidgetTester tester) =>
      tester.widget<SuperListView>(find.byType(SuperListView)).controller!;

  ({bool start, bool end}) groupFlags(WidgetTester tester, String title) {
    final card = tester
        .element(row(title))
        .findAncestorWidgetOfExactType<NavTreeGroupCard>()!;
    return (start: card.isGroupStart, end: card.isGroupEnd);
  }

  bool isOnScreen(WidgetTester tester, String title) {
    final rect = tester.getRect(row(title));
    final viewport = tester.getRect(find.byType(SuperListView));
    return rect.top >= viewport.top && rect.bottom <= viewport.bottom;
  }

  String? focusedTitle(WidgetTester tester) => tester
      .binding
      .focusManager
      .primaryFocus
      ?.context
      ?.findAncestorWidgetOfExactType<NavTreeTile>()
      ?.title;

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

  Future<void> shiftTab(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  Future<void> beginEntry(WidgetTester tester) async {
    tester.widget<TextField>(find.byType(TextField)).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'PDF outline entry',
    );
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
    expect(
      tester.getCenter(row('סימן 2-100')).dy,
      closeTo(tester.getCenter(find.byType(SuperListView)).dy, 1),
    );
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
    expect(
      tester.getCenter(row('סעיף 2-60-3')).dy,
      closeTo(tester.getCenter(find.byType(SuperListView)).dy, 1),
    );
    expect(tester.widget<NavTreeTile>(row('פרק 2-60')).isExpanded, isTrue);
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(60));
  });

  testWidgets('סינון מציג את ההתאמות בעצלות, גם בסוף הרשימה', (tester) async {
    await pumpOutline(tester);
    await tester.tap(find.byType(TextField));
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
    await tester.tap(find.byType(TextField));
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
    expect(
      tester.getCenter(row('סימן 2-100')).dy,
      closeTo(tester.getCenter(find.byType(SuperListView)).dy, 1),
    );
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
    rebuildOutline(() {
      outline = [for (var i = 0; i < 300; i++) _node('דף $i', i + 1)];
      controller.page = 200;
    });
    await tester.pumpAndSettle();
    expect(row('חלק 0'), findsNothing);
    expect(tester.widget<NavTreeTile>(row('דף 199')).isSelected, isTrue);
    expect(
      tester.getCenter(row('דף 199')).dy,
      closeTo(tester.getCenter(find.byType(SuperListView)).dy, 1),
    );
  });

  testWidgets('Tab חוזר לסעיף הנבחר גם אחרי גלילה ידנית רחוקה', (tester) async {
    await pumpOutline(tester, page: 501);
    final controller = scrollController(tester);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    await tester.pumpAndSettle();
    final focusedTile = tester.binding.focusManager.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<NavTreeTile>();
    expect(focusedTile?.title, 'סימן 2-0');
    expect(isOnScreen(tester, 'סימן 2-0'), isTrue);
    expect(find.byType(NavTreeTile).evaluate().length, lessThan(60));
  });

  testWidgets('סינון בזמן גלילה אל הסעיף הפעיל עוצר יעד שנעלם', (tester) async {
    final controller = await pumpOutline(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    controller.showPage(601);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.enterText(find.byType(TextField), 'סימן 3-249');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('סינון בזמן גלילה מעדכן את מיקום היעד שנותר', (tester) async {
    final controller = await pumpOutline(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    controller.showPage(601);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'סימן 2-1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<NavTreeTile>(row('סימן 2-100')).isSelected, isTrue);
    expect(
      tester.getCenter(row('סימן 2-100')).dy,
      closeTo(tester.getRect(find.byType(SuperListView)).center.dy, 1),
    );
  });

  testWidgets('כיווץ בזמן גלילה מעדכן את אינדקס היעד', (tester) async {
    final controller = await pumpOutline(tester);
    final collapse = tester.widget<NavTreeTile>(row('חלק 0')).onToggleExpand!;
    controller.showPage(601);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    collapse();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getCenter(row('סימן 2-100')).dy,
      closeTo(tester.getCenter(find.byType(SuperListView)).dy, 1),
    );
  });

  testWidgets('החלפת מסמך בזמן גלילה מבטלת את היעד הישן', (tester) async {
    final controller = await pumpOutline(tester);
    controller.showPage(601);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    rebuildOutline(() {
      outline = [for (var i = 0; i < 20; i++) _node('חדש $i', i + 1)];
      controller.page = 10;
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<NavTreeTile>(row('חדש 9')).isSelected, isTrue);
    expect(isOnScreen(tester, 'חדש 9'), isTrue);
  });

  testWidgets('סגירת חלונית בזמן גלילה עוצרת אותה ופתיחה ממרכזת מחדש', (
    tester,
  ) async {
    final controller = await pumpOutline(tester);
    controller.showPage(601);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    rebuildOutline(() => paneOpen = false);
    await tester.pump();
    final offset = scrollController(tester).offset;
    await tester.pumpAndSettle();
    expect(scrollController(tester).offset, offset);
    rebuildOutline(() => paneOpen = true);
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(row('סימן 2-100')).dy,
      closeTo(tester.getCenter(find.byType(SuperListView)).dy, 1),
    );
  });

  testWidgets('מעבר עמוד נוסף בזמן גלילה משאיר רק את היעד העדכני', (
    tester,
  ) async {
    final controller = await pumpOutline(tester);
    controller.showPage(601);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    controller.showPage(201);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<NavTreeTile>(row('סימן 0-200')).isSelected, isTrue);
    expect(
      tester.getCenter(row('סימן 0-200')).dy,
      closeTo(tester.getCenter(find.byType(SuperListView)).dy, 1),
    );
    expect(row('סימן 2-100'), findsNothing);
  });

  testWidgets('כיווץ ענף היעד בזמן גלילה עוצר יעד שנעלם', (tester) async {
    final controller = await pumpOutline(tester, page: 501);
    final collapse = tester.widget<NavTreeTile>(row('חלק 2')).onToggleExpand!;
    controller.showPage(601);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    collapse();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(row('סימן 2-100'), findsNothing);
  });

  testWidgets('שורות מחוץ לתצוגה משתחררות אחרי החלפת בחירה', (
    tester,
  ) async {
    final controller = await pumpOutline(tester, page: 501);
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(row('סימן 2-0', skipOffstage: false), findsNothing);
    controller.showPage(751);
    await tester.pumpAndSettle();
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(row('סימן 2-0', skipOffstage: false), findsNothing);
    expect(row('סימן 3-0', skipOffstage: false), findsNothing);
    expect(
      find.byType(NavTreeTile, skipOffstage: false).evaluate().length,
      lessThan(60),
    );
  });

  testWidgets('השורות שומרות שם נגיש ומצב נבחר ומורחב', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOutline(tester);
    final selected = tester.getSemantics(row('סימן 0-0')).getSemanticsData();
    expect(selected.label, contains('סימן 0-0'));
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    final parent = tester.getSemantics(row('חלק 0')).getSemanticsData();
    expect(parent.flagsCollection.isExpanded, Tristate.isTrue);
    semantics.dispose();
  });
  testWidgets('יעד עמוד חדש בזמן גרירה מקבל Tab', (tester) async {
    final controller = await pumpOutline(tester, page: 501);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SuperListView)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final offset = scrollController(tester).offset;
    controller.showPage(751);
    await tester.pump();
    expect(scrollController(tester).offset, offset);
    expect(row('סימן 3-0', skipOffstage: false), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    await beginEntry(tester);
    await tester.pumpAndSettle();
    final focused = tester.binding.focusManager.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<NavTreeTile>();
    expect(focused?.title, 'סימן 3-0');
  });

  testWidgets('Tab ו־Shift+Tab עוברים לנבחר ולשכנים במארח ניווט', (
    tester,
  ) async {
    await pumpOutline(tester, page: 501, withNeighbors: true, withHost: true);
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    beforeFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focusedTitle(tester), 'סימן 2-0');
    await shiftTab(tester);
    expect(beforeFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focusedTitle(tester), isNot('סימן 2-0'));
    await shiftTab(tester);
    expect(focusedTitle(tester), 'סימן 2-0');
    await shiftTab(tester);
    expect(beforeFocus.hasFocus, isTrue);
    afterFocus.requestFocus();
    await tester.pump();
    await shiftTab(tester);
    expect(fieldHasFocus(tester), isTrue);
  });

  testWidgets('כניסה מהסרגל עם חץ למטה מגלה את הנבחר', (tester) async {
    await pumpOutline(tester, page: 501, withHost: true);
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedTitle(tester), 'סימן 2-0');
    expect(isOnScreen(tester, 'סימן 2-0'), isTrue);
  });

  testWidgets('שינוי עמוד בזמן כניסה ממקד את היעד העדכני', (tester) async {
    final controller = await pumpOutline(tester, page: 501);
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    controller.showPage(751);
    await tester.pumpAndSettle();
    expect(focusedTitle(tester), 'סימן 3-0');
    expect(isOnScreen(tester, 'סימן 3-0'), isTrue);
  });

  testWidgets('לחיצת עכבר מבטלת כניסת פוקוס ממתינה לסעיף הישן', (tester) async {
    final navigations = <int>[];
    await pumpOutline(
      tester,
      page: 501,
      onNavigate: (page) async => navigations.add(page),
    );
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    await tester.tap(row('סימן 0-0'));
    await tester.pumpAndSettle();
    expect(navigations, [1]);
    expect(focusedTitle(tester), isNot('סימן 2-0'));
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('PDF outline entry'),
    );
  });

  testWidgets('כיווץ יעד בזמן כניסה אינו ממקד שורה שהוסרה', (tester) async {
    await pumpOutline(tester, page: 501);
    final collapse = tester.widget<NavTreeTile>(row('חלק 2')).onToggleExpand!;
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    collapse();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focusedTitle(tester), isNot('סימן 2-0'));
    expect(row('סימן 2-0', skipOffstage: false), findsNothing);
  });

  testWidgets('החלפת מסמך בזמן כניסה מבטלת מיקוד של המסמך הישן', (
    tester,
  ) async {
    final controller = await pumpOutline(tester, page: 501);
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    rebuildOutline(() {
      outline = [for (var i = 0; i < 20; i++) _node('חדש $i', i + 1)];
      controller.page = 10;
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focusedTitle(tester), isNot('סימן 2-0'));
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('PDF outline entry'),
    );
    expect(tester.widget<NavTreeTile>(row('חדש 9')).isSelected, isTrue);
  });

  testWidgets('סגירת חלונית בזמן כניסה מבטלת את הפוקוס הממתין', (tester) async {
    await pumpOutline(tester, page: 501);
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    rebuildOutline(() => paneOpen = false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focusedTitle(tester), isNull);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('PDF outline entry'),
    );
  });

  testWidgets('הסרת המסך בזמן כניסה אינה משאירה מוקד מעבר חי', (tester) async {
    await pumpOutline(tester, page: 501);
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('PDF outline entry'),
    );
  });

  testWidgets('כניסה לסעיף עם ילדים ואז Enter מנווטת ואינה מכווצת', (
    tester,
  ) async {
    outline = [
      for (var i = 0; i < 1000; i++)
        _node('כותרת $i', i * 10 + 1, i == 500 ? [_node('תת סעיף', 5002)] : []),
    ];
    final navigations = <int>[];
    await pumpOutline(
      tester,
      page: 5001,
      onNavigate: (page) async => navigations.add(page),
    );
    scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await beginEntry(tester);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(navigations, [5001]);
    expect(tester.widget<NavTreeTile>(row('כותרת 500')).isExpanded, isTrue);
  });

  for (final appearance in [
    (
      name: 'בהיר',
      seed: AppSeedColors.defaultLight,
      brightness: Brightness.light,
    ),
    (name: 'כהה', seed: AppSeedColors.defaultDark, brightness: Brightness.dark),
    (name: 'לבן', seed: AppSeedColors.white, brightness: Brightness.light),
  ]) {
    for (final width in [360.0, 800.0]) {
      testWidgets(
        'כניסה ויציאה עם RTL וטקסט מוגדל: ${appearance.name} $width',
        (tester) async {
          final scheme = AppThemeData.createColorScheme(
            appearance.seed,
            appearance.brightness,
          );
          await pumpOutline(
            tester,
            page: 501,
            withNeighbors: true,
            width: width,
            textScale: 1.3,
            theme: AppThemeData.light(
              scheme,
              compactMenuMode: false,
              variant: AppThemeVariant.ofSeed(appearance.seed),
            ),
          );
          scrollController(tester).jumpTo(0);
          await tester.pumpAndSettle();
          beforeFocus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(fieldHasFocus(tester), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(focusedTitle(tester), 'סימן 2-0');
          expect(isOnScreen(tester, 'סימן 2-0'), isTrue);
          await shiftTab(tester);
          expect(fieldHasFocus(tester), isTrue);
          await shiftTab(tester);
          expect(beforeFocus.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
          expect(
            find.byType(NavTreeTile, skipOffstage: false).evaluate().length,
            lessThan(60),
          );
        },
      );
    }
  }
}
