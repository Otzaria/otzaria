import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// לשונית מדומה עם חיפוש משני: כותרת עם אייקון החיפוש ושלוש שורות.
class _Host extends StatefulWidget {
  final String initialText;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowUp;
  final VoidCallback? onClear;
  final int rowCount;

  const _Host({
    this.initialText = '',
    this.onArrowDown,
    this.onArrowUp,
    this.onClear,
    this.rowCount = 3,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final host = NavPanelSearchHost();
  late final controller = TextEditingController(text: widget.initialText);
  final focus = FocusNode();

  @override
  void dispose() {
    host.dispose();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NavPanelSearchScope(
      host: host,
      child: NavPanelCollapsibleSearch(
        delegate: NavPanelSearchDelegate(
          controller: controller,
          focusNode: focus,
          hintText: 'איתור כותרת...',
          onClear: widget.onClear,
          onArrowDown: widget.onArrowDown,
          onArrowUp: widget.onArrowUp,
        ),
        child: NavTreeFocusGroup(
          child: ListView(
            children: [
              const NavTreeHeader(
                title: 'בראשית',
                trailing: NavPanelSearchToggle(),
              ),
              for (var i = 0; i < widget.rowCount; i++)
                NavTreeGroupCard(
                  isGroupStart: i == 0,
                  isGroupEnd: i == widget.rowCount - 1,
                  child: NavTreeTile.category(
                    title: 'שורה $i',
                    level: 0,
                    isSelected: i == 1,
                    onTap: () {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SizedBox(width: 400, height: 700, child: child),
    ),
  ),
);

Future<void> _openField(WidgetTester tester) async {
  await tester.tap(find.byType(NavPanelSearchToggle));
  await tester.pumpAndSettle();
}

bool _fieldHasFocus(WidgetTester tester) =>
    tester.binding.focusManager.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<OtzariaSearchField>() !=
    null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('חיפוש משני בלשונית', () {
    testWidgets('השדה סגור, והאייקון יושב בכותרת הרשימה', (tester) async {
      await tester.pumpWidget(wrap(const _Host()));
      await tester.pumpAndSettle();

      expect(find.byType(OtzariaSearchField), findsNothing);
      expect(
        find.descendant(
          of: find.byType(NavTreeHeader),
          matching: find.byIcon(FluentIcons.search_24_regular),
        ),
        findsOneWidget,
      );
    });

    testWidgets('לחיצה על האייקון פותחת שדה ממוקד ומסתירה את האייקון', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const _Host()));
      await tester.pumpAndSettle();

      await _openField(tester);

      expect(find.byType(OtzariaSearchField), findsOneWidget);
      expect(_fieldHasFocus(tester), isTrue);
      expect(find.byType(IconButton).hitTestable(), findsOneWidget);
      expect(find.byIcon(FluentIcons.search_24_regular), findsNothing);
    });

    testWidgets('X סוגר את השדה, מנקה אותו ומפעיל onClear', (tester) async {
      var clears = 0;
      await tester.pumpWidget(wrap(_Host(onClear: () => clears++)));
      await tester.pumpAndSettle();

      await _openField(tester);
      await tester.enterText(find.byType(OtzariaSearchField), 'אבג');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
      await tester.pumpAndSettle();

      expect(find.byType(OtzariaSearchField), findsNothing);
      expect(clears, 1);
      final state = tester.state<_HostState>(find.byType(_Host));
      expect(state.controller.text, isEmpty);
    });

    testWidgets('Escape בשדה סוגר אותו', (tester) async {
      await tester.pumpWidget(wrap(const _Host()));
      await tester.pumpAndSettle();

      await _openField(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(OtzariaSearchField), findsNothing);
    });

    testWidgets('סינון קיים — השדה מוצג פתוח בלי לחטוף פוקוס', (tester) async {
      await tester.pumpWidget(wrap(const _Host(initialText: 'פרק')));
      await tester.pumpAndSettle();

      expect(find.byType(OtzariaSearchField), findsOneWidget);
      expect(_fieldHasFocus(tester), isFalse);
    });

    testWidgets('טקסט שהוחל מבחוץ על שדה סגור פותח אותו', (tester) async {
      await tester.pumpWidget(wrap(const _Host()));
      await tester.pumpAndSettle();

      tester.state<_HostState>(find.byType(_Host)).controller.text = 'פרק';
      await tester.pumpAndSettle();

      expect(find.byType(OtzariaSearchField), findsOneWidget);
    });

    testWidgets('אייקון מחוץ לחיפוש מתקפל אינו מצויר', (tester) async {
      await tester.pumpWidget(wrap(const NavPanelSearchToggle()));

      expect(find.byType(IconButton), findsNothing);
    });
  });

  // issue #1725 — האייקון נגלל עם הכותרת; במקומו מופיע אייקון צף.
  group('אייקון צף כשהכותרת נגללה', () {
    Finder searchIcon() => find.byIcon(FluentIcons.search_24_regular);
    Finder listScrollable() => find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );

    Future<void> scrollBy(WidgetTester tester, double dy) async {
      await tester.drag(find.byType(ListView), Offset(0, dy));
      await tester.pumpAndSettle();
    }

    testWidgets('מופיע רק אחרי שהכותרת יצאה מהתחום ונעלם כשהיא חוזרת', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const _Host(rowCount: 80)));
      await tester.pumpAndSettle();
      expect(searchIcon(), findsOneWidget);

      await scrollBy(tester, -20);
      expect(searchIcon(), findsOneWidget, reason: 'הכותרת עדיין בתחום');

      await scrollBy(tester, -1500);
      expect(find.byType(NavTreeHeader), findsNothing);
      expect(searchIcon().hitTestable(), findsOneWidget);

      await scrollBy(tester, 3000);
      expect(searchIcon(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavTreeHeader),
          matching: searchIcon(),
        ),
        findsOneWidget,
      );
    });

    testWidgets('לחיצה עליו פותחת שדה ממוקד בלי לגלול', (tester) async {
      await tester.pumpWidget(wrap(const _Host(rowCount: 80)));
      await tester.pumpAndSettle();
      await scrollBy(tester, -1500);
      final offset = tester
          .state<ScrollableState>(listScrollable())
          .position
          .pixels;

      await tester.tap(searchIcon());
      await tester.pumpAndSettle();

      expect(find.byType(OtzariaSearchField), findsOneWidget);
      expect(_fieldHasFocus(tester), isTrue);
      expect(searchIcon(), findsNothing);
      expect(
        tester.state<ScrollableState>(listScrollable()).position.pixels,
        offset,
      );
    });

    // issue #1942 — שכבת הריחוף המרובעת של הכפתור בלטה מחוץ לעיגול.
    testWidgets('הרקע העגול חותך את שכבת הריחוף של הכפתור', (tester) async {
      await tester.pumpWidget(wrap(const _Host(rowCount: 80)));
      await tester.pumpAndSettle();
      await scrollBy(tester, -1500);

      final circle = tester.widget<Material>(
        find.ancestor(
          of: searchIcon(),
          matching: find.byWidgetPredicate(
            (w) => w is Material && w.shape is CircleBorder,
          ),
        ),
      );
      expect(circle.clipBehavior, isNot(Clip.none));
    });
  });

  group('מקלדת בשדה החיפוש', () {
    testWidgets('חץ למטה מעביר פוקוס לשורה המסומנת', (tester) async {
      await tester.pumpWidget(wrap(const _Host()));
      await tester.pumpAndSettle();
      await _openField(tester);
      expect(_fieldHasFocus(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      String? focusedRowTitle() => tester
          .binding
          .focusManager
          .primaryFocus
          ?.context
          ?.findAncestorWidgetOfExactType<NavTreeTile>()
          ?.title;

      expect(focusedRowTitle(), 'שורה 1');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedRowTitle(), 'שורה 2');
    });

    testWidgets('onArrowDown/Up — דפדוף בתוצאות בלי לעזוב את השדה', (
      tester,
    ) async {
      var downs = 0;
      var ups = 0;
      await tester.pumpWidget(
        wrap(_Host(onArrowDown: () => downs++, onArrowUp: () => ups++)),
      );
      await tester.pumpAndSettle();
      await _openField(tester);
      final beforeFocus = tester.binding.focusManager.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(downs, 2);
      expect(ups, 1);
      expect(tester.binding.focusManager.primaryFocus, beforeFocus);
    });

    testWidgets('חץ ימין/שמאל נשארים בטקסט', (tester) async {
      await tester.pumpWidget(wrap(const _Host()));
      await tester.pumpAndSettle();
      await _openField(tester);
      await tester.enterText(find.byType(OtzariaSearchField), 'אבג');
      await tester.pumpAndSettle();
      final beforeFocus = tester.binding.focusManager.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(tester.binding.focusManager.primaryFocus, beforeFocus);
      expect(find.text('אבג'), findsOneWidget);
    });
  });

  // issue #1268 — בתצוגה מפוצלת החלון רחב אך החלונית צרה; החלטות רוחב
  // (מיקוד יזום של שדה) חייבות להימדד לפי החלונית.
  group('רוחב לפי החלונית ולא לפי החלון (issue #1268)', () {
    testWidgets('חלונית צרה בתוך חלון רחב — אינה רחבה', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      bool? isWide;
      await tester.pumpWidget(
        MaterialApp(
          home: NavPanelPaneWidthScope(
            width: 300,
            child: Builder(
              builder: (context) {
                isWide = NavPanelSearch.isWide(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(isWide, isFalse);
    });

    testWidgets('כל חלונית ב-SplitPaneView מקבלת את רוחבה', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      double? paneWidth;
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              SizedBox(
                width: 320,
                child: SplitPaneView.buildPane(
                  _FakePane('א'),
                  (_) => Builder(
                    builder: (context) {
                      paneWidth = NavPanelPaneWidthScope.maybeOf(context);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      expect(paneWidth, 320);
    });
  });
}

class _FakePane extends OpenedTab {
  _FakePane(super.title);
  @override
  OpenedTab clone() => this;
  @override
  Map<String, dynamic> toJson() => {'type': '_FakePane', 'title': title};
}
